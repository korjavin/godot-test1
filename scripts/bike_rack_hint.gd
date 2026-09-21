extends Label
## THE RACK HINT PAD (bead godot-test1-1hp7, owner 2026-09-20): "X — rent a bike
## (2 coins)" while standing at a `bike_stand` rack, in the lift pad hint's
## visual language (`tower_lift_menu.gd` HINT_LINE "%s — lift", owner ruling 2,
## bead b9m8) and on its enter edge like the waypoint circle (`waypoint_hub.gd`).
## Today the help card (z2yv.10) is the only way to learn the mount key.
##
## GEOMETRY AND SKIN MIRROR THE LIFT'S `_build_hint()` in values, not by
## reference: lifting a shared helper would route the tower's own code path
## through it, and the bead keeps tower paths untouched. One row above
## `HUD/CaptureHint`'s slot, transparent lettering with no frame, so German has
## nothing to overflow and `locale_selfcheck` needs no budget for this face.
##
## ONE RULE with the mount (`player_abilities.nearest_bike_stand()`): the pad
## shows exactly when that function returns non-null — a retuned
## `BIKE_MOUNT_REACH` retunes both, and a decoupled copy fails the hint probe's
## agreement. Hidden on leave, while riding, while any panel holds the pause
## (`PauseHub.holder_count()`), and under the HQ roof (`_sheltered()`).
##
## The second line ("%s — return the bike") appears only if a `dismount_bike`
## action exists: dismount today is the jump press, not a key, so there is no
## second line — and the mount probe's "mounted → hidden" demands exactly that.
## Refusals keep speaking through the toast (`try_mount_bike()` owns them);
## this pad is the affordance, never the message.
const HINT_PAD_FONT_SIZE: int = 22
const HINT_PAD_HALF_WIDTH: float = 200.0
const HINT_PAD_HEIGHT: float = 32.0
const HINT_PAD_BOTTOM: float = 80.0

## RULE 2 (`tower_lift_menu.gd`): `tr()` on the format, the key written here.
const RENT_LINE: String = "%s — rent a bike (%d coins)"
const RETURN_LINE: String = "%s — return the bike"

## The cost figure, off the player's own const (the number, not the rule —
## the rule stays live through `nearest_bike_stand()`). One direction only:
## nothing in `player_controller.gd` reads this file.
const PlayerScript := preload("res://scripts/player_controller.gd")

var _was_showing: bool = false

## The key string the visible text was composed with: a remapped action
## re-composes the pad under a standing player instead of waiting for an edge.
var _last_key: String = ""


func _ready() -> void:
	# Must keep running under its own pause, like the lift hint (`tower_lift_menu`)
	# and every other always-available HUD piece: the pad has to notice the
	# pause-holder that hides it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = -HINT_PAD_HALF_WIDTH
	offset_right = HINT_PAD_HALF_WIDTH
	offset_top = -HINT_PAD_BOTTOM - HINT_PAD_HEIGHT
	offset_bottom = -HINT_PAD_BOTTOM
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_theme_font_override("font", HudTheme.heading_font())
	add_theme_font_size_override("font_size", HINT_PAD_FONT_SIZE)
	add_theme_color_override("font_color", HudTheme.BONE)
	add_theme_color_override("font_outline_color", HudTheme.INK)
	add_theme_constant_override("outline_size", HudTheme.OUTLINE_PX * 2)
	add_theme_color_override("font_shadow_color",
		Color(HudTheme.INK, HudTheme.SHADOW_ALPHA))
	add_theme_constant_override("shadow_offset_x", HudTheme.SHADOW_PANEL_OFFSET.x)
	add_theme_constant_override("shadow_offset_y", HudTheme.SHADOW_PANEL_OFFSET.y)
	visible = false


func _notification(what: int) -> void:
	# RULE 2's cost, the lift's shape: the text is composed, so a locale flip
	# under a standing player must re-compose it (`tower_lift_menu.gd`).
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_was_showing = false
		_last_key = ""


func _process(_delta: float) -> void:
	# Group + has_method, never a path (`CLAUDE.md`); `"player"` is the LOCAL
	# player only, so a hologram can never raise this pad.
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("try_mount_bike"):
		_hide()
		return
	var abilities: Object = player.get("abilities")
	if abilities == null or not abilities.has_method("nearest_bike_stand"):
		_hide()
		return
	var riding := bool(player.get("is_riding"))
	var sheltered := player.has_method("_sheltered") and bool(player.call("_sheltered"))
	var stand: Node3D = abilities.call("nearest_bike_stand") as Node3D
	if stand == null or riding or sheltered or PauseHub.holder_count() > 0:
		_hide()
		return
	var key := _action_key("mount_bike")
	if not _was_showing or key != _last_key:
		_last_key = key
		text = tr(RENT_LINE) % [key, PlayerScript.BIKE_COIN_COST]
		if InputMap.has_action("dismount_bike"):
			text += "\n" + tr(RETURN_LINE) % _action_key("dismount_bike")
	visible = true
	_was_showing = true


func _hide() -> void:
	visible = false
	_was_showing = false


func _action_key(action: String) -> String:
	# The key as the player bound it: the first key event on the action,
	# physical position preferred (the project's bindings are positional).
	# Read live, never a literal — a remapped action renames this pad.
	if not InputMap.has_action(action):
		return ""
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			var code := int(key.physical_keycode)
			if code == 0:
				code = int(key.keycode)
			if code != 0:
				return OS.get_keycode_string(code)
	return ""
