extends Label
## Score HUD (top-right of the screen): the coin count, and the level strip it
## paints under itself.
##
## Each frame this mirrors the player's coin count (the headline score) into the
## label text. It finds the player through the "player" group rather than a hard
## reference, matching the rest of the project, so it keeps working across player
## respawns.
##
## THIS LABEL ALSO PAINTS (bead godot-test1-l8rs). Under the text, inside its own
## rect, `_draw()` puts a Diablo-ish hexagon badge carrying the level digits and a
## slim bar filling toward the next level. It is a `_draw` on the Label rather
## than a sibling node because the whole strip is ONE readout with the count: it
## wants the same corner, the same pickup pop, and the same "no Progression node
## -> paint nothing" degrade the old "Lv N" text prefix had. The prefix is gone —
## the badge IS the level, and two level readouts on one line is the regression
## `hero_hud_selfcheck` check 9 exists to catch.
##
## The fill reads LIFETIME coins, never `player.coins_collected`: levels are
## lifetime-cumulative and personal (see `progression.gd`'s header), while the
## run's purse is taxed on a bite and reset per run.

## THE SKIN COMES OFF `HudTheme` AND THE SCENE CARRIES NO COLOUR (bead
## godot-test1-y1o.26). `main.tscn` used to hold this label's yellow, its black
## outline and its size as `theme_override_*`, which is a second palette nobody
## can grep; the overrides are applied in `_ready()` from the one source instead.
##
## Coins are the headline score, so this is the ONE place in the HUD where
## VISOR_AMBER is the TEXT colour rather than a frame or a ring — the spec's
## "one amber thing per screen region", spent here for the whole top-right.

## Unchanged from the scene it came out of, deliberately: Oswald is CONDENSED, so
## keeping 40 makes the German line NARROWER than it was and no width budget in
## `locale_selfcheck` moves.
const FONT_SIZE: int = 40

## How big the label pops when a coin is picked up (1.25 = 25% oversized).
const POP_SCALE: float = 1.25

## How fast the pop eases back to normal size (lerp weight per second).
const POP_RECOVER_SPEED: float = 10.0

## THE LEVEL STRIP'S BAND, in this Label's local coordinates.
##
## `STRIP_TOP` is `heading_font().get_height(FONT_SIZE)` — measured 60 — so the
## band starts exactly where the text's descent space ends and the strip can never
## touch a glyph. The rect in `main.tscn` is 72 px tall, so the band is the bottom
## 12 px of it.
const STRIP_TOP: float = 60.0

## The badge is deliberately TALLER than the band and overhangs it by 6 px at each
## end: up into the count's empty descent space (no glyph in this line descends),
## and down into `AbilityHUD`'s rect, whose own ring starts 13 px in. A badge that
## fitted the 12 px band would be a bar with a point on it.
const BADGE_HEIGHT: float = 24.0

## Floor on the badge's width, so a single digit still gets a plate rather than a
## sliver. Three digits (level 100+) widen it instead of clipping — the curve is
## unbounded and there is no maximum level.
const BADGE_MIN_WIDTH: float = 28.0

## How far the hexagon's left and right points stick out past its flat top and
## bottom edges.
const BADGE_POINT: float = 6.0

const BAR_HEIGHT: float = 6.0

## Heading size for the bare level digits — nothing to translate, so no CSV row
## and no width budget.
const BADGE_FONT_SIZE: int = HudTheme.HEADING_FONT_SIZE

## Cached player reference (re-fetched if it ever goes away).
var player: Node = null

## Cached meta-progression node (scripts/progression.gd) — the strip's level and
## fill, plus the unspent-points suffix.
## Cached exactly like `player` — a group lookup per frame for a label that may
## legitimately never have one is the wrong shape.
var progression: Node = null

## Last coin count we displayed — an increase means a pickup just happened.
var _last_coins: int = 0

## THE STRIP'S ONLY REDRAW TRIGGER. `_process` recomputes both every frame and
## calls `queue_redraw()` ONLY when one of them moved — which is per coin, never
## per frame. (Assigning an unchanged `text` does not redraw a Label either, so
## without this the strip would simply never repaint.)
##
## A fraction below zero means "no Progression node": `_draw` paints nothing, the
## same standalone degrade the old level prefix had. -1 rather than a second bool.
var _last_fraction: float = -1.0
var _last_level: int = -1


