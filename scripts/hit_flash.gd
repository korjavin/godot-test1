extends ColorRect
## Full-screen red "you got hit" flash.
##
## Sits in the HUD as a translucent red ColorRect. When a crocodile catches the
## player, the player triggers it via the "hit_flash" group; it simply pops to a
## peak opacity and fades itself back out. It ignores mouse input so it never
## blocks the game.

## How quickly the flash fades (alpha per second).
const FADE_SPEED: float = 1.8

## Opacity the flash jumps to when triggered.
const PEAK_ALPHA: float = 0.55

## Current opacity, eased down to 0 each frame.
var current_alpha: float = 0.0


func _ready() -> void:
	add_to_group("hit_flash")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(0.7, 0.0, 0.0, 0.0)


func flash(flash_color: Color = Color(0.7, 0.0, 0.0)) -> void:
	"""
	Trigger the flash. Defaults to the classic "you got hit" red, so the existing
	bite caller keeps working unchanged; other systems can pass their own tint
	(the alpha component is ignored — opacity is driven by current_alpha).
	"""
	color = Color(flash_color.r, flash_color.g, flash_color.b, 0.0)
	current_alpha = PEAK_ALPHA


func _process(delta: float) -> void:
	if current_alpha > 0.0:
		current_alpha = maxf(0.0, current_alpha - FADE_SPEED * delta)
		color.a = current_alpha
