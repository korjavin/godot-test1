extends Label
## Score HUD (top-right of the screen): level and coin count.
##
## Each frame this mirrors the player's coin count (the headline score) and
## progression level into the label text. It finds the player through the "player"
## group rather than a hard reference, matching the rest of the project, so it
## keeps working across player respawns.

## How big the label pops when a coin is picked up (1.25 = 25% oversized).
const POP_SCALE: float = 1.25

## How fast the pop eases back to normal size (lerp weight per second).
const POP_RECOVER_SPEED: float = 10.0

## Cached player reference (re-fetched if it ever goes away).
var player: Node = null

## Cached meta-progression node (scripts/progression.gd), for the "Lv N" prefix.
## Cached exactly like `player` — a group lookup per frame for a label that may
## legitimately never have one is the wrong shape.
var progression: Node = null

## Last coin count we displayed — an increase means a pickup just happened.
var _last_coins: int = 0


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	if progression == null or not is_instance_valid(progression):
		progression = get_tree().get_first_node_in_group("progression")

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
		# `tr()` explicitly, because Godot's Control auto-translation would only
		# ever see the FORMATTED result ("Coins: 87"), which is not a key in any
		# translation. The rule across the project: a plain literal assigned to
		# `.text` needs no `tr()`; a format string does, and the `tr()` goes on
		# the format string, before the `%`.
		# The level prefix is only rendered when a Progression node exists (found by
		# group, like everything else here), so this label keeps working unchanged
		# in a scene without one — and both format strings are CSV rows.
		if progression and "level" in progression and progression.has_method("unspent_points"):
			text = tr("Lv %d   Coins: %d") % [
				progression.level, player.coins_collected
			]
			# Unspent skill points, shown only when there are any — the same
			# suffix-when-it-matters rule the streak "(xN)" below follows. Nothing
			# spends them yet (bead godot-test1-20z.3).
			var points: int = progression.unspent_points()
			if points > 0:
				text += tr("  %d SP") % points
		else:
			text = tr("Coins: %d") % [
				player.coins_collected
			]
		# Show the coin-streak multiplier only while it's actually boosting (>1),
		# e.g. "Coins: 87 (x3)" — see get_streak_multiplier().
		var mult: int = player.get_streak_multiplier()
		if mult > 1:
			text += " (x%d)" % mult
