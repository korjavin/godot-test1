extends Label
## Score HUD (top-right of the screen): level and coin count.
##
## Each frame this mirrors the player's coin count (the headline score) and
## progression level into the label text. It finds the player through the "player"
## group rather than a hard reference, matching the rest of the project, so it
## keeps working across player respawns.

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

## The transient-shout stroke: 3 px of INK, per the spec's SFX rule (the coin
## counter and "NEW BEST!" are the two things it names). `HudTheme.OUTLINE_PX` is
## the 2 px WORLD-lettering stroke and is a different number, so it is not reused
## here.
## ponytail: the theme has no 3 px SFX const — a gap named in the PR, for the
## next bead that needs the same stroke to promote this line into `HudTheme`.
## Doubled at the call site like `hero_hud`'s: Godot grows an outline in BOTH
## directions, so a 3 px stroke is `outline_size = 6`.
const OUTLINE_INK_PX: int = 3

## How big the label pops when a coin is picked up (1.25 = 25% oversized).
const POP_SCALE: float = 1.25

## How fast the pop eases back to normal size (lerp weight per second).
const POP_RECOVER_SPEED: float = 10.0

## Cached player reference (re-fetched if it ever goes away).
var player: Node = null

## Cached meta-progression node (scripts/progression.gd), for the "Lv N" prefix.
## Cached exactly like `player` — a group lookup per frame for a label that may
## legitimately never have one is the wrong shape.
var progression: Node = null

## Last coin count we displayed — an increase means a pickup just happened.
var _last_coins: int = 0


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
	add_theme_constant_override("outline_size", OUTLINE_INK_PX * 2)
	# A HARD shadow: an offset solid copy, never a blur. Godot's Label shadow is
	# exactly that, so the panel language's (2,2) in INK at 0.6 transfers as is.
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
		# The level prefix is only rendered when a Progression node exists (found by
		# group, like everything else here), so this label keeps working unchanged
		# in a scene without one — and both format strings are CSV rows.
		var line: String = ""
		if progression and "level" in progression and progression.has_method("unspent_points"):
			line = tr("Lv %d   Coins: %d") % [
				progression.level, player.coins_collected
			]
			# Unspent skill points, shown only when there are any — the same
			# suffix-when-it-matters rule the streak "(xN)" below follows. Nothing
			# spends them yet (bead godot-test1-20z.3).
			var points: int = progression.unspent_points()
			if points > 0:
				line += tr("  %d SP") % points
		else:
			line = tr("Coins: %d") % [
				player.coins_collected
			]
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
