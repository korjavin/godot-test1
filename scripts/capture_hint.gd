extends Label
## "Click to look around" hint — desktop-web companion to click-to-capture.
##
## Browsers refuse pointer lock outside a user gesture, so on a desktop web
## load the mouse starts FREE and the camera is dead until the player clicks
## (see the click-to-capture block in player_controller._input). This label
## tells them so. It self-manages visibility every frame — no signals, no
## coupling: visible only when this is NOT a touch session, the mouse is NOT
## captured, and the Game Over screen is not up (that screen has its own
## clickable button and this hint would just be noise under it).

## Cached once — the touch-session probe can hit JavaScriptBridge, so don't
## re-evaluate it every frame (same caching as touch_controls.gd).
var _is_touch: bool = false

## The scene's own size, kept: 22. An `@export` and not a const because the size
## is geometry, not a palette, and the thing this bead moves out of the scene is
## the colour (world_caption's own reasoning, bead `godot-test1-y1o.38`).
@export var font_size: int = 22


func _ready() -> void:
	# A HUD overlay must never eat clicks — especially THIS one, whose whole
	# job is getting the player to click through it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# THE SKIN COMES OFF `HudTheme` AND THE SCENE CARRIES NO COLOUR, exactly as
	# `world_caption.gd` does it: lettering ON the world takes the heading face
	# and the hard ink outline, not a card's body text.
	add_theme_font_override("font", HudTheme.heading_font())
	add_theme_font_size_override("font_size", font_size)
	add_theme_color_override("font_color", HudTheme.BONE)
	add_theme_color_override("font_outline_color", HudTheme.INK)
	# A hint, not an SFX shout: the 2 px world stroke, doubled at the call site
	# as every consumer does (Godot grows the outline both ways).
	add_theme_constant_override("outline_size", HudTheme.OUTLINE_PX * 2)
	# A HARD shadow: an offset solid copy, never a blur — which is what Godot's
	# Label shadow already is.
	#
	# IT IS THE PANEL OFFSET AND NOT `HudTheme.SHADOW_OFFSET` (1,1), for
	# `coin_hud`'s reason at the same stroke: `Label` draws shadow, then OUTLINE,
	# then fill, and an outline is the glyph DILATED and filled — not a ring — so
	# the outline paints opaque INK over everything within half its size of the
	# glyph. The shadow's own reach is the offset plus its 1 px
	# `shadow_outline_size`: (1,1) is swallowed whole, (2,2) leaves a hairline
	# down-right of the outline. So this is a hairline, deliberately, and the
	# smallest offset that survives its own outline at this stroke.
	add_theme_color_override("font_shadow_color",
		Color(HudTheme.INK, HudTheme.SHADOW_ALPHA))
	add_theme_constant_override("shadow_offset_x", HudTheme.SHADOW_PANEL_OFFSET.x)
	add_theme_constant_override("shadow_offset_y", HudTheme.SHADOW_PANEL_OFFSET.y)
	_is_touch = MobileSensors.is_touch_session()
	visible = false
	# On a touch session there is no mouse to capture — the hint is never
	# relevant, so skip the per-frame polling entirely.
	if _is_touch:
		set_process(false)


func _process(_delta: float) -> void:
	var show := Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	if show:
		# Hide while the Game Over screen is up (null-safe group lookup,
		# matching project convention).
		var player := get_tree().get_first_node_in_group("player")
		if player and "is_game_over" in player and player.is_game_over:
			show = false
	visible = show
