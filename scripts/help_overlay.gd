extends Control
## ============================================================================
## HELP OVERLAY — "?" pauses the game and shows every key, with one line each
## ============================================================================
## The problem: this game has grown a keyboard. W/S/A/D/Q/E, Space, Shift, Ctrl,
## R, F, C, K, M, +/-, P, Esc — sixteen keys, and the only place any of them were
## ever written down was a `print()` in `player_controller._ready()` that a web
## player cannot see, and which is already **incomplete** — it predates the C
## view cycle, the M minimap and its +/- zoom, and the P pause. The prose has
## drifted outright: CLAUDE.md still said "character switching (E key)" while the
## input map has bound it to R and E to the right sidestep. A control list nobody
## reads drifts silently; that drift is the thing this file is built against.
##
## So: press **?** (or F1, or plain "/" — see `_is_help_key()`), the tree pauses
## and a two-column list of every key comes up. Esc, ? again, or the Close
## button puts it away and resumes.
##
## ----------------------------------------------------------------------------
## ONE static table, and a self-check that dares it to drift
## ----------------------------------------------------------------------------
## Every row lives in `ROWS` below and nothing else in this file knows what a key
## does. That alone would not stop the list going stale — the `print()` it
## replaces was also a single list. What stops it is `scripts/help_selfcheck.gd`,
## which reads the **input map** and `player_controller.ABILITY_NAME` back out of
## the running game and fails if the row for `jump` no longer says Space or the
## ability row no longer names all four abilities. Rebind a key in
## `project.godot` without touching this table and CI says so.
##
## ----------------------------------------------------------------------------
## The pause is the shared one, not a new one
## ----------------------------------------------------------------------------
## Every pauser in this project routes through `PauseHub` (scripts/pause_hub.gd),
## which refcounts holders: **only ever release a pause WE took, and the world
## only starts again when the LAST holder lets go.** This node carries its own
## `_paused_by_us` claim bit, which is what makes the interactions between them
## boring — open the help over a P-pause and closing it leaves the P-pause
## standing; press P again with the help still up and the world stays frozen
## behind it. `process_mode = ALWAYS` is what lets this node still hear the key
## that closes it (the same argument `pause_controller.gd`'s header makes at
## length).
##
## THIS NODE IS WHY THE HUB EXISTS. Opening over an already-paused game is the
## point of a keymap card, so under the old first-taker-owns discipline it was
## the overlay that claimed nothing and got stranded over a running world the
## moment the P-pause behind it was released. It now takes a claim of its own
## every time it opens, paused tree or not.
##
## The mouse follows `pause_controller`'s rule exactly: release a CAPTURED cursor
## on open, and re-capture on close **only if we were the one who released it**.
## A player who had already pressed Esc to free the cursor gets it left free.
##
## ----------------------------------------------------------------------------
## Localization: the table is literals, so the engine does it
## ----------------------------------------------------------------------------
## Per CLAUDE.md's RULE 1, a plain literal assigned to `Label.text` is already
## translated (and already live-switching) — so both columns are just assigned
## and `assets/translations/ui.csv` does the rest. That falls out especially well
## for the KEY column: "Space" and "Esc" have no CSV row and render as themselves
## in both languages (which is what is printed on the key), while the touch rows'
## "JUMP" / "SPECIAL\n(F)" / "View" DO have rows — the ones the touch buttons
## themselves use — so the help says exactly what is written on the button in
## whatever language the button is written in. No code, no mapping table.
##
## **German width is handled by WRAPPING, not clipping.** The description column
## is a fixed `DESC_WIDTH` with `AUTOWRAP_WORD_SMART`, so a German line ~30%
## longer than its English source takes two lines and the card grows downward
## (and scrolls — see `_build_ui`) instead of overflowing. The one thing wrapping
## cannot save is a single unbreakable compound noun wider than the column, so
## `help_selfcheck.gd` measures the longest GERMAN WORD of every row in the real
## font against `DESC_WIDTH`. That is the actual failure mode, and it is the one
## thing measured.
##
## Debug rows are deliberately NOT in the CSV — the \fo/F4 surfaces they describe
## are excluded from localization by design (`locale_selfcheck.gd` says so), and
## an untranslated key falls back to readable English for free.
##
## ----------------------------------------------------------------------------
## On touch
## ----------------------------------------------------------------------------
## Rows carry a `mode`, so a touch session sees the touch row (step in place,
## tilt to steer, the three thumb buttons) wherever it differs from the keyboard
## one and the keyboard-only rows are dropped. What this file does NOT do is add
## a "?" button to the phone HUD: touch already has its own how-to — the ⚙ panel's
## "How to play" re-shows `touch_controls`' onboarding card — and a second help
## affordance in the one corner of the screen that is already crowded is not an
## improvement. The touch rows are what a tablet with a keyboard sees.
## ponytail: if the ⚙ card is ever retired, the lazy replacement is one
## `_make_button` in `touch_controls._build_ui()` calling `toggle()` here.
##
## ----------------------------------------------------------------------------
## The skin is `HudTheme`'s, and this file owns none of it (bead godot-test1-y1o.28)
## ----------------------------------------------------------------------------
## The root adopts `theme = HudTheme.theme()` — on THIS Control and nowhere
## higher, which is the seam's rule: a project-wide flip would restyle every
## `Control` in the game at once. Everything below inherits it, so the card is an
## opaque INK modal with a 2 px STEEL frame and a hard shadow (`HudTheme.card(true)`),
## the descriptions are Oswald Regular in BONE and the Close button is the theme's
## own button with no override left here at all.
##
## Not one colour and not one `StyleBoxFlat` is built in this file any more. The
## two things it still draws itself are one pixel tall each — the BONE letterbox
## hairline over the card's top edge and the STEEL rule under the heading — and
## they are `_rule()`, six lines, because `HudTheme` has no builder for either
## (its own closing note says the modal-card beads are the first consumers that
## would want one). If a second panel wants a hairline, that is the theme's to
## absorb.

