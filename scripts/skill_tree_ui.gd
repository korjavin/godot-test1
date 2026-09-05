extends Control
## ============================================================================
## SKILL TREE PANEL — where the levels turn into something
## ============================================================================
## `scripts/progression.gd` has been banking lifetime coins into levels, and each
## level into a skill point, since bead godot-test1-20z.2. This is the screen that
## spends them: one column per branch, one button per node, press to buy a rank.
##
## It owns NO game rules. Every rule — what the trees contain, what a node costs,
## whether a prerequisite is met, what a rank is worth and where the balance caps
## sit — lives in `Progression`, and this file only ever calls `can_spend()` /
## `spend()` and renders the answer. That is what keeps the caps enforceable: a UI
## that computed affordability itself would be a second place to get −40% wrong.
##
## ----------------------------------------------------------------------------
## Built in code, no assets, found by group — the project convention
## ----------------------------------------------------------------------------
## `touch_controls.gd`, `mobile_settings_panel.gd`, `mp_ui.gd` and
## `start_overlay.gd` all build their whole UI in `_ready()` from bare `Control`s
## and a `StyleBoxFlat`, so `main.tscn` carries nothing but a `Control` with this
## script on it. The player and the progression node are both reached through
## their groups with `has_method` guards, so a scene missing either renders an
## empty, harmless panel instead of erroring.
##
## ----------------------------------------------------------------------------
## HOW IT OPENS: the K key, and a button next to the level indicator
## ----------------------------------------------------------------------------
## **K is a RAW KEYCODE, deliberately outside the project input map.** That is the
## rule this project already applies to every meta/UI key — P (pause), M (minimap),
## +/− (minimap zoom), F3/F4/F5/F6/F7 — and it is the right side of the line the
## convention actually draws: named actions exist for *gameplay* input, which is
## rebindable and read by `player_controller`, while a key that only opens a panel
## has nothing to rebind against and adding it to `project.godot` would put a
## merge-conflict-prone edit in the way of every parallel branch for no gain.
##
## The button is the other half, and it is what makes the panel reachable **by
## touch alone**: a phone has no K. It sits top-right directly under the ability
## dial, which is the free space beside the level indicator that `coin_hud.gd`
## draws (the hero row + perf own the top-left column, the steer/View toggles the
## top-centre, the action cluster the bottom-right, the MP button and ⚙ gear the
## bottom-left, and the minimap the left edge). It carries a `(N)` suffix while
## there are unspent points — the same show-it-only-when-it-matters rule the coin
## HUD's streak `(xN)` and skill-point ` N SP` suffixes follow.
##
## ----------------------------------------------------------------------------
## It pauses the tree, with the shared guard
## ----------------------------------------------------------------------------
## Every pauser in this project routes through `PauseHub` (scripts/pause_hub.gd),
## which refcounts holders, and each carries its own `_paused_by_us` claim bit:
## only ever release a pause WE took, and the world starts again only when the
## LAST holder lets go. This node carries it too.
##
## Pausing rather than merely freezing the player is not a preference:
## `player_controller` reads gameplay through the GLOBAL polled `Input` state and
## through `_input()`, neither of which a `Control` on top suppresses. Without the
## pause, every click in this panel would re-fire the desktop-web click-to-capture
## (warping the cursor to screen centre and making the buttons unreachable after
## the first press), and the world would keep running — crocodiles closing while
## the player reads a menu. `process_mode` gates `_input` and `_physics_process`
## together, so one pause fixes both. `PROCESS_MODE_ALWAYS` here is what lets the
## key that CLOSES the panel still be heard under that pause.
##
## **It will not open over somebody else's pause.** The start overlay is a later
## `HUD` child and the P-pause overlay is its own `CanvasLayer` at 90, so both
## draw above this node and a card opened underneath either would be invisible
## while still holding input. (The MP panel is the exception that does not need
## the argument — this node is declared after it, so this one draws on top — but
## two panels open at once is still nobody's idea of a good screen.) Refusing is
## one line, `tree.paused and not _paused_by_us`, and it covers all three plus
## whatever takes the same pause next.
## The Game Over screen is the mirror case `mp_ui` documents: it is PAUSABLE, so
## pausing there would kill Play Again — the panel still opens, it just leaves the
## tree running, which is safe because a game-over player is already frozen.
##
## ----------------------------------------------------------------------------
## Localization
## ----------------------------------------------------------------------------
## Per RULE 1 every plain literal assigned to a `Label`/`Button` `text` is already
## translated and already live-switching, and the skill `name`/`desc`/`branch`
## strings in `Progression.SKILL_TREES` are English source strings, i.e. their own
## keys — so they are `tr()`'d explicitly here only because they are COMPOSED into
## a label with the rank counter (RULE 2: `tr()` the format string, never the
## formatted result). German is ~30% longer, so the descriptions autowrap inside a
## fixed column width and the card grows downward; the only strings measured
## against a hard width in `locale_selfcheck.gd` are the ones that cannot wrap —
## the node names on their buttons.
##
## ----------------------------------------------------------------------------
## The skin is `HudTheme`'s, and this file owns none of it (bead godot-test1-y1o.30)
## ----------------------------------------------------------------------------
## The root adopts `theme = HudTheme.theme()` — on THIS Control and nowhere higher,
## which is the seam's rule — so the card is an opaque INK modal with a 2 px STEEL
## frame and a hard shadow, and every button is the theme's. The five `COLOR_*`
## consts and the card's hand-built `StyleBoxFlat` are gone; not one colour is
## typed in this file.
##
## THE RANK IS PIPS, NOT A COUNTER. `max_ranks` runs 1 to 3 across the whole of
## `Progression`, so a node's rank is a row of small squares — STEEL for a rank
## you have not bought, VISOR_AMBER for one you have — and the `"   %d/%d"` that used to be
## composed onto every node name is gone with it. That is the card region's ONE
## amber; the opener button's `(N)` is the other region's, and the tabs, headings
## and node labels are BONE / UNIT_KHAKI so the accent stays rationed.
##
## EVERY HEADING IS CAPS, AND `_caps()` IS WHY IT CAN BE. Godot's `to_upper()`
## has no single-character uppercase for ß, so a bare `.to_upper()` renders the
## German branch names "Windstoß" and "Größe" as `WINDSTOß` / `GRÖßE` — a
## lowercase letter stranded mid-word. German's own rule is that the capital of ß
## is SS (Duden), which is one `replace` and is what this file's headings go
## through. Losing the free auto-translation is not a cost here: `_notification`
## rebuilds an open panel on a locale change and a closed one rebuilds on open,
## so a heading assigned `tr(...)` live-switches exactly like a plain literal —
## the help card (bead y1o.28) had no such rebuild and left its button alone.

