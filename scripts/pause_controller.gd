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
##
## THE PAUSE ITSELF GOES THROUGH `PauseHub` — see scripts/pause_hub.gd. The
## refcount is what makes "P again" safe while the help card is still up over
## our pause: we drop OUR claim, the help keeps ITS one, and the world stays
## frozen until the last overlay closes.
##
## IN A ROOM, P IS THE ONE PAUSE THAT TRAVELS (bead godot-test1-3a2, owner:
## "when I click pause in the MP it should be paused for all"). This node joins
## group "pause_controller" and answers `is_pausing()`; `mp_manager._send_presence`
## reads that once a frame and sets a `pz` bit on the presence packet, and every
## other peer's manager holds ONE `PauseHub` claim while anybody's bit is set. So
## nothing about the pause is sent from here and no packet is decoded here — this
## node only draws the card that names who to wait for (`_process` below).
## The other eight pausers stay LOCAL and that is deliberate: reading a map, a
## help card or a skill tree must not stop three other people. See the list in
## `pause_hub.gd`'s header.

## The key that toggles pause. A constant (not an input-map action) on purpose:
## debug/meta keys in this project live outside the input map so they can never
## collide with rebindable gameplay actions.
const PAUSE_KEY: Key = KEY_P

## Overlay look: the veil over the world, and the message shown while frozen.
##
## THE CARD IS `game_over_ui`'S AT HALF SIZE (bead godot-test1-y1o.31): the same
## modal `HudTheme.card(true)` under the same 1 px BONE hairline, with the message
## in Oswald Bold at half the ending card's title size. Nothing here types a
## colour; the RGB is INK and this alpha is the dim the overlay has always used.
const DIM_ALPHA: float = 0.55
const DIM_COLOR: Color = Color(HudTheme.INK, DIM_ALPHA)
## Half of `game_over_ui.TITLE_FONT_SIZE`, written down rather than read across:
## the two panels are two files by the bead's own split, and a `preload` of a
## sibling HUD script for one integer is a dependency for nothing. A title-card
## size ladder has no home in `HudTheme` yet — named in the PR.
const PAUSE_FONT_SIZE: int = 36
const PAUSE_TEXT: String = "PAUSED\n\nPress P to resume"

## Shown instead while a ROOM MEMBER holds the pause. `%s` is their lobby name.
## `tr()`d explicitly at the format string (localization rule 2 — a string
## composed at runtime is never seen by Control auto-translation).
const REMOTE_PAUSE_TEXT: String = "PAUSED by %s\n\nThey resume"

## The overlay UI this node builds for itself in _ready(), and the label inside
## it whose text switches between the local and the remote message.
var _overlay: CanvasLayer = null
var _label: Label = null

## The full-screen dim. Held because its `mouse_filter` differs between the two
## cards — see `_show_remote_card()`.
var _dim: ColorRect = null

## The name of the room member currently pausing us, `""` for nobody. Cached so
## `_process` writes the label only on a change rather than 60 times a second.
var _remote_pauser: String = ""

## True while THIS node holds a `PauseHub` claim. The mobile focus-loss pause
## (mobile_input.gd) also freezes the tree — P must never silently cancel THAT
## pause, or the "tap to resume" overlay would be left up over a running game.
var _paused_by_us: bool = false

## Whether we released a captured mouse when pausing, and so should recapture
## it on resume (the resume keypress is a user gesture, which is what browser
## pointer-lock needs, so this works on desktop web too).
var _recapture_mouse: bool = false


func _ready() -> void:
	# Keep processing input while the tree is paused — the entire point of
	# this node (children, i.e. the overlay, inherit ALWAYS from here).
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The per-HUD-widget group idiom: `mp_manager` finds us by group and asks
	# `is_pausing()`, so it never learns that the player owns this node.
	add_to_group("pause_controller")
	_build_overlay()


func is_pausing() -> bool:
	"""
	Whether the LOCAL player is holding the pause with P. The one thing
	`mp_manager._send_presence` reads; it is `_paused_by_us` and nothing else,
	because a pause we merely inherited (the help card, a teammate) is not ours
	to publish and republishing it would deadlock two peers into each other.
	"""
	return _paused_by_us


func _input(event: InputEvent) -> void:
	# Raw keycode check, echo-filtered so holding P doesn't rapid-toggle.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == PAUSE_KEY:
		_toggle_pause()


