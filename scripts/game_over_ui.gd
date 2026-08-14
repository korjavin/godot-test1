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

## The labels we rewrite each time the screen appears. Distance is the HEADLINE
## score (bigger, above the coin tally) — see run_distance in player_controller.gd.
var distance_label: Label = null
var coins_label: Label = null
## All-time records line ("Best: NNNm / NN coins") — the player persists these
## across sessions (user://best_run.cfg), we just display what it hands us.
var best_label: Label = null
## "NEW BEST!" flash, shown only when this run set a new distance record. Pulsed
## by a code-built Tween (no assets) each time the screen appears with a record.
var new_best_label: Label = null
var new_best_tween: Tween = null


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

	# "NEW BEST!" record flash — sits right under the title, hidden unless this
	# run beat the all-time distance record (see show_game_over). Bright green so
	# it reads as a reward against the red GAME OVER above it.
	new_best_label = Label.new()
	new_best_label.text = "NEW BEST!"
	new_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	new_best_label.add_theme_font_size_override("font_size", 40)
	new_best_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.35))
	new_best_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	new_best_label.add_theme_constant_override("outline_size", 8)
	# Scale the pulse around the label's centre, not its top-left corner.
	new_best_label.pivot_offset = new_best_label.get_minimum_size() * 0.5
	new_best_label.visible = false
	vbox.add_child(new_best_label)

	# Headline distance score (rewritten by show_game_over) — larger than the coin
	# tally because distance is the run's primary score.
	distance_label = Label.new()
	distance_label.text = "Distance: 0m"
	distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	distance_label.add_theme_font_size_override("font_size", 48)
	distance_label.add_theme_color_override("font_color", Color(1, 1, 1))
	distance_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	distance_label.add_theme_constant_override("outline_size", 8)
	vbox.add_child(distance_label)

	# Final coin tally (rewritten by show_game_over).
	coins_label = Label.new()
	coins_label.text = "Coins collected: 0"
	coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coins_label.add_theme_font_size_override("font_size", 36)
	coins_label.add_theme_color_override("font_color", Color(1, 0.85, 0.1))
	coins_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	coins_label.add_theme_constant_override("outline_size", 6)
	vbox.add_child(coins_label)

	# All-time records line (rewritten by show_game_over). Smaller and dimmer
	# than the run's own numbers — it's context, not the headline.
	best_label = Label.new()
	best_label.text = "Best: 0m / 0 coins"
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	best_label.add_theme_font_size_override("font_size", 26)
	best_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	best_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	best_label.add_theme_constant_override("outline_size", 5)
	vbox.add_child(best_label)

	# "Play Again" button, centred under the text.
	var button := Button.new()
	button.text = "Play Again"
	button.add_theme_font_size_override("font_size", 32)
	button.custom_minimum_size = Vector2(300.0, 76.0)
	button.pressed.connect(_on_restart_pressed)

	var button_wrap := CenterContainer.new()
	button_wrap.add_child(button)
	vbox.add_child(button_wrap)


func show_game_over(coins: int, distance: int = 0, best_distance: int = 0,
		best_coins: int = 0, is_new_best: bool = false) -> void:
	"""
	Reveal the screen: the run's distance (headline) and coin count, the all-time
	records line, and — when this run set a new distance record — a pulsing
	"NEW BEST!" flash. The player computes/persists the records; we only display.
	"""
	if distance_label:
		distance_label.text = "Distance: %dm" % distance
	if coins_label:
		coins_label.text = "Coins collected: %d" % coins
	if best_label:
		best_label.text = "Best: %dm / %d coins" % [best_distance, best_coins]
	if new_best_label:
		new_best_label.visible = is_new_best
		# Kill any pulse left over from a previous game over before starting a
		# fresh one, so tweens never stack across repeated screens.
		if new_best_tween:
			new_best_tween.kill()
			new_best_tween = null
		if is_new_best:
			new_best_label.pivot_offset = new_best_label.get_minimum_size() * 0.5
			new_best_tween = create_tween().set_loops()
			new_best_tween.tween_property(new_best_label, "scale",
					Vector2(1.15, 1.15), 0.4).set_trans(Tween.TRANS_SINE)
			new_best_tween.tween_property(new_best_label, "scale",
					Vector2.ONE, 0.4).set_trans(Tween.TRANS_SINE)
	visible = true


func _on_restart_pressed() -> void:
	"""Hide the screen and tell the player to start a fresh run."""
	visible = false
	# Stop the "NEW BEST!" pulse — a looping tween must not keep ticking behind
	# a hidden screen for the whole next run.
	if new_best_tween:
		new_best_tween.kill()
		new_best_tween = null
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("restart_game"):
		player.restart_game()