# ============================================================================
# CONSTANTS — layout
# ============================================================================

## The always-visible opener, parked top-right under the ability dial (which ends
## at y = 270 in `main.tscn`).
##
## 124 -> 138 WITH THE SKIN, and the 14 px is `HudTheme`'s button padding rather
## than taste: `HudTheme.button()` puts `CARD_PADDING` (12) on each side against
## the engine default's ~4, and `locale_selfcheck` budgets "Skills" at 84 px with
## a further ~30 reserved for the " (N)" suffix. 138 - 24 = 114 = 84 + 30, so the
## shipped budget stays exactly as true as it was; leaving it at 124 would have
## made that budget loose by 14 px without a line of the check changing.
const BUTTON_WIDTH: float = 138.0
const BUTTON_HEIGHT: float = 34.0
const BUTTON_TOP: float = 278.0
const EDGE_MARGIN: float = 16.0

## The open card. Wide enough for two branch columns side by side, and it scrolls
## (a `ScrollContainer`) so a short phone screen in landscape still reaches the
## Close button.
const CARD_WIDTH: float = 640.0
const CARD_MAX_HEIGHT: float = 560.0
const COLUMN_WIDTH: float = 292.0

## Node buttons are past the ~44–48 pt minimum touch target: this panel has to be
## operable by thumb, not only by mouse.
const NODE_HEIGHT: float = 48.0
const TAB_HEIGHT: float = 40.0
const ACTION_HEIGHT: float = 44.0

