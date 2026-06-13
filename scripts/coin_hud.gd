extends Label
## Coin counter HUD (top-right of the screen).
##
## Each frame this mirrors the player's coin count into the label text. It finds
## the player through the "player" group rather than a hard reference, matching
## the rest of the project, so it keeps working across player respawns.

## Cached player reference (re-fetched if it ever goes away).
var player: Node = null


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")

	if player and "coins_collected" in player:
		text = "Coins: %d" % player.coins_collected
