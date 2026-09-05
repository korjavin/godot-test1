extends Control
## Special-ability cooldown indicator (top-right of the screen, under the coins).
##
## Shows the current character's special ability (the F key) as a radial dial that
## empties as the ability cools down, plus the ability's name and the seconds left.
##
## THREE STATES, NOT TWO — and this is the point of the contract below:
##   COOLING (khaki arc, seconds) the charge is still filling; wait.
##   GATED   (bone ring, a word)  charged, but something refuses the press right
##                                now — Windman airborne ("LAND") or in the rain
##                                ("RAIN"). There is nothing to wait for, so it
##                                must NOT render as still cooling: the dial
##                                names the fix instead of counting down at a
##                                player who has already paid.
##   READY   (amber ring)         press it.
## Before godot-test1-tw6 the gates were invisible here and a gated-but-charged
## ability painted a READY ring while every press bounced.
##
## Like the rest of the HUD it uses GROUP-BASED discovery — it finds the player via
## the "player" group rather than a hard reference — so it keeps working across
## respawns and character switches. It reads five small methods on the player:
##   get_ability_cooldown_ratio()  1.0 just-used → 0.0 ready (drives the arc)
##   get_ability_remaining()       seconds left (shown inside the dial)
##   get_ability_name()            label under the dial
##   is_ability_ready()            ACTUAL availability — cooldown AND gates
##   get_ability_block_reason()    "" or the gate's short label ("LAND"/"RAIN")
## The first and the fourth deliberately measure different things (see
## `is_ability_ready()` in player_controller.gd), which is what lets three states
## come out of two inputs that can never contradict each other: "cooling" is read
## off the ratio, never off `not is_ability_ready()`.
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
## "" when only the cooldown gates the ability, else the gate's label (see above).
var _block_reason: String = ""
## Quantized copies of ratio/secs used for the redraw change-check (see _process).
var _last_arc: int = -1
var _last_tenths: int = -1

## Seconds left of the "blocked press" red flash (0 = not flashing). Set by
## flash_blocked() on any refused F press; while it runs the ring and the F hint
## render in COLOR_BLOCKED, overriding all three states above.
var _blocked_timer: float = 0.0

# --- Layout ------------------------------------------------------------------
const DIAL_RADIUS: float = 40.0
const RING_WIDTH: float = 6.0
## Vertical centre of the dial within this control.
const DIAL_CENTER_Y: float = 56.0
const BLOCKED_FLASH_DURATION: float = 0.15

# --- Colours, and they all come off `HudTheme` -------------------------------
## Bead `godot-test1-y1o.25`, the HUD style spec: not one hex is typed here.
## THE THREE STATES ABOVE STAY THREE COLOURS, drawn out of the six the films
## gave us — the ring is the only thing on this region carrying the state, so
## two of them sharing a colour would put the whole readout on "arc or full
## ring", which at ratio ≈ 1 is no difference at all.
const COLOR_BACKDROP: Color = Color(HudTheme.INK, HudTheme.PANEL_ALPHA)
## The track the arc rides on: a frame, so the palette's frame colour.
const COLOR_TRACK: Color = HudTheme.STEEL
## Cooling: the corporation's neutral khaki — "not yours yet".
const COLOR_COOLING: Color = HudTheme.UNIT_KHAKI
## READY is this region's ONE amber thing, which is the whole rationing rule.
const COLOR_READY: Color = HudTheme.VISOR_AMBER
## Charged but gated: a BONE full ring — deliberately NOT the amber ready ring
## (the press would bounce) and NOT the khaki cooling arc (nothing is filling).
const COLOR_GATED: Color = HudTheme.BONE
## SEMANTIC, not stylistic, and so the one literal the palette does not own — the
## refused-press flash is the same "no" red as the captive cell bars, and
## `hero_hud`'s `COLOR_BARS` note one file along says why that stays a literal.
const COLOR_BLOCKED := Color(1.0, 0.25, 0.2)          # red flash on a blocked press


func _ready() -> void:
	# Never let this readout eat mouse clicks meant for the game.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Group registration so the player can flash us on a blocked press without
	# holding a hard reference (same discovery convention as the rest of the HUD).
	add_to_group("ability_hud")


func flash_blocked() -> void:
	"""Called (via the "ability_hud" group) when an F press is REFUSED — still
	cooling, or charged but gated — briefly renders the dial in red so the press
	visibly registers as 'not now' instead of feeling dead."""
	_blocked_timer = BLOCKED_FLASH_DURATION
	queue_redraw()


