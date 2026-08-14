extends Label
## Score HUD (top-right of the screen): distance travelled plus coin count.
##
## Each frame this mirrors the player's distance (the headline score — see
## run_distance in player_controller.gd) and coin count into the label text. It
## finds the player through the "player" group rather than a hard reference,
## matching the rest of the project, so it keeps working across player respawns.

## Cached player reference (re-fetched if it ever goes away).
var player: Node = null


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")

	if player and "coins_collected" in player:
		var distance: int = player.run_distance if "run_distance" in player else 0
		text = "Distance: %dm   Coins: %d" % [distance, player.coins_collected]
		# Show the coin-streak multiplier only while it's actually boosting (>1),
		# e.g. "Distance: 240m   Coins: 87 (x3)" — see get_streak_multiplier().
		if player.has_method("get_streak_multiplier"):
			var mult: int = player.get_streak_multiplier()
			if mult > 1:
				text += " (x%d)" % mult