## EVERY ONE OF THESE IS THE SIZE `locale_selfcheck`'s budget table names, so they
## did not move with the skin: a budget row carries its font size, and changing
## one here without the matching edit there measures German at a size nothing
## draws. `HudTheme` ships `HEADING_FONT_SIZE` (20) and `BODY_FONT_SIZE` (14) —
## the title's 22 is this card's own title size and is the theme gap the modal
## beads leave open; `DESC_FONT_SIZE` happens to equal the theme's body size and
## is kept as a named constant only because the budget comments point at it.
const TITLE_FONT_SIZE: int = 22
const BRANCH_FONT_SIZE: int = 16
const NODE_FONT_SIZE: int = 18
const DESC_FONT_SIZE: int = 14
const TAB_FONT_SIZE: int = 16

## One rank pip. `max_ranks` runs 1 to 3 across the whole of `Progression`, so
## this is at most three squares per node and never a bar worth measuring.
const PIP_SIZE: float = 10.0
const PIP_GAP: int = 4

## The open/close key. Raw keycode, outside the input map — see the header.
const TOGGLE_KEY: Key = KEY_K

# ============================================================================
# STATE
# ============================================================================

## True while the card is up.
var _panel_open: bool = false

## Which hero's tree is on screen. Re-seeded from the live player every time the
## panel opens, so it follows a character switch without needing to watch for one.
var _view_hero: String = ""

## Whether the CURRENT tree pause is ours to release, and whether we were the one
## who freed a captured mouse. Both copied from `pause_controller.gd` /
## `mp_ui.gd` — see the header.
var _paused_by_us: bool = false
var _recapture_mouse: bool = false

## Last unspent-point count painted on the opener. -1 until the first frame, so
## the label is always drawn once — see `_refresh_open_button()`.
var _last_points: int = -1

# --- Child node references (built in _ready, not from a .tscn) --------------

var _open_button: Button = null
## The full-rect modal wrapper — the node whose `visible` IS "the panel is open".
var _centre: CenterContainer = null
var _card: PanelContainer = null
var _title_label: Label = null
var _hint_label: Label = null
var _tab_row: HBoxContainer = null
## The container the branch columns are rebuilt into on every open, hero switch
## and purchase. Ten-odd nodes, so a wholesale rebuild is cheaper to read than a
## diff and cannot go stale.
var _columns: HBoxContainer = null


func _ready() -> void:
	# Must keep running under its own pause, like every other always-available HUD
	# piece (`mp_ui.gd`, `mobile_settings_panel.gd`, `start_overlay.gd`).
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The root spans the screen but is never a hit-test target itself, so taps on
	# empty space still reach the HUD siblings drawn beneath it. The open button
	# and the card carry their own STOP filter.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# THE SKIN, adopted on our own root and inherited by everything under it.
	# Never on the scene root and never in ProjectSettings — see `hud_theme.gd`.
	theme = HudTheme.theme()
	add_to_group("skill_tree_ui")
	_build_ui()


func _process(_delta: float) -> void:
	# Yield the screen to any `touch_controls` full-rect overlay — the same three
	# lines `mp_ui.gd`, `mobile_settings_panel.gd` and `start_overlay.gd` run, and
	# for the same non-negotiable reason: the enable-motion tap is the ONE gesture
	# iOS grants DeviceMotionEvent.requestPermission() and the browser grants
	# WebAudio, and this node draws above that overlay.
	var touch_ui: Node = get_tree().get_first_node_in_group("touch_controls")
	var modal: bool = touch_ui != null and touch_ui.has_method("has_modal") and touch_ui.has_modal()
	if _open_button != null:
		_open_button.visible = not modal
	if modal and _panel_open:
		_set_panel_open(false)
		return
	if not _panel_open:
		_refresh_open_button()
	# Re-assert the pause every frame while open, for the reason `mp_ui` does: the
	# pause is taken lazily (it is declined over Game Over), so a Play Again
	# pressed with this panel up must not leave it running unpaused afterwards.
	_apply_pause(_panel_open)


