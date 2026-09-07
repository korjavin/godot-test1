extends Button
## ============================================================================
## HELP HINT — "? (hotkeys)" chip bottom-right (bead godot-test1-0h4)
## ============================================================================
## The problem: the help card lists every key, but nothing on the HUD says it
## exists — a desktop player who never presses ? never learns the hotkeys the
## k4l bead just printed on every button. So: one small always-visible chip in
## the bottom-right corner reading "? (hotkeys)", BONE text on INK_RAISED like
## the card's key chips. Clicking it opens the card through the SAME toggle()
## the ? / F1 keys use.
##
## Touch sessions never see it: the touch cluster owns that corner, and touch
## already has its own how-to (the gear panel's "How to play" re-shows the
## onboarding card). It stays visible while other panels are open — the help
## card itself is one of them, and P/? already stack through PauseHub.
##
## Not one colour lives here: BONE, INK_RAISED and the chip face all come off
## `HudTheme` constants and builders, so `hero_hud_selfcheck`'s palette grep
## stays green.

## Margin from the screen edges: two of `HudTheme`'s grid units, the same
## daylight the MP toggle keeps to its corner.
const HINT_MARGIN: int = 2 * HudTheme.GRID

## The chip's face size, matching the help card's key caps (`help_overlay.gd`'s
## row size) so the hint reads as the same element, not a new one.
const HINT_FONT_SIZE: int = 18


func _ready() -> void:
	# Hear clicks under the help's own pause: opening the card pauses the tree
	# through PauseHub, and the chip must stay clickable to close it again —
	# the same reason `help_overlay.gd` itself is PROCESS_MODE_ALWAYS.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# FOCUS_NONE, like every button on a gameplay HUD: a focused Control
	# swallows polled gameplay Input (Space is both ui_accept and jump), so a
	# focused hint would eat the player's very next jump. See
	# `mp_ui._make_button()` for the full version of this warning.
	focus_mode = Control.FOCUS_NONE
	# STOP on the chip ONLY: the surrounding HUD stays MOUSE_FILTER_IGNORE, so
	# clicks everywhere else still reach the game (and the desktop-web
	# click-to-capture) exactly as before.
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Bottom-right, Godot-owned: the anchors do the positioning and the offsets
	# carry only the margin, so the chip follows any window size. Grow BEGIN
	# on both axes so the content-sized chip extends left and up from the
	# corner instead of off the screen.
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -HINT_MARGIN
	offset_top = -HINT_MARGIN
	offset_right = -HINT_MARGIN
	offset_bottom = -HINT_MARGIN
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	# The skin: the key-cap face and Oswald Bold in BONE, hover/pressed kept
	# the same — the film has no lit-up buttons. A plain literal for the text
	# so the engine translates (and live-switches) it like every help legend.
	add_theme_stylebox_override("normal", HudTheme.strip())
	add_theme_stylebox_override("hover", HudTheme.strip())
	add_theme_stylebox_override("pressed", HudTheme.strip())
	add_theme_font_override("font", HudTheme.heading_font())
	add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	add_theme_color_override("font_color", HudTheme.BONE)
	add_theme_color_override("font_hover_color", HudTheme.BONE)
	add_theme_color_override("font_pressed_color", HudTheme.BONE)
	text = "? (hotkeys)"
	update_touch_visibility(DisplayServer.is_touchscreen_available())
	pressed.connect(_on_hint_pressed)


func update_touch_visibility(touch: bool) -> void:
	## Hide the chip on a touch session (the cluster owns the corner); the
	## argument is a seam so the self-check can drive both states without
	## stubbing DisplayServer.
	visible = not touch


func _on_hint_pressed() -> void:
	## The overlay is reached through its group with has_method — never a
	## `$` path — so the scene run standalone degrades instead of erroring.
	var overlay: Node = get_tree().get_first_node_in_group("help_overlay")
	if overlay != null and overlay.has_method("toggle"):
		overlay.call("toggle")