func _toggle_pause() -> void:
	var tree := get_tree()
	if _paused_by_us:
		# Drop only OUR claim (see _paused_by_us above). If the help card or the
		# MP panel is also holding one, the world stays frozen and only our dim
		# goes away — which is precisely the bug the refcount fixes.
		_paused_by_us = false
		PauseHub.release(self)
		_overlay.visible = false
		# A room member may still be pausing underneath us — `_process` sees the
		# cleared cache next frame and puts their card back up (and takes the mouse
		# straight back off us, which is what it is for).
		_remote_pauser = ""
		_recapture_mouse_if_released()
		return
	# P IS INERT UNDER SOMEBODY ELSE'S PAUSE, unchanged by the refcount. This is a
	# CONDITION read — "is the world already stopped" — not an ownership question:
	# adding a second claim here would park a "PAUSED / press P to resume" card
	# over the MP panel or the phone's resume overlay, which is a worse screen than
	# doing nothing.
	if tree.paused:
		return
	# Don't pause over the game-over screen — its buttons should stay live,
	# and "paused behind game over" is a state nobody can read.
	var player := tree.get_first_node_in_group("player")
	if player != null and bool(player.get("is_game_over")):
		return
	PauseHub.take(self)
	_paused_by_us = true
	# Restore OUR message and OUR dim. A remote card may have been up a moment ago
	# (a teammate resumed, then we pressed P), and a label left saying "PAUSED by
	# Ada — they resume" over our own pause names the wrong person to wait for.
	_label.text = PAUSE_TEXT
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_remote_pauser = ""
	_overlay.visible = true
	# Free the mouse so a paused player can reach their browser/OS.
	_release_mouse()


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

	_dim = ColorRect.new()
	_dim.color = DIM_COLOR
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Swallow clicks while paused so the game underneath can't be poked. Flipped to
	# IGNORE for the REMOTE card — see `_show_remote_card()`.
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(_dim)

	# THE CARD. Everything from here down is IGNORE for clicks: the dim is the ONLY
	# thing that decides whether this overlay eats them, and a second Control
	# quietly doing it too is how the remote card's escape hatch (see
	# `_show_remote_card`) would come back blocked over the card's own rect.
	# `Control`'s default is STOP for a Panel and IGNORE for a Label, so both are
	# said out loud — the behaviour is load-bearing.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)

	# `card(true)` is the modal case — opaque INK, a 2 px STEEL frame, the hard
	# (2,2) shadow — and it returns a FRESH box, so editing the margins restyles no
	# other panel. THE BOX CARRIES NO PADDING AND THE MARGIN CONTAINER BELOW DOES,
	# for `game_over_ui`'s reason: a `PanelContainer` lays its children out INSIDE
	# the stylebox's margins, so a hairline meant to span the top edge cannot be a
	# child of a padded one.
	var card_box := HudTheme.card(true)
	card_box.set_content_margin_all(0)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", card_box)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(card)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(outer)

	# The film's letterbox line across the top edge — `game_over_ui`'s hairline,
	# and one ColorRect for its reason: a StyleBoxFlat carries ONE border colour
	# and this card's frame is STEEL.
	var hairline := ColorRect.new()
	hairline.color = HudTheme.BONE
	hairline.custom_minimum_size = Vector2(0.0, float(HudTheme.BORDER_PX))
	hairline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(hairline)

	# The card's padding, on everything BUT the hairline.
	var pad := MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_bottom", "margin_top"]:
		pad.add_theme_constant_override(side, HudTheme.CARD_PADDING * 3)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", HudTheme.GRID * 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(vbox)

	_label = Label.new()
	_label.text = PAUSE_TEXT
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", HudTheme.heading_font())
	_label.add_theme_font_size_override("font_size", PAUSE_FONT_SIZE)
	_label.add_theme_color_override("font_color", HudTheme.BONE)
	_label.add_theme_color_override("font_outline_color", HudTheme.INK)
	# `OUTLINE_PX` is 2 px OF INK and Godot grows a glyph BOTH ways, so this is the
	# spec's 1 px card outline — `game_over_ui`'s note, same card.
	_label.add_theme_constant_override("outline_size", HudTheme.OUTLINE_PX)
	# And the same hard (2,2) drop shadow in INK_RAISED: it is the title card's
	# lettering that makes it a title card, so half size does not mean half the
	# treatment (caught in review).
	_label.add_theme_color_override("font_shadow_color", HudTheme.INK_RAISED)
	_label.add_theme_constant_override("shadow_offset_x",
			HudTheme.SHADOW_PANEL_OFFSET.x)
	_label.add_theme_constant_override("shadow_offset_y",
			HudTheme.SHADOW_PANEL_OFFSET.y)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_label)