func _notification(what: int) -> void:
	# Godot re-translates a plain `Label`/`Button` literal for free on this
	# notification (localization RULE 1), but the two strings this file COMPOSES —
	# the opener's "Skills (N)" and the card's title — are built with an explicit
	# `tr()` and would keep the old language until something else happened to
	# rewrite them. RULE 2's "every such site re-runs on its own" used to be true
	# here because `_refresh_open_button()` repainted every frame; gating that on a
	# change is what makes this hook necessary, so the two belong together.
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_last_points = -1  # force the opener to repaint in the new language
		if _panel_open:
			_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event == null:
		return
	# Esc closes, and only when we are actually open — otherwise this would eat the
	# `ui_cancel` that `player_controller._input()` uses to release the mouse.
	if _panel_open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_set_panel_open(false)
		return
	# Raw keycode, echo-filtered so holding K does not rapid-toggle.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == TOGGLE_KEY:
		get_viewport().set_input_as_handled()
		_toggle_panel()


# ============================================================================
# UI CONSTRUCTION
# ============================================================================

func _build_ui() -> void:
	# --- The opener, top-right under the ability dial --------------------
	_open_button = Button.new()
	_open_button.name = "SkillsButton"
	# FOCUS_NONE on every button this panel builds. `BaseButton` defaults to
	# FOCUS_ALL and KEEPS focus after a click, and `ui_accept` — which fires a
	# focused button — is SPACE, which is also `jump`. One click here would
	# otherwise re-open this panel on every jump for the rest of the run. Same
	# rule, same reason, as `mp_ui._make_button()`.
	_open_button.focus_mode = Control.FOCUS_NONE
	_open_button.text = "Skills"
	_open_button.add_theme_font_size_override("font_size", NODE_FONT_SIZE)
	_open_button.custom_minimum_size = Vector2(BUTTON_WIDTH, BUTTON_HEIGHT)
	_open_button.anchor_left = 1.0
	_open_button.anchor_right = 1.0
	_open_button.offset_left = -EDGE_MARGIN - BUTTON_WIDTH
	_open_button.offset_right = -EDGE_MARGIN
	_open_button.offset_top = BUTTON_TOP
	_open_button.offset_bottom = BUTTON_TOP + BUTTON_HEIGHT
	_open_button.pressed.connect(_toggle_panel)
	add_child(_open_button)

	# --- The card --------------------------------------------------------
	# A CenterContainer so the card sizes to its own content and stays centred at
	# any resolution, exactly like `start_overlay.gd`'s.
	_centre = CenterContainer.new()
	_centre.name = "Centre"
	_centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP, not IGNORE: while the card is up it is a modal and has to swallow every
	# click, or the desktop-web click-to-capture fires through it.
	_centre.mouse_filter = Control.MOUSE_FILTER_STOP
	_centre.visible = false
	add_child(_centre)

	# The stack the card lives in, so the BONE letterbox hairline can sit ON its
	# top edge: a `StyleBoxFlat` has ONE border colour, so a BONE top edge over a
	# STEEL frame is not something `HudTheme.card()` can express — it is a sibling
	# one pixel tall. Separation 0 keeps the two flush.
	var stack := VBoxContainer.new()
	stack.name = "Stack"
	stack.add_theme_constant_override("separation", 0)
	_centre.add_child(stack)
	stack.add_child(_rule(HudTheme.BONE))

	_card = PanelContainer.new()
	_card.name = "Card"
	_card.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	# The modal case: opaque INK, a 2 px STEEL frame, a hard offset shadow and
	# square corners — the whole panel language, typed nowhere in this file.
	_card.add_theme_stylebox_override("panel", HudTheme.card(true))
	stack.add_child(_card)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(CARD_WIDTH - 36.0, 0.0)
	_card.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.name = "Body"
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.custom_minimum_size = Vector2(CARD_WIDTH - 36.0, 0.0)
	scroll.add_child(vbox)

	_title_label = Label.new()
	_title_label.name = "Title"
	# Oswald BOLD; BONE comes off the theme's `Label` colour. The caps are applied
	# where the string is COMPOSED (`_rebuild`), which is the spec's draw site.
	_title_label.add_theme_font_override("font", HudTheme.heading_font())
	_title_label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	vbox.add_child(_title_label)
	# The STEEL rule the spec puts under every section heading.
	vbox.add_child(_rule(HudTheme.STEEL))

	_hint_label = Label.new()
	_hint_label.name = "Hint"
	# Secondary text is STEEL.
	_hint_label.add_theme_font_size_override("font_size", DESC_FONT_SIZE)
	_hint_label.add_theme_color_override("font_color", HudTheme.STEEL)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_hint_label)

	_tab_row = HBoxContainer.new()
	_tab_row.name = "Heroes"
	_tab_row.add_theme_constant_override("separation", 6)
	vbox.add_child(_tab_row)

	# A STEEL rule, not an `HSeparator`: the separator's line comes off the engine
	# default theme, which is a colour this file would then not own.
	vbox.add_child(_rule(HudTheme.STEEL))

	_columns = HBoxContainer.new()
	_columns.name = "Branches"
	_columns.add_theme_constant_override("separation", 16)
	vbox.add_child(_columns)

	# A STEEL rule, not an `HSeparator`: the separator's line comes off the engine
	# default theme, which is a colour this file would then not own.
	vbox.add_child(_rule(HudTheme.STEEL))
	vbox.add_child(_make_button("Close", _on_close_pressed, ACTION_HEIGHT))