# ============================================================================
# THE KEYS THAT OPEN IT
# ============================================================================

## Raw keycodes, outside the project input map — the same rule `perf_overlay`'s
## O, `motion_debug`'s F4 and `minimap_hud`'s M follow: a meta/HUD key has no
## business in the gameplay map where it could collide with a rebindable action.
##
## Three aliases because "?" is not one key anywhere. On a US layout it is
## Shift+/ and arrives as `KEY_SLASH` with `unicode` 63; on a German layout it is
## Shift+ß and arrives as `KEY_SSHARP` with the same unicode; some platforms
## report `KEY_QUESTION` directly. So the unicode is the general test and these
## are the belt and braces, plus F1 for the player who expects F1.
const HELP_KEYCODES: Array[Key] = [KEY_F1, KEY_QUESTION, KEY_SLASH, KEY_HELP]

## The unicode "?" — the layout-independent half of the test above.
const QUESTION_UNICODE: int = 63

# ============================================================================
# THE TABLE
# ============================================================================

## Which sessions a row is for.
enum Mode {
	BOTH,     ## Keyboard and touch alike (the MP button).
	DESKTOP,  ## Keyboard rows — dropped on a touch session.
	TOUCH,    ## Touch rows — dropped on a keyboard session.
	DEBUG,    ## Only in OS.is_debug_build(); never localized.
}

