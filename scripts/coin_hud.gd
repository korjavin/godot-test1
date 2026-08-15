extends Label
## Score HUD (top-right of the screen): distance travelled plus coin count.
##
## Each frame this mirrors the player's distance (the headline score — see
## run_distance in player_controller.gd) and coin count into the label text. It
## finds the player through the "player" group rather than a hard reference,
## matching the rest of the project, so it keeps working across player respawns.

## How big the label pops when a coin is picked up (1.25 = 25% oversized).
const POP_SCALE: float = 1.25

## How fast the pop eases back to normal size (lerp weight per second).
const POP_RECOVER_SPEED: float = 10.0

## Cached player reference (re-fetched if it ever goes away).
var player: Node = null

## Last coin count we displayed — an increase means a pickup just happened.
var _last_coins: int = 0


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")

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
		text = "Distance: %dm   Coins: %d" % [player.run_distance, player.coins_collected]
		# Show the coin-streak multiplier only while it's actually boosting (>1),
		# e.g. "Distance: 240m   Coins: 87 (x3)" — see get_streak_multiplier().
		var mult: int = player.get_streak_multiplier()
		if mult > 1:
			text += " (x%d)" % mult