func _ready() -> void:
	# One group per HUD widget, the project convention — and what lets the
	# `style_shots` acceptance tool photograph this line on its own.
	add_to_group("coin_hud")
	# Overrides rather than `HudTheme.theme()`: this Label is not on a panel, it
	# is lettering ON the world, so it wants the heading face and the hard ink
	# outline the world-side contract asks for — not a card's body text.
	add_theme_font_override("font", HudTheme.heading_font())
	add_theme_font_size_override("font_size", FONT_SIZE)
	add_theme_color_override("font_color", HudTheme.VISOR_AMBER)
	add_theme_color_override("font_outline_color", HudTheme.INK)
	# The transient-shout stroke, promoted into `HudTheme` by bead
	# godot-test1-y1o.38 when `world_caption.gd` became its second consumer —
	# `HudTheme.OUTLINE_PX` is the 2 px WORLD-lettering stroke and is a different
	# number, so it is not what this wants. Doubled at the call site like
	# `hero_hud`'s: Godot grows an outline in BOTH directions, so a 3 px stroke is
	# `outline_size = 6`.
	add_theme_constant_override("outline_size", HudTheme.OUTLINE_SFX_PX * 2)
	# A HARD shadow: an offset solid copy, never a blur — which is what Godot's
	# Label shadow already is, so the panel language's (2,2) in INK at 0.6 needs no
	# translating.
	#
	# IT IS THE PANEL OFFSET AND NOT `HudTheme.SHADOW_OFFSET` (1,1), AND THE
	# OUTLINE IS WHY. `Label` draws shadow, then OUTLINE, then fill, and an
	# outline is the glyph DILATED and filled — not a ring — so `outline_size = 6`
	# paints opaque INK over everything within 3 px of the glyph. The shadow's own
	# reach is the offset plus its 1 px `shadow_outline_size`: (1,1) reaches 2.41
	# px and is swallowed WHOLE, (2,2) reaches 3.83 and leaves a ~0.8 px hairline
	# down-right of the outline. So this is a hairline, deliberately — the spec's
	# (2,2) is the smallest offset that survives its own outline at this stroke,
	# and anything more legible means moving a number the spec fixed.
	add_theme_color_override("font_shadow_color",
		Color(HudTheme.INK, HudTheme.SHADOW_ALPHA))
	add_theme_constant_override("shadow_offset_x", HudTheme.SHADOW_PANEL_OFFSET.x)
	add_theme_constant_override("shadow_offset_y", HudTheme.SHADOW_PANEL_OFFSET.y)


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	if progression == null or not is_instance_valid(progression):
		progression = get_tree().get_first_node_in_group("progression")

	# Ease any active pop back toward normal size every frame.
	scale = scale.lerp(Vector2.ONE, minf(1.0, POP_RECOVER_SPEED * delta))

	if player and "coins_collected" in player:
		# Scale-pop on pickup: when the count increases, jump oversized and let
		# the lerp above shrink us back. Pivot at our centre so the pop doesn't
		# swing around the top-left corner.
		if player.coins_collected > _last_coins:
			pivot_offset = size * 0.5
			scale = Vector2.ONE * POP_SCALE
		_last_coins = player.coins_collected
		# `tr()` explicitly, because Godot's Control auto-translation would only
		# ever see the FORMATTED result ("Coins: 87"), which is not a key in any
		# translation. The rule across the project: a plain literal assigned to
		# `.text` needs no `tr()`; a format string does, and the `tr()` goes on
		# the format string, before the `%`.
		# ONE level readout, and it is the badge `_draw` paints below (bead
		# godot-test1-l8rs) — which is why this branch collapsed to the count. The
		# now-unused "Lv %d   Coins: %d" row stays in `ui.csv`: nothing there forbids
		# an unused key, and the file is owned by beads in flight.
		var line: String = tr("Coins: %d") % [player.coins_collected]
		if progression and progression.has_method("unspent_points"):
			# Unspent skill points, shown only when there are any — the same
			# suffix-when-it-matters rule the streak "(xN)" below follows. Nothing
			# spends them yet (bead godot-test1-20z.3).
			var points: int = progression.unspent_points()
			if points > 0:
				line += tr("  %d SP") % points
		# Show the coin-streak multiplier only while it's actually boosting (>1),
		# e.g. "Coins: 87 (x3)" — see get_streak_multiplier().
		var mult: int = player.get_streak_multiplier()
		if mult > 1:
			line += " (x%d)" % mult
		# ALL CAPS AT THE DRAW SITE and never in `ui.csv`, where the key IS the
		# English source string — the spec's typography rule, and the reason the
		# composition above happens into a local rather than into `.text`.
		# `to_upper()` is locale-aware in Godot, so the German row's ü/ö/ä survive.
		text = line.to_upper()

	# THE STRIP'S REDRAW, AND THE ONLY ONE. Both reads are cheap (`level_for` is a
	# handful of integer compares), and the fraction only moves when a coin lands —
	# so this is a per-COIN repaint wearing a per-frame poll, which is what the bead
	# asked for over a signal: `levelled_up` fires on a LEVEL change, and a coin gain
	# has no signal at all. (Assigning an unchanged `text` does not redraw a Label
	# either, so without this the strip would simply never repaint.)
	var frac: float = -1.0
	var level: int = -1
	if progression and progression.has_method("level_progress") \
			and "lifetime_coins" in progression and "level" in progression:
		frac = progression.level_progress(progression.lifetime_coins)
		level = progression.level
	if frac != _last_fraction or level != _last_level:
		_last_fraction = frac
		_last_level = level
		queue_redraw()