## THE keymap. `[key legend, one-line explanation, Mode]`, and the single source
## of truth for what this game's controls are.
##
## Both strings are literals so the engine translates them (see the header). The
## explanation deliberately folds the action and its note into ONE sentence
## rather than carrying them as two columns: it halves the strings to translate
## and to width-check, and the sentence has to be readable anyway.
## ponytail: two columns if a row ever needs a note long enough to want its own
## line.
const ROWS: Array = [
	["W / S", "Move forward and back — you run by default.", Mode.DESKTOP],
	["Q / E", "Turn left and right.", Mode.DESKTOP],
	["A / D", "Strafe left or right while held.", Mode.DESKTOP],
	["Mouse", "Look around. Click to grab the cursor again.", Mode.DESKTOP],
	["Space", "Jump. A jump also breaks a crocodile's scent.", Mode.DESKTOP],
	["Shift", "Hold to slow to a walk. Let go and you run again.", Mode.DESKTOP],
	["Ctrl", "Duck and move slowly.", Mode.DESKTOP],
	["R", "Switch hero: Windman, Primm, Teibi, Phoboman.", Mode.DESKTOP],
	["1 2 3 4", "Jump straight to one hero — the numbers on the portraits.", Mode.DESKTOP],
	["F", "Special ability: Air Rush, Phase Step, Resize or Stink Wave — Air Sight indoors.", Mode.DESKTOP],
	["C", "Cycle the view: over the shoulder, eyes, front.", Mode.DESKTOP],
	["V", "Voice mic on/off in a multiplayer room (hold to talk in push-to-talk mode).", Mode.DESKTOP],



	# The landmark quiz answer keys. Raw keycodes outside the input map, like K
	# and M beneath — so `help_selfcheck.gd` cannot compare them against a bound
	# action, and its `raw` table names a constant per legend that only the toast
	# will own. Until then this row is held by the legend/description checks
	# alone, the same way "+ / -" is only asserted to EXIST.
	# The row lands with the German strings and ahead of the toast that reads
	# these keys — deliberately, so the localization half of the quiz can merge on
	# its own (the four card literals are fixed wording, not UI). Between the two
	# merges the help card names three keys that do nothing yet; the alternative
	# is a second pass over this file for one row.
	["1 2 3", "Answer a landmark quiz — coins for the right answer.", Mode.DESKTOP],
	["K", "Open the skill tree — also the Skills button, top right.", Mode.DESKTOP],
	["M", "Show or hide the minimap.", Mode.DESKTOP],
	["+ / -", "Zoom the minimap in and out.", Mode.DESKTOP],
	# The city map panel — a raw keycode like K, M and P above it, and named here
	# because a panel nobody can find is a panel that does not exist. No touch
	# variant, exactly like the M row: `city_map_panel.gd` says why.
	["B", "Open the map of Budapest and the places to find.", Mode.DESKTOP],
	# The HQ's service lift — a raw keycode like the four above it, and named here
	# for the same reason B is: a panel that only opens where you are standing is
	# unfindable if the card does not say where. No touch variant, like B and M.
	["L", "At the HQ ground landing: ride the lift, a number picks the floor.", Mode.DESKTOP],
	["P", "Pause the game.", Mode.DESKTOP],
	["Esc", "Free the mouse cursor. Press again to grab it back.", Mode.DESKTOP],
	["?", "Open or close this list.", Mode.DESKTOP],

	# Touch variants of the rows above, in the same order. "JUMP", "SPECIAL\n(F)",
	# "SWITCH\n(R)" and "View" are the touch BUTTONS' own labels, CSV keys and all,
	# so these legends read in German exactly like the buttons do.
	["Step", "Walk by stepping in place — the phone counts your steps.", Mode.TOUCH],
	["Tilt", "Tilt the phone to steer. The toggle up top switches to twist.", Mode.TOUCH],
	["JUMP", "Jump. A jump also breaks a crocodile's scent.", Mode.TOUCH],
	["SPECIAL\n(F)", "Special ability: Air Rush, Phase Step, Resize or Stink Wave — Air Sight indoors.", Mode.TOUCH],
	["SWITCH\n(R)", "Switch hero: Windman, Primm, Teibi, Phoboman.", Mode.TOUCH],
	["View", "Cycle the view: over the shoulder, eyes, front.", Mode.TOUCH],
	# "Skills" is the opener button's own CSV key, so this legend reads in German
	# exactly like the button does. A phone has no K.
	["Skills", "Open the skill tree and spend skill points.", Mode.TOUCH],
	["Tune", "Tune step and steering feel, or read how to play again.", Mode.TOUCH],

	["MP", "Multiplayer: host or join a room for up to 4 players.", Mode.BOTH],

	# Debug builds only.
	["\\fo", "Performance overlay: FPS, draw calls, live crocodiles.", Mode.DEBUG],
	["\\fb", "Teleport to Budapest's gate.", Mode.DEBUG],
	["\\fh", "Teleport to the GastroDefense HQ.", Mode.DEBUG],
	["F4", "Raw motion-sensor read-out.", Mode.DEBUG],
	["F5", "Force-enable the touch motion driver.", Mode.DEBUG],
	["F6", "Force-show the touch controls.", Mode.DEBUG],
	["F7", "Force-show the ⚙ tuning panel.", Mode.DEBUG],
]

