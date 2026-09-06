extends Label
## A big centred caption drawn ON the world — the respawn countdown ("Caught! /
## Robbed! Back in 1.2...") and the level-up message, which are the same widget
## twice and therefore share one script (bead `godot-test1-y1o.38`).
##
## THE SKIN COMES OFF `HudTheme` AND THE SCENE CARRIES NO COLOUR, exactly as
## `coin_hud.gd` does it (bead `godot-test1-y1o.26`): `main.tscn` used to hold
## each label's white/cream, its black outline and its size as `theme_override_*`,
## which is a second palette nobody can grep. They are applied in `_ready()` from
## the one source instead.
##
## Overrides rather than `HudTheme.theme()`: neither of these sits on a panel,
## they are lettering ON the world, so they want the heading face and the hard
## ink outline the world-side contract asks for — not a card's body text.
##
## THE WRITERS ARE UNTOUCHED. `player_controller._show_respawn_countdown()` and
## `progression._set_message()` still find their label by GROUP and write
## `.text` / `.visible`; this script only dresses the node, so nothing here can
## be a second place a caption is decided.
##
## BOTH CAPTIONS ARE BONE, and that is a decision rather than an omission. The
## bead allows the arrest ("Caught!") to be drawn in `hero_hud.COLOR_BARS`, the
## semantic captive red, so the graver line reads graver. It is not taken: the
## colour would then be a function of WHICH message is up, which means this
## script reading `caught_was_arrest` off the player every frame the caption is
## visible — a second decision site for something the sentence already says out
## loud, for one frame-and-a-half of red. The owner rules from the shots.

## The scene's own sizes, kept: the countdown is 48 and the level-up line 40.
## An `@export` and not a const because one script dresses two nodes, and it is
## the ONE property either node keeps in `main.tscn` — a size is geometry, not a
## palette, and the thing this bead moves out of the scene is the colour.
##
## Unchanged from the overrides they replace, deliberately: Oswald is CONDENSED,
## so keeping the numbers makes the German lines NARROWER than they were and no
## width budget in `locale_selfcheck` moves.
@export var font_size: int = 48


func _ready() -> void:
	add_theme_font_override("font", HudTheme.heading_font())
	add_theme_font_size_override("font_size", font_size)
	# BONE, not amber: the coin counter is the one amber TEXT in the HUD and the
	# accent is rationed to one amber thing per screen region.
	add_theme_color_override("font_color", HudTheme.BONE)
	add_theme_color_override("font_outline_color", HudTheme.INK)
	add_theme_constant_override("outline_size", HudTheme.OUTLINE_SFX_PX * 2)
	# A HARD shadow: an offset solid copy, never a blur — which is what Godot's
	# Label shadow already is.
	#
	# IT IS THE PANEL OFFSET AND NOT `HudTheme.SHADOW_OFFSET` (1,1), for
	# `coin_hud`'s reason at the same stroke: `Label` draws shadow, then OUTLINE,
	# then fill, and an outline is the glyph DILATED and filled — not a ring — so
	# `outline_size = 6` paints opaque INK over everything within 3 px of the
	# glyph. The shadow's own reach is the offset plus its 1 px
	# `shadow_outline_size`: (1,1) reaches 2.41 px and is swallowed WHOLE, (2,2)
	# reaches 3.83 and leaves a ~0.8 px hairline down-right of the outline. So
	# this is a hairline, deliberately, and the smallest offset that survives its
	# own outline at this stroke.
	add_theme_color_override("font_shadow_color",
		Color(HudTheme.INK, HudTheme.SHADOW_ALPHA))
	add_theme_constant_override("shadow_offset_x", HudTheme.SHADOW_PANEL_OFFSET.x)
	add_theme_constant_override("shadow_offset_y", HudTheme.SHADOW_PANEL_OFFSET.y)
