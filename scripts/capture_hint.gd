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


func _ready() -> void:
	# A HUD overlay must never eat clicks — especially THIS one, whose whole
	# job is getting the player to click through it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