# ============================================================================
# LAYOUT
# ============================================================================

## Width of the key column, and of the explanation column. The description width
## is the number `help_selfcheck.gd` measures German words against; the key
## column is wide enough for the widest legend ("SPECIAL\n(F)" wraps itself at
## the newline).
##
## THESE TWO ARE TEXT BUDGETS AND STAYED PUT. A key legend now sits inside an
## INK_RAISED chip, so the CONTROL is `KEY_WIDTH + KEY_CHIP_PADDING` wide — the
## chip's own margins are added to the control rather than taken out of the
## budget, because `help_selfcheck` measures the LEGEND against `KEY_WIDTH` and
## silently swallowing 16 px of it here is exactly the kind of budget that passes
## vacuously.
const KEY_WIDTH: float = 116.0
const DESC_WIDTH: float = 430.0

## What `HudTheme.strip()` costs a chip horizontally (`GRID` each side).
const KEY_CHIP_PADDING: float = 2.0 * HudTheme.GRID

## Margin from the screen edge to the card. The card FILLS what is left
## vertically and scrolls its list — which is why no amount of German, and no
## number of extra rows in a debug build, can push content off the screen.
const SCREEN_MARGIN: int = 28

## The title-card size. `HudTheme` ships `HEADING_FONT_SIZE` (20) for a section
## heading and has no TITLE size yet — its own closing note names that gap and
## the modal-card beads (.28/.31/.32) as the consumers that would fill it. 32 is
## this card's, kept from before the skin so the heading did not shrink in the
## same PR that changed its face.
const TITLE_FONT_SIZE: int = 32

## The row size, and it is the number `help_selfcheck` budgets German against —
## unchanged on purpose, so the re-measurement in that check is of the FONT and
## nothing else.
const ROW_FONT_SIZE: int = 18

## How dark the scrim over the world is. INK, like everything else here.
const DIM_ALPHA: float = 0.82

# ============================================================================
# STATE
# ============================================================================

## Whether the list is up. The pause and the cursor follow this.
var _open: bool = false

## True only while the CURRENT tree pause is ours to release. See the header.
var _paused_by_us: bool = false

## True when opening released a CAPTURED cursor, and closing should give it back.
var _recapture_mouse: bool = false

## Cached — the touch probe can reach into JavaScriptBridge, and the answer
## cannot change mid-session (same caching `start_overlay.gd` does).
var _is_touch: bool = false

## Everything visible, so opening and closing is one `visible` flip.
var _body: Control = null


func _ready() -> void:
	# Keep hearing input under our own pause — without this the key that opens the
	# overlay could never close it. Same reason `pause_controller.gd` is a node of
	# its own rather than a branch in the player.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The root spans the screen but never hit-tests; `_body` is the modal.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# THE SKIN, adopted on our own root and inherited by everything under it.
	# Never on the scene root and never in ProjectSettings — see `hud_theme.gd`.
	theme = HudTheme.theme()
	_is_touch = MobileSensors.is_touch_session()
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	# _unhandled_input, NOT _input: a focused LineEdit (the MP panel's invite-code
	# field) consumes its own keys first, so typing a "?" into an invite code types
	# a "?" instead of throwing this list over the panel.
	if event == null:
		return
	if _is_help_key(event):
		get_viewport().set_input_as_handled()
		toggle()
		return
	if _open and event.is_action_pressed("ui_cancel"):
		# Swallow it, or `player_controller._input()`'s Esc handler would also see
		# it and toggle the mouse capture we are in the middle of restoring. (It is
		# PAUSABLE and so silent under our pause, but this node is ALWAYS and runs
		# first either way — belt and braces for the pause we did NOT take, e.g.
		# the help opened over a P-pause.)
		get_viewport().set_input_as_handled()
		_set_open(false)