func _process(_delta: float) -> void:
	# Tick the blocked flash and force a redraw while it runs — including the
	# frame it expires, so the red reliably clears back to the normal colours.
	if _blocked_timer > 0.0:
		_blocked_timer = maxf(0.0, _blocked_timer - _delta)
		queue_redraw()
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
	var reason: String = player.get_ability_block_reason()
	# Redraw ONLY when what we would draw actually changed: ready flag, name,
	# the ratio quantized to arc-visible steps (1/128th of the ring — finer
	# changes don't move a pixel), and the seconds text at its displayed 0.1 s
	# precision. While the ability is READY and idle (the common case) nothing
	# changes, so the HUD costs zero redraws instead of one per frame.
	var arc := roundi(ratio * 128.0)
	var tenths := roundi(secs * 10.0)
	if _have_data and ready == _ability_ready and ability_name == _ability_name \
			and arc == _last_arc and tenths == _last_tenths and reason == _block_reason:
		return
	_have_data = true
	_ratio = ratio
	_ability_ready = ready
	_ability_name = ability_name
	_secs = secs
	_block_reason = reason
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
	# Blocked-press flash: while it runs, the arc and the F hint go red.
	var blocked := _blocked_timer > 0.0

	# Oswald Bold — the film's title-card face. HUD lettering and numerals are
	# the heading weight throughout (`hero_hud` does the same one file along).
	var font: Font = HudTheme.heading_font()
	var center := Vector2(size.x * 0.5, DIAL_CENTER_Y)

	# Dark disc behind everything so the dial reads over the bright sky.
	draw_circle(center, DIAL_RADIUS + 8.0, COLOR_BACKDROP)
	# Faint full ring (the "track" the cooldown arc rides on).
	draw_arc(center, DIAL_RADIUS, 0.0, TAU, 48, COLOR_TRACK, RING_WIDTH, true)

	# COOLING is read off the ratio, not off `not ready` — `ready` now also
	# answers for the gates, and conflating the two is what painted a charged,
	# gated ability as still counting down.
	var cooling := ratio > 0.0
	var ring_col := COLOR_READY
	if blocked:
		ring_col = COLOR_BLOCKED   # the refused-press flash outranks everything
	elif cooling:
		ring_col = COLOR_COOLING
	elif not ready:
		ring_col = COLOR_GATED     # charged, but a gate says no

	if cooling:
		# An arc that empties clockwise from the top as the charge fills.
		var start := -PI / 2.0
		draw_arc(center, DIAL_RADIUS, start, start + TAU * ratio, 48, ring_col,
			RING_WIDTH, true)
	else:
		# Full ring: the charge IS full, whether or not a gate lets it out.
		draw_arc(center, DIAL_RADIUS, 0.0, TAU, 48, ring_col, RING_WIDTH, true)

	# Big "F" key hint in the centre of the dial.
	var key_size := 30
	var key_col := HudTheme.BONE if cooling and not blocked else ring_col
	_draw_centered(font, "F", center + Vector2(0.0, key_size * 0.36), key_size, key_col)

	# Ability name below the dial, in caps at the DRAW SITE — never in ui.csv,
	# where the translation key is the English source string (CLAUDE.md rule 1).
	var name_size := 18
	_draw_centered(font, ability_name.to_upper(),
		Vector2(center.x, center.y + DIAL_RADIUS + 24.0), name_size, HudTheme.BONE)

	# Inside the dial: the seconds left while cooling, otherwise the gate that is
	# holding a full charge back — "LAND", "RAIN" — so the player is told what to
	# DO rather than watching a countdown that already finished. tr() explicitly,
	# per CLAUDE.md rule 2: a drawn string is not an auto-translated Control.text.
	if cooling:
		_draw_centered(font, "%.1f" % _secs, Vector2(center.x, center.y + 22.0),
			14, HudTheme.BONE)
	elif _block_reason != "":
		_draw_centered(font, tr(_block_reason), Vector2(center.x, center.y + 22.0),
			14, COLOR_GATED)


func _draw_centered(font: Font, text: String, baseline_center: Vector2, font_size: int, color: Color) -> void:
	"""Draw `text` horizontally centred on `baseline_center` with the palette's
	INK outline — the world-side lettering contract (`HudTheme.OUTLINE_PX`, which
	is 2 px OF INK and so doubles at the call, since Godot grows the glyph in both
	directions)."""
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := Vector2(baseline_center.x - width * 0.5, baseline_center.y)
	# Outline first (drawn slightly thicker), then the fill on top.
	font.draw_string_outline(get_canvas_item(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, HudTheme.OUTLINE_PX * 2, HudTheme.INK)
	font.draw_string(get_canvas_item(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, color)
