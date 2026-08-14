extends Node
## ============================================================================
## PAUSE CONTROLLER — desktop pause on the P key
## ============================================================================
## A tiny self-contained pause toggle for keyboard sessions. Press P to freeze
## the whole game (get_tree().paused) under a dark "PAUSED" overlay; press P
## again to resume.
##
## WHY A SEPARATE NODE (and not a branch in player_controller._input):
## pausing the SceneTree stops _input on every node that inherits the default
## process mode — including the player. A handler that lives on the player
## could pause the game but never see the keypress to UNpause it. This node
## sets PROCESS_MODE_ALWAYS so it keeps hearing input while everything else
## is frozen. The player instances it at runtime (see player_controller
## _ready), so main.tscn needs no edit and any scene that runs the player
## standalone gets pausing for free.
##
## The P key is handled by keycode, outside the project input map — same
## pattern as the F3 perf overlay and the other debug keys. Touch sessions
## have no P key, so this is inert on phones; the mobile focus-loss pause in
## mobile_input.gd is a SEPARATE system with its own tap-to-resume overlay,
## and the `_paused_by_us` guard below keeps the two from unpausing each
## other's state.

## The key that toggles pause. A constant (not an input-map action) on purpose:
## debug/meta keys in this project live outside the input map so they can never
## collide with rebindable gameplay actions.
const PAUSE_KEY: Key = KEY_P

## Overlay look: dim strength and the message shown while frozen.
const DIM_COLOR: Color = Color(0.0, 0.0, 0.0, 0.55)
const PAUSE_TEXT: String = "PAUSED\n\nPress P to resume"

## The overlay UI this node builds for itself in _ready().
var _overlay: CanvasLayer = null

## True only while the CURRENT pause was started by this node. The mobile
## focus-loss pause (mobile_input.gd) also sets get_tree().paused — P must
## never silently cancel THAT pause, or the "tap to resume" overlay would be
## left up over a running game.
var _paused_by_us: bool = false

## Whether we released a captured mouse when pausing, and so should recapture
## it on resume (the resume keypress is a user gesture, which is what browser
## pointer-lock needs, so this works on desktop web too).
var _recapture_mouse: bool = false


func _ready() -> void:
	# Keep processing input while the tree is paused — the entire point of
	# this node (children, i.e. the overlay, inherit ALWAYS from here).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()


func _input(event: InputEvent) -> void:
	# Raw keycode check, echo-filtered so holding P doesn't rapid-toggle.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == PAUSE_KEY:
		_toggle_pause()


func _toggle_pause() -> void:
	var tree := get_tree()
	if not tree.paused:
		# Don't pause over the game-over screen — its buttons should stay live,
		# and "paused behind game over" is a state nobody can read.
		var player := tree.get_first_node_in_group("player")
		if player != null and bool(player.get("is_game_over")):
			return
		tree.paused = true
		_paused_by_us = true
		_overlay.visible = true
		# Free the mouse so a paused player can reach their browser/OS.
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			_recapture_mouse = true
	elif _paused_by_us:
		# Only unpause a pause WE created (see _paused_by_us above).
		tree.paused = false
		_paused_by_us = false
		_overlay.visible = false
		if _recapture_mouse:
			_recapture_mouse = false
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _build_overlay() -> void:
	"""
	Build the pause overlay in code (same convention as touch_controls.gd —
	no scene file to keep in sync). A CanvasLayer well above the HUD, holding
	a full-screen dim and a centred label.
	"""
	_overlay = CanvasLayer.new()
	_overlay.layer = 90  # above the gameplay HUD, below nothing that matters
	_overlay.visible = false
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.color = DIM_COLOR
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Swallow clicks while paused so the game underneath can't be poked.
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)

	var label := Label.new()
	label.text = PAUSE_TEXT
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	_overlay.add_child(label)
