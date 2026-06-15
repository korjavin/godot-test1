extends Control
## Game Over screen.
##
## Shown by the player (via the "game_over_ui" group) when the last life is lost.
## It dims the screen, reports the final coin tally, and offers a "Play Again"
## button that starts a fresh run. The whole UI is built in code in _ready() so
## main.tscn only needs to declare one node with this script attached — the same
## "set yourself up in code" approach the other HUD scripts use.
##
## Decoupling: the button finds the player through the "player" group and calls
## restart_game(); it never holds a hard reference, matching the rest of the
## project's group-based wiring.

## The label we rewrite each time the screen appears, to show the coin count.
var coins_label: Label = null


func _ready() -> void:
	add_to_group("game_over_ui")

	# Cover the whole screen and sit on top. STOP so clicks behind the panel don't
	# leak through to the game while the screen is up (the button still gets its
	# own clicks because it is a child control).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_build_ui()

	# Hidden until the player runs out of lives.
	visible = false


func _build_ui() -> void:
	"""Construct the dim backdrop, the centred panel, and its contents."""
	# Semi-transparent backdrop so the world reads as "paused" behind the screen.
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.65)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	# Centre everything on screen.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 28)
	center.add_child(vbox)

	# Title.
	var title := Label.new()
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.95, 0.2, 0.2))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 10)
	vbox.add_child(title)

	# Final coin tally (rewritten by show_game_over).
	coins_label = Label.new()
	coins_label.text = "Coins collected: 0"
	coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coins_label.add_theme_font_size_override("font_size", 36)
	coins_label.add_theme_color_override("font_color", Color(1, 0.85, 0.1))
	coins_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	coins_label.add_theme_constant_override("outline_size", 6)
	vbox.add_child(coins_label)

	# "Play Again" button, centred under the text.
	var button := Button.new()
	button.text = "Play Again"
	button.add_theme_font_size_override("font_size", 32)
	button.custom_minimum_size = Vector2(300.0, 76.0)
	button.pressed.connect(_on_restart_pressed)

	var button_wrap := CenterContainer.new()
	button_wrap.add_child(button)
	vbox.add_child(button_wrap)


func show_game_over(coins: int) -> void:
	"""Reveal the screen and report the final coin count."""
	if coins_label:
		coins_label.text = "Coins collected: %d" % coins
	visible = true


func _on_restart_pressed() -> void:
	"""Hide the screen and tell the player to start a fresh run."""
	visible = false
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("restart_game"):
		player.restart_game()
