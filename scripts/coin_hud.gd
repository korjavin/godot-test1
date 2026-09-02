extends Label
## Score HUD (top-right of the screen): level, coin count, and the BUDAPEST LINE.
##
## Each frame this mirrors the player's coin count (the headline score) and
## progression level into the label text. It finds the player through the "player"
## group rather than a hard reference, matching the rest of the project, so it
## keeps working across player respawns.
##
## ============================================================================
## THE BUDAPEST LINE — what replaced the distance headline
## ============================================================================
##
## Epic `godot-test1-8gw`. Distance was retired as a score by bead .1 and the
## destination replaced it: the road ends at Budapest and exploring eighteen of
## its twenty-two landmarks is the win. So the second line of this corner is the
## COUNTDOWN TO IT, and it has exactly two states (bead .5):
##
##   * OUTSIDE the city rect — "Budapest: 1.4 km", the straight-line distance to
##     the gate. A bearing, not a route: the road bends and the corridor eases,
##     and a number that tried to follow either would be a different number from
##     the one the map is showing you.
##   * INSIDE it — "Budapest 3/22", the explored count. The distance stops
##     meaning anything the moment you are standing in the thing.
##
## ONE LABEL, TWO STATES, and it is BUILT IN CODE rather than added as a second
## node in `scenes/main.tscn` — `landmark_toast.gd` and `touch_controls.gd`'s
## rule, for their reason: this project ships a web build and every extra `.tscn`
## node is another resource to import, parse and keep in step with a script that
## already knows the whole layout. It is its own Control and not a `\n` in this
## label's own text because the two lines want different sizes and different
## colours, and because the coin headline's 40 px would put German's
## "Nach Budapest: 1,4 km" far outside a 256 px corner (see
## `locale_selfcheck.WIDTH_BUDGETS`, which measures exactly that).

## How big the label pops when a coin is picked up (1.25 = 25% oversized).
const POP_SCALE: float = 1.25

## How fast the pop eases back to normal size (lerp weight per second).
const POP_RECOVER_SPEED: float = 10.0

## The Budapest line's own type, sized well under the coin headline's 40: it is
## the SECOND thing you read in this corner, and the coin count stays the first.
const BUDAPEST_FONT_SIZE: int = 20

## Its colour — the minimap's landmark violet lightened to read at this size, so
## the line and the X marks on the map are visibly about the same thing.
const BUDAPEST_COLOR := Color(0.85, 0.72, 1.0, 1.0)

## Height reserved under the coin label for it. One line at
## BUDAPEST_FONT_SIZE plus a little air.
const BUDAPEST_HEIGHT: float = 30.0

## The two states. BOTH ARE FORMAT STRINGS, hence both are `tr()`ed at the format
## and never at the result (Localization RULE 2), and both are `ui.csv` keys that
## `locale_selfcheck.WIDTH_BUDGETS` measures German against — this corner is
## 256 px wide and the label does not wrap.
##
## ponytail: the distance is in kilometres at one decimal all the way in, so the
## last 100 m of the approach all read "Budapest: 0.1 km". The city is 2 km from
## the HQ, so that is the last few seconds of a long walk and the gate is in
## plain sight by then. A metres state below ~1 km was the alternative and it is
## a third state for a case the player can already see.
const BUDAPEST_FAR: String = "Budapest: %.1f km"
const BUDAPEST_HERE: String = "Budapest %d/%d"

## The Budapest line itself, built in `_ready()`.
var budapest_label: Label = null

## Cached player reference (re-fetched if it ever goes away).
var player: Node = null

## Cached meta-progression node (scripts/progression.gd), for the "Lv N" prefix.
## Cached exactly like `player` — a group lookup per frame for a label that may
## legitimately never have one is the wrong shape.
var progression: Node = null

## Last coin count we displayed — an increase means a pickup just happened.
var _last_coins: int = 0


func _ready() -> void:
	# THE BUDAPEST LINE IS A SIBLING, NOT A CHILD, and that is the one non-obvious
	# thing about it. This label SCALE-POPS on every coin pickup around its own
	# centre; a child would ride that pop and swing 15 px up and down under it
	# twenty times a minute. So it is parented beside us and its rect is written
	# from ours each frame (`_update_budapest`) — which still means no
	# `scenes/main.tscn` offset is written down twice.
	budapest_label = Label.new()
	budapest_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	budapest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	budapest_label.add_theme_color_override("font_color", BUDAPEST_COLOR)
	budapest_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	budapest_label.add_theme_constant_override("outline_size", 6)
	budapest_label.add_theme_font_size_override("font_size", BUDAPEST_FONT_SIZE)
	var host: Node = get_parent()
	if host is Control:
		host.add_child(budapest_label)
	else:
		# No Control parent (this script run in isolation): keep it anyway so
		# nothing below has to be null-guarded twice, just under us.
		add_child(budapest_label)


func _update_budapest() -> void:
	"""
	Write the Budapest line: the countdown outside the city, the explored count
	inside it.

	Both numbers are pure functions of things this node can already reach — the
	player's position and its `explored_mask` — so there is nothing to subscribe
	to and nothing to keep in step. `has_method` / `in` guards throughout, the
	project's standard shape, so a scene whose player is a stand-in (a standalone
	scene, a headless check) simply shows nothing.
	"""
	if budapest_label == null:
		return
	# Track our rect: directly under this label, the same width, right-aligned. One
	# assignment a frame against never writing an offset down twice.
	if budapest_label.get_parent() != self:
		budapest_label.position = position + Vector2(0.0, size.y)
		budapest_label.size = Vector2(size.x, BUDAPEST_HEIGHT)
	if player == null or not ("global_position" in player):
		budapest_label.text = ""
		return
	var pos: Vector3 = player.global_position
	if BudapestPlan.contains(pos.x, pos.z):
		var explored: int = 0
		if player.has_method("explored_count"):
			explored = int(player.call("explored_count"))
		budapest_label.text = tr(BUDAPEST_HERE) % [explored, BudapestPlan.SLOTS.size()]
		return
	# STRAIGHT-LINE TO THE GATE, flat XZ — the world is flat and the gate's `y` is
	# 0, so the third axis would only add the player's own jump height.
	var gate: Vector3 = BudapestPlan.GATE
	var metres: float = Vector2(pos.x - gate.x, pos.z - gate.z).length()
	budapest_label.text = tr(BUDAPEST_FAR) % (metres / 1000.0)


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

	_update_budapest()
