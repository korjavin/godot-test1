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

## Last-drawn display state (see _process). "" means "never drawn / force redraw".
var _last_drawn_key: String = ""

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
		_last_drawn_key = ""  # player just [re]acquired — force one redraw
	# Redraw ONLY when what we would draw actually changed. We fold everything the
	# dial shows into one comparable key: ready flag, ability name, the cooldown
	# ratio quantized to arc-visible steps (1/128th of the ring — finer changes
	# don't move a pixel), and the remaining-seconds text at its displayed "%.1f"
	# precision. While the ability is READY and idle (the common case) the key is
	# constant, so the HUD costs zero redraws instead of one per frame.
	if player == null or not is_instance_valid(player) \
			or not player.has_method("get_ability_cooldown_ratio"):
		return
	var ratio: float = player.get_ability_cooldown_ratio()
	var ready: bool = player.is_ability_ready() if player.has_method("is_ability_ready") else ratio <= 0.0
	var ability_name: String = player.get_ability_name() if player.has_method("get_ability_name") else "Ability"
	var secs: float = player.get_ability_remaining() if player.has_method("get_ability_remaining") else 0.0
	var key := "%s|%s|%d|%.1f" % [ready, ability_name, roundi(ratio * 128.0), secs]
	if key != _last_drawn_key:
		_last_drawn_key = key
		queue_redraw()


func _draw() -> void:
	if player == null or not is_instance_valid(player):
		return
	if not player.has_method("get_ability_cooldown_ratio"):
		return

	var ratio: float = player.get_ability_cooldown_ratio()  # 1 = just used, 0 = ready
	var ready: bool = player.is_ability_ready() if player.has_method("is_ability_ready") else ratio <= 0.0
	var ability_name: String = player.get_ability_name() if player.has_method("get_ability_name") else "Ability"

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
	if not ready and player.has_method("get_ability_remaining"):
		var secs: float = player.get_ability_remaining()
		_draw_centered(font, "%.1f" % secs, Vector2(center.x, center.y + 22.0),
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