func _draw() -> void:
	"""
	THE LEVEL STRIP: a hexagon badge carrying the level digits, and a bar filling
	toward the next level, in the band under the count. Spatially disjoint from the
	text the `Label` paints on top of us, so the order between the two is moot.

	NO EASING on the fill (owner ruling): one coin moves it a fraction of a pixel
	on a ~200 px bar, and a chest burst should jump honestly. At a level-up the
	fraction goes ~1 -> 0 on the same poll, which IS the snap to empty — the
	`LEVEL N` caption and `play_level_up()` stay the only fanfare.

	NOT ONE HEX LITERAL: every colour is a `HudTheme` const, which
	`hero_hud_selfcheck` check 8a scans every script for.
	"""
	if _last_fraction < 0.0:
		return   # no Progression node — paint nothing, exactly as the old prefix did
	var cy := STRIP_TOP + (size.y - STRIP_TOP) * 0.5
	var font := HudTheme.heading_font()
	var digits := str(_last_level)
	var digits_w := font.get_string_size(
		digits, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_FONT_SIZE).x
	var badge_w := maxf(BADGE_MIN_WIDTH, digits_w + HudTheme.GRID)

	# The hexagon: flat top and bottom, a point at each side — six points rather
	# than a rect, because the badge is the one Diablo-ish thing in this corner.
	var half := BADGE_HEIGHT * 0.5
	var hexagon := PackedVector2Array([
		Vector2(0.0, cy),
		Vector2(BADGE_POINT, cy - half),
		Vector2(badge_w - BADGE_POINT, cy - half),
		Vector2(badge_w, cy),
		Vector2(badge_w - BADGE_POINT, cy + half),
		Vector2(BADGE_POINT, cy + half),
	])
	draw_colored_polygon(hexagon, Color(HudTheme.INK, HudTheme.PANEL_ALPHA))
	# `draw_polyline` does not close a loop, so the first point is repeated.
	draw_polyline(hexagon + PackedVector2Array([hexagon[0]]),
		HudTheme.BONE, HudTheme.BORDER_PX)
	# The digits, centred on the plate. No outline: they are ON a plate rather than
	# on the world, so the world-lettering stroke would only thicken them.
	font.draw_string(get_canvas_item(),
		Vector2((badge_w - digits_w) * 0.5,
			cy - font.get_height(BADGE_FONT_SIZE) * 0.5
				+ font.get_ascent(BADGE_FONT_SIZE)),
		digits, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_FONT_SIZE, HudTheme.BONE)

	# The bar runs from the badge to our right edge — a FIXED width, right-flush
	# with the count above it, so the strip does not jitter as the count grows.
	var bar_x := badge_w + HudTheme.GRID
	var bar := Rect2(Vector2(bar_x, cy - BAR_HEIGHT * 0.5),
		Vector2(size.x - bar_x, BAR_HEIGHT))
	if bar.size.x <= 0.0:
		return
	draw_rect(bar, Color(HudTheme.INK, HudTheme.PANEL_ALPHA))
	# Inset half a pixel so the 1 px frame lands ON pixels rather than across two.
	draw_rect(bar.grow(-0.5), HudTheme.STEEL, false, HudTheme.BORDER_PX)
	var inner := bar.grow(-float(HudTheme.BORDER_PX))
	draw_rect(Rect2(inner.position,
		Vector2(roundi(inner.size.x * _last_fraction), inner.size.y)),
		HudTheme.BONE)