## One button, FOCUS_NONE for the reason spelled out in `_build_ui`.
func _make_button(label: String, handler: Callable, height: float) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", NODE_FONT_SIZE)
	button.custom_minimum_size = Vector2(0.0, height)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(handler)
	return button


## THE CAPS RULE, and it is German orthography rather than a style choice.
## `String.to_upper()` maps ß to itself — Godot has no single-character uppercase
## for it — so "Windstoß" comes back as `WINDSTOß`. German capitalises ß as SS,
## which is one `replace` and correct in both languages (English carries no ß, so
## this is `to_upper()` exactly). Every caps heading in this file goes through it.
static func _caps(text: String) -> String:
	return text.replace("ß", "ss").to_upper()


## One hairline. `HudTheme` has no builder for either of the two this card wants
## (the BONE letterbox line over the card, the STEEL rule under a heading) and its
## closing note names the modal beads as the first that would need one — so it
## lives here, six lines, until a second panel asks for it.
func _rule(colour: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = colour
	rect.custom_minimum_size = Vector2(0.0, 1.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## The rank readout: one square per rank, VISOR_AMBER for the ranks bought and
## STEEL for the ranks left. It replaces the `"   %d/%d"` that used to be composed
## onto the node's own name, which is why the button below carries the name alone.
##
## ponytail: a row of `ColorRect`s and not a drawn widget — `max_ranks` never
## exceeds 3 in `Progression`, so this is at most three nodes per skill. A real
## meter is worth writing the day a node has ten ranks.
func _pips(rank: int, max_ranks: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Ranks"
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", PIP_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in maxi(max_ranks, 1):
		var pip := ColorRect.new()
		pip.color = HudTheme.VISOR_AMBER if i < rank else HudTheme.STEEL
		pip.custom_minimum_size = Vector2(PIP_SIZE, PIP_SIZE)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pip)
	return row


# ============================================================================
# LOOKUPS (group-based, null-safe — the project convention)
# ============================================================================

## Cached exactly like `coin_hud.gd` caches its own, and for the same reason: a
## group lookup per frame for a node that may legitimately never exist is the
## wrong shape. Re-resolved whenever it is missing or has been freed.
var _progression_node: Node = null


func _progression() -> Node:
	if _progression_node == null or not is_instance_valid(_progression_node):
		var node := get_tree().get_first_node_in_group("progression")
		_progression_node = node if node != null and node.has_method("skill_mult") else null
	return _progression_node


## The hero the player is currently in, or "" when there is no player. Used to
## seed the viewed tree on open, and to mark that hero in the tab row.
func _active_hero() -> String:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not ("current_character_index" in player):
		return ""
	var characters: Array = player.CHARACTERS
	var index: int = int(player.current_character_index)
	if index < 0 or index >= characters.size():
		return ""
	return String(characters[index]["name"])


# ============================================================================
# OPEN / CLOSE
# ============================================================================

func _toggle_panel() -> void:
	_set_panel_open(not _panel_open)


func _on_close_pressed() -> void:
	_set_panel_open(false)


func _set_panel_open(open: bool) -> void:
	if open and not _panel_open:
		# Refuse to open underneath somebody else's pause: the start overlay, the
		# P-pause overlay and the MP panel all draw at or above this node, so the
		# card would be invisible while still holding input. One test covers all
		# three (and any future one), because they all take the same pause.
		if get_tree().paused and not _paused_by_us:
			return
		# Follow the player's current character rather than remembering the last
		# tree looked at — the tree you want is almost always the one you are in.
		_view_hero = _active_hero()
	_panel_open = open
	# `_centre`, NOT `_card.get_parent()`: the card's parent is the hairline stack
	# since the skin landed, and walking up one level silently flipped the wrong
	# node's `visible` — the panel opened and drew nothing. A modal this file
	# builds is a modal this file should hold a name for.
	if _centre != null:
		_centre.visible = open
	if open:
		# Clamp the card to the visible viewport on every open (a phone's scaled
		# viewport is much shorter than a desktop one, and an orientation change
		# moves it), so the inner ScrollContainer genuinely reaches every row
		# instead of the card poking off-screen where nothing can scroll it.
		var view_height: float = get_viewport().get_visible_rect().size.y
		var scroll := _card.get_child(0) as ScrollContainer
		if scroll != null:
			scroll.custom_minimum_size = Vector2(
				CARD_WIDTH - 36.0, minf(CARD_MAX_HEIGHT, maxf(200.0, view_height - 80.0))
			)
		_rebuild()
	_apply_pause(open)


## Take or release the pause for the panel's current state, and hand the mouse
## across with it. Mirrors `mp_ui._apply_pause()` exactly, including both guards.
func _apply_pause(open: bool) -> void:
	if not open and not _paused_by_us:
		return  # The overwhelmingly common case: closed panel, nothing to undo.
	var tree := get_tree()
	var player := tree.get_first_node_in_group("player")
	var game_over: bool = player != null and bool(player.get("is_game_over"))
	if open and not game_over:
		# `not _paused_by_us`, where this used to read `not tree.paused`: under the
		# refcount the question is whether WE already hold a claim, not whether
		# anybody does. In practice this node cannot open under a foreign pause at
		# all (`_set_panel_open` refuses), so the two only differ in that the
		# re-assert from `_process` now costs nothing instead of racing.
		if not _paused_by_us:
			PauseHub.take(self)
			_paused_by_us = true
			# Free a captured mouse so the nodes can be clicked, and remember that
			# we were the one who did it — `pause_controller` and `mp_ui` may have
			# freed it first, and re-capturing on somebody else's behalf is how a
			# player ends up with a cursor pinned to screen centre.
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				_recapture_mouse = true
	elif _paused_by_us:
		_paused_by_us = false
		PauseHub.release(self)
		if _recapture_mouse:
			_recapture_mouse = false
			# Not on a touch session, for the same reason every other capture site
			# in the project skips it: there is no mouse and the request pops a
			# useless prompt over the touch controls.
			if not MobileSensors.is_touch_session():
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# ============================================================================
# RENDERING
# ============================================================================

## The `(N)` suffix on the opener, shown only while there are points to spend.
## The suffix is a bare number, so it needs no translation row of its own — the
## same rule the coin HUD's streak `(xN)` follows.
func _refresh_open_button() -> void:
	if _open_button == null:
		return
	var progression := _progression()
	var points: int = int(progression.unspent_points()) if progression != null else 0
	# ONLY ON A CHANGE — the same discipline `crocodile_lod_manager` applies to its
	# state flips. This runs every frame, and rewriting a theme override and a
	# translated string sixty times a second to say the same thing is exactly the
	# kind of idle cost the web build's perf work exists to avoid. -1 is the "not
	# yet drawn" sentinel, so the first frame always paints.
	if points == _last_points:
		return
	_last_points = points
	_open_button.text = tr("Skills") + (" (%d)" % points if points > 0 else "")
	# THE OPENER'S REGION GETS THE AMBER: an unspent point is the one thing on this
	# corner of the screen the player is meant to act on. BONE when there is
	# nothing to spend — never pure white, which is the palette's own rule.
	_open_button.add_theme_color_override(
		"font_color", HudTheme.VISOR_AMBER if points > 0 else HudTheme.BONE
	)


## Rebuild everything inside the card from the current profile. Called on open,
## on a hero tab press and after every purchase — ten-odd nodes, so a wholesale
## rebuild is both cheap and impossible to leave stale.
func _rebuild() -> void:
	var progression := _progression()
	_refresh_open_button()
	_rebuild_tabs(progression)
	_rebuild_columns(progression)

	if progression == null:
		_title_label.text = _caps(tr("Skills"))
		_hint_label.text = tr("No progression in this scene.")
		return
	var points: int = int(progression.unspent_points())
	# RULE 2: `tr()` on the FORMAT STRING, never on the formatted result. The hero
	# name is a proper noun (Windman, Primm, Teibi, Phoboman) and stays as it is in
	# every language, like the EN/DE pills on the start screen.
	#
	# `.to_upper()` AT THE DRAW SITE, which this legitimately is: the string is
	# composed here, so there is no auto-translation to lose, and the German row
	# ("%s — Stufe %d,  %d Punkte") carries no ß to mangle. The branch headings
	# below are the opposite case on both counts and stay sentence case.
	_title_label.text = _caps(tr("%s — Level %d,  %d points") % [
		_view_hero.capitalize(), int(progression.level), points
	])
	if points > 0:
		_hint_label.text = tr("Press a skill to spend a point.")
	else:
		_hint_label.text = tr("Collect coins to earn levels — each level is one skill point.")


func _rebuild_tabs(progression: Node) -> void:
	for child in _tab_row.get_children():
		child.queue_free()
	if progression == null:
		return
	var active := _active_hero()
	for hero: String in progression.SKILL_TREES:
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE  # see `_build_ui`
		# A proper noun, so untranslated on purpose; the ✓ marks the hero the
		# player is actually in, which is not necessarily the tree on screen.
		button.text = hero.capitalize() + (" ✓" if hero == active else "")
		button.add_theme_font_size_override("font_size", TAB_FONT_SIZE)
		button.custom_minimum_size = Vector2(0.0, TAB_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# THE SELECTED TAB IS A PRESSED BUTTON, not an amber one: the spec rations
		# the accent to one thing per region and the card's is the rank pips, so
		# "which tree am I looking at" is said with the INK face the theme already
		# gives a pressed button, plus BONE letters against the others' khaki.
		if hero == _view_hero:
			button.add_theme_stylebox_override("normal", HudTheme.button("pressed"))
		button.add_theme_color_override(
			"font_color", HudTheme.BONE if hero == _view_hero else HudTheme.UNIT_KHAKI
		)
		button.pressed.connect(_on_hero_tab_pressed.bind(hero))
		_tab_row.add_child(button)


func _rebuild_columns(progression: Node) -> void:
	for child in _columns.get_children():
		child.queue_free()
	if progression == null:
		return
	# One column per `branch`, in first-seen order, so adding a node to the data is
	# the whole change and this file never learns a branch name.
	var order: Array[String] = []
	var by_branch: Dictionary = {}
	for def: Dictionary in progression.skills_for(_view_hero):
		var branch := String(def.get("branch", ""))
		if not by_branch.has(branch):
			by_branch[branch] = []
			order.append(branch)
		(by_branch[branch] as Array).append(def)

	for branch: String in order:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 6)
		column.custom_minimum_size = Vector2(COLUMN_WIDTH, 0.0)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var heading := Label.new()
		# `tr()` + `_caps()` rather than the plain literal RULE 1 would allow: the
		# spec wants caps, and two of the five German branch names carry a ß. The
		# live switch survives because `_notification` rebuilds an open panel and
		# opening rebuilds a closed one. Oswald BOLD, BONE off the theme.
		heading.text = _caps(tr(branch))
		heading.add_theme_font_override("font", HudTheme.heading_font())
		heading.add_theme_font_size_override("font_size", BRANCH_FONT_SIZE)
		column.add_child(heading)
		column.add_child(_rule(HudTheme.STEEL))

		for def: Dictionary in by_branch[branch]:
			_add_node_row(column, progression, def)
		_columns.add_child(column)


func _add_node_row(column: VBoxContainer, progression: Node, def: Dictionary) -> void:
	var skill_id := String(def["id"])
	var rank: int = int(progression.rank_of(_view_hero, skill_id))
	var max_ranks: int = int(def.get("max_ranks", 1))
	var affordable: bool = bool(progression.can_spend(_view_hero, skill_id))

	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE  # see `_build_ui`
	# THE NAME ALONE. The `"   %d/%d"` counter that used to be composed on here is
	# the pip row below, so this is a plain `tr()` of the name and nothing else —
	# which also hands `locale_selfcheck`'s 232 px node-name budget back the ~48 px
	# it reserved for that counter (see the PR: the budget is now conservative, and
	# tightening it is the shared check's edit, not this file's).
	button.text = tr(String(def.get("name", skill_id)))
	button.add_theme_font_size_override("font_size", NODE_FONT_SIZE)
	button.custom_minimum_size = Vector2(0.0, NODE_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# BONE for a node you can buy now, UNIT_KHAKI — the palette's neutral/disabled
	# role — for everything else. A MAXED node needs no colour of its own any more:
	# its pips are all amber, which says "done" better than a green label did.
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(
			state, HudTheme.BONE if affordable else HudTheme.UNIT_KHAKI)
	# Not `disabled`: a greyed Button's label is close to unreadable, and a locked
	# node still has to say what it would do. The press is validated by
	# `Progression.can_spend()` inside `spend()` anyway, so an unaffordable press
	# is simply a no-op — the rules stay in one place.
	button.pressed.connect(_on_node_pressed.bind(skill_id))
	column.add_child(button)
	column.add_child(_pips(rank, max_ranks))

	var desc := Label.new()
	# Autowrap inside the fixed column, which is how German (~30% longer) is
	# handled here: the card grows downward and scrolls instead of overflowing, so
	# these strings need no width budget in `locale_selfcheck.gd`.
	desc.text = String(def.get("desc", ""))  # a plain literal: auto-translated
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", DESC_FONT_SIZE)
	# ponytail: ONE colour for every description, where there used to be two — and
	# `is_unlocked()` is no longer asked here at all. The locked/available read is
	# the button's own label plus the pips; a second dim grey under them said
	# nothing the row was not already saying, and STEEL is the palette's own
	# "inactive text". Re-split it the day a description has to differ by state.
	desc.add_theme_color_override("font_color", HudTheme.STEEL)
	desc.custom_minimum_size = Vector2(COLUMN_WIDTH - 8.0, 0.0)
	column.add_child(desc)


# ============================================================================
# HANDLERS
# ============================================================================

func _on_hero_tab_pressed(hero: String) -> void:
	_view_hero = hero
	_rebuild()


func _on_node_pressed(skill_id: String) -> void:
	var progression := _progression()
	if progression == null:
		return
	# `spend()` validates and returns false without changing anything, so this UI
	# never has to decide whether a purchase is legal. A refused press is silent
	# (the node is already visibly dim) rather than buzzing: unlike a refused F,
	# there is nothing here that could have looked ready.
	if progression.spend(_view_hero, skill_id):
		var sound: Node = get_tree().get_first_node_in_group("sound_manager")
		if sound != null and sound.has_method("play_coin"):
			sound.play_coin()
	_rebuild()