func _is_help_key(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return false
	var key := event as InputEventKey
	return key.unicode == QUESTION_UNICODE or key.keycode in HELP_KEYCODES


# ============================================================================
# OPEN / CLOSE
# ============================================================================

## Public so a future button (see the header's touch note) has something to call.
func toggle() -> void:
	_set_open(not _open)


func _set_open(open: bool) -> void:
	if open == _open:
		return
	if open and not _may_open():
		return
	_open = open
	if _body != null:
		_body.visible = open
	_apply_pause(open)


## Two places this list must not appear over.
func _may_open() -> bool:
	var tree := get_tree()
	# Game Over: `pause_controller` refuses for the same reason — the Play Again
	# button needs a live cursor, and "paused behind game over" is a state nobody
	# can read.
	var player: Node = tree.get_first_node_in_group("player")
	if player != null and bool(player.get("is_game_over")):
		return false
	# One of `touch_controls`' full-rect overlays: its first-run tap is the ONE
	# user gesture iOS grants motion permission and the browser grants audio, and
	# our dim is MOUSE_FILTER_STOP — it would eat that tap. The same yield
	# `start_overlay.gd` and `mp_ui.gd` make.
	var touch_ui: Node = tree.get_first_node_in_group("touch_controls")
	if touch_ui != null and touch_ui.has_method("has_modal") and bool(touch_ui.has_modal()):
		return false
	return true


## Take or release the pause, and hand the mouse across with it. The
## `_paused_by_us` guard is the one every pauser in this project carries: releasing
## a pause somebody else took would strand their overlay over a running game.
##
## THE CLAIM IS UNCONDITIONAL, and that is the fix. The old `if not tree.paused`
## around it meant a help card opened over the P-pause held nothing, so the next P
## started the world underneath it. `PauseHub.take()` is idempotent, so claiming
## over an existing pause simply makes us the second holder and the world stays
## frozen until BOTH let go.
func _apply_pause(open: bool) -> void:
	if open:
		if not _paused_by_us:
			PauseHub.take(self)
			_paused_by_us = true
		# Free the cursor so Close is clickable — and remember that we did, so a
		# player who had already freed it themselves gets it left alone.
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			_recapture_mouse = true
		return
	if _paused_by_us:
		_paused_by_us = false
		PauseHub.release(self)
	if _recapture_mouse:
		_recapture_mouse = false
		# The keypress/click that closed the list IS the user gesture browsers
		# require for pointer lock, so this works on desktop web too.
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# ============================================================================
# UI CONSTRUCTION — in code, no scene file, per the project convention
# ============================================================================

func _build_ui() -> void:
	_body = Control.new()
	_body.name = "Body"
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP: a modal. Without it the desktop-web click-to-capture in
	# `player_controller._input()` fires through the dim and warps the cursor to
	# screen centre while the list is still up.
	_body.mouse_filter = Control.MOUSE_FILTER_STOP
	_body.visible = false
	add_child(_body)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(HudTheme.INK, DIM_ALPHA)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(dim)

	# MarginContainer (not CenterContainer): a CenterContainer sizes its child to
	# the child's MINIMUM, so a long German list or a debug build's five extra rows
	# would grow the card straight off the bottom of the screen with nothing to
	# clamp it. This fills the screen minus a margin, the card shrinks to
	# CARD width horizontally and fills vertically, and the list SCROLLS inside it.
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, SCREEN_MARGIN)
	_body.add_child(margin)

	# The stack the card lives in, so the letterbox hairline can sit ON its top
	# edge rather than inside its padding: a `StyleBoxFlat` has ONE border colour,
	# so a BONE top edge on a STEEL frame is not something `HudTheme.card()` can
	# express — it is a sibling one pixel tall. Separation 0 keeps the two flush.
	var stack := VBoxContainer.new()
	stack.name = "Stack"
	stack.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_theme_constant_override("separation", 0)
	margin.add_child(stack)
	stack.add_child(_rule(HudTheme.BONE, "Hairline"))

	var card := PanelContainer.new()
	card.name = "Card"
	# The modal case: opaque INK, a 2 px STEEL frame, a hard offset shadow and
	# square corners — the whole panel language, typed nowhere in this file.
	card.add_theme_stylebox_override("panel", HudTheme.card(true))
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.name = "Content"
	vbox.add_theme_constant_override("separation", HudTheme.GRID)
	card.add_child(vbox)

	var title := Label.new()
	# Already capitals in BOTH tables ("CONTROLS" / "STEUERUNG"), so the spec's
	# caps heading needs no `.to_upper()` at the draw site and the literal stays a
	# plain auto-translated one. Oswald BOLD is the heading face; BONE comes off
	# the theme's `Label` colour.
	title.text = "CONTROLS"
	title.add_theme_font_override("font", HudTheme.heading_font())
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# The STEEL rule the spec puts under every section heading.
	vbox.add_child(_rule(HudTheme.STEEL, "TitleRule"))

	var scroll := ScrollContainer.new()
	scroll.name = "List"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.name = "Keymap"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", HudTheme.GRID * 2)
	grid.add_theme_constant_override("v_separation", HudTheme.GRID)
	scroll.add_child(grid)
	for row: Array in visible_rows(_is_touch):
		grid.add_child(_make_key_label(String(row[0])))
		grid.add_child(_make_desc_label(String(row[1])))

	var hint := Label.new()
	hint.text = "Press ? or Esc to close"
	# Secondary text is STEEL, and the size is the theme's body default — the two
	# font-size overrides this label and the Close button used to carry are gone,
	# which is what "the panel renders from HudTheme alone" means in practice.
	hint.add_theme_color_override("font_color", HudTheme.STEEL)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	var close := Button.new()
	# ponytail: NOT `.to_upper()`. Godot has no single-character uppercase for ß,
	# so the German "Schließen" comes out "SCHLIEßEN" — a lowercase letter in the
	# middle of a capitalised word, which is worse than sentence case. The spec's
	# caps-button rule wants a CSV-side or font-feature answer; named for the
	# theme bead rather than shipped broken here. The heading above needs none of
	# this because both its rows are already capitals.
	close.text = "Close"
	# FOCUS_NONE, like every button in this project — `ui_accept` is SPACE, SPACE
	# is also `jump`, and `BaseButton` KEEPS focus after a click, so a focused
	# Close would re-fire on the player's very first jump. See
	# `mp_ui._make_button()` for the full version of this warning.
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_set_open.bind(false))
	vbox.add_child(close)