func _process(_delta: float) -> void:
	"""
	Draw the card for a pause somebody ELSE in the room is holding.

	The claim itself is `mp_manager`'s — it takes exactly one `PauseHub` claim
	while any member's presence carries the `pz` bit, and this node neither sends
	nor decodes a packet. All that is left is the screen, which would otherwise be
	a world that silently stopped for no visible reason.

	Our OWN pause wins the label outright (the early return): `_toggle_pause`
	already put the local card up, and P is inert under a foreign pause anyway, so
	the peer who paused is the peer who resumes — the owner's own phrasing.

	Runs while the tree is frozen because this node is PROCESS_MODE_ALWAYS, which
	is the same property that lets it hear the unpause keypress.
	"""
	if _paused_by_us:
		return
	var mp: Node = get_tree().get_first_node_in_group("mp")
	# `has_method`-guarded like every other group lookup in this project: the
	# player scene run standalone has no manager, and a headless fixture may put
	# something else in the group.
	var who: String = str(mp.call("remote_pauser_name")) \
			if mp != null and mp.has_method("remote_pauser_name") else ""
	if who == _remote_pauser:
		return
	_remote_pauser = who
	_show_remote_card(who)


func _show_remote_card(who: String) -> void:
	"""
	Put up (or take down) the card for a teammate's pause.

	THE ESCAPE HATCH IS WHY THIS IS NOT JUST A LABEL SWAP. Under our OWN pause the
	way out is P; under a teammate's, P is inert by design, so the only way out of
	a peer who never resumes is the MP panel's Leave — which is PROCESS_MODE_ALWAYS
	and opens under a foreign pause, but lives on the HUD CanvasLayer UNDER this
	overlay. So the remote card releases a captured mouse (a captured cursor cannot
	click anything) and lets the dim IGNORE clicks, which leaves the HUD's MP
	button reachable through it. The local card keeps swallowing them: there the
	world underneath must not be pokeable and P is right there.
	"""
	_overlay.visible = not who.is_empty()
	if who.is_empty():
		_dim.mouse_filter = Control.MOUSE_FILTER_STOP
		_recapture_mouse_if_released()
		return
	_label.text = tr(REMOTE_PAUSE_TEXT) % who
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_release_mouse()


func _release_mouse() -> void:
	"""Free a captured cursor and remember to hand it back on resume."""
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_recapture_mouse = true


func _recapture_mouse_if_released() -> void:
	"""
	The other half of `_release_mouse()`. The resume is a user gesture (a keypress
	or a teammate's packet arriving on a frame we are awake for), which is what
	browser pointer-lock needs, so this works on desktop web too.

	NOT WHILE SOMEBODY ELSE IS STILL PAUSING, and that is the refcount's rule one
	more time: the MP panel is what the remote card deliberately leaves clickable,
	and a panel opened over an ALREADY-free cursor arms no `_recapture_mouse` of
	its own — so grabbing the pointer back the moment the teammate resumes pins
	the cursor to screen centre over a panel whose buttons are now unreachable and
	whose claim nothing can release. The claim we are dropping is ours alone; the
	cursor belongs to whoever is still holding one, and `mp_ui` re-captures on
	close. The flag is spent either way, because there is no second chance to.
	"""
	if not _recapture_mouse:
		return
	_recapture_mouse = false
	if _may_recapture_mouse():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _may_recapture_mouse() -> bool:
	"""
	Whether the cursor is ours to take back — i.e. nobody else is still pausing.

	A one-caller predicate, which this project would normally not write, and it is
	one because HEADLESS CANNOT SEE THE EFFECT: `Input.set_mouse_mode()` is a no-op
	under the dummy display server and `Input.mouse_mode` reads VISIBLE whatever
	you do to it, so an assertion on the pointer passes however this branch is
	written. `pause_selfcheck` drives the decision instead.
	"""
	return not get_tree().paused