## The rows this session shows. Static and pure so `help_selfcheck.gd` can ask for
## both sessions' lists without a scene.
static func visible_rows(is_touch: bool) -> Array:
	var out: Array = []
	for row: Array in ROWS:
		var mode: int = int(row[2])
		var keep: bool = mode == Mode.BOTH \
			or (mode == Mode.DESKTOP and not is_touch) \
			or (mode == Mode.TOUCH and is_touch) \
			or (mode == Mode.DEBUG and OS.is_debug_build())
		if keep:
			out.append(row)
	return out


## A KEY CAP: `HudTheme.strip()` is the chip (INK_RAISED face, STEEL frame, no
## shadow — it is already on a card) and the letters are Oswald Bold in BONE off
## the theme. The colour override the key column used to carry — a warm yellow
## repeated thirty times — is gone: the spec rations VISOR_AMBER to ONE element
## per region, and thirty amber-ish chips is the opposite of that.
##
## ponytail: SHRINK_BEGIN vertically so the chip is the height of the legend and
## not of the two-line German description beside it — a key cap, not a column.
func _make_key_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", HudTheme.heading_font())
	label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	label.add_theme_stylebox_override("normal", HudTheme.strip())
	label.custom_minimum_size = Vector2(KEY_WIDTH + KEY_CHIP_PADDING, 0.0)
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _make_desc_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	# The German-width answer: WRAP. The column is a fixed width and a longer
	# translation takes a second line instead of overflowing the card.
	label.custom_minimum_size = Vector2(DESC_WIDTH, 0.0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## One hairline. `HudTheme` has no builder for either of the two this card wants
## (BONE letterbox line, STEEL heading rule) and its closing note says the modal
## beads are the first that would need one — so it lives here, six lines, until a
## second panel asks for it.
func _rule(color: Color, name: String) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = name
	rect.color = color
	rect.custom_minimum_size = Vector2(0.0, 1.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
