extends SceneTree
## ============================================================================
## HELP OVERLAY SELF-CHECK — run headless, prints "SELFCHECK OK", exits 0
## ============================================================================
##
##     godot --headless --path . --import      # once, for the .translation files
##     godot --headless --path . --script res://scripts/help_selfcheck.gd
##
## Sibling of `minimap_selfcheck.gd` / `locale_selfcheck.gd`, and written for the
## same reason: it guards the ways this feature dies **without an error in the
## log**. Explicit `if`s rather than `assert`s, because asserts are stripped from
## release builds and this file's value is that it still works a year from now.
##
## What it guards, and why each one is worth a check:
##
##  1. **A stuck pause.** The overlay takes `get_tree().paused`. If closing ever
##     stops releasing it, the game is *frozen forever* with nothing on screen to
##     say why and no error anywhere. So every close is followed by an assertion
##     that the tree is running again — and the deliberate NEGATIVE CONTROL is
##     `_check_pause_is_shared()`, which leaves the pause on and proves the check
##     would have caught it.
##
##  2. **Cancelling somebody else's pause.** `start_overlay`, `pause_controller`,
##     `mp_ui` and `mobile_input` all pause the same tree and all carry the
##     `_paused_by_us` guard. A help overlay that unpauses unconditionally would
##     drop the P-pause (or the start menu's) out from under a still-visible
##     overlay — a running game behind a "PAUSED" card. Checked by opening and
##     closing the help *under a foreign pause* and requiring the pause to
##     survive.
##
##  3. **The list going stale — the whole reason this feature exists.** The
##     `print()` in `player_controller._ready()` that the overlay replaces had
##     drifted to the point of naming the wrong key for switching character. So
##     the key legends are read back against the REAL sources: `project.godot`'s
##     input map for the gameplay keys, and the raw-keycode constants in
##     `minimap_hud` / `pause_controller` / `perf_overlay` / `motion_debug` /
##     `landmark_toast` / `player_controller` for the HUD, hero and debug keys.
##     Rebind anything without
##     touching `ROWS` and this fails.
##
##  4. **An untranslated row.** A row added without its `ui.csv` entry renders in
##     English inside a German game, silently (that is exactly what `tr()` does on
##     a miss). Every non-debug row's key legend and description is required to
##     resolve to something DIFFERENT in German. Debug rows are exempt on
##     purpose — the F3/F4 surfaces they describe are excluded from localization
##     by design, and so are their rows.
##
##  5. **German too wide for the column.** The description column WRAPS, so an
##     ordinary long translation is safe by construction — but wrapping cannot
##     break a single unbreakable compound noun, which is the one German string
##     that can still overflow the card. So the longest WORD of each German
##     description is measured in the real font against `DESC_WIDTH`, and each
##     German key legend against `KEY_WIDTH`.
##
## Deliberately NOT covered: the mouse-capture handover (headless has no pointer
## lock to take — what IS checked is the half that works without one: opening
## with a free cursor must not arm the re-capture, which is the "no double
## capture" rule), and whether the German reads well, which is not machine
## checkable.

const HelpOverlay := preload("res://scripts/help_overlay.gd")
const MinimapHud := preload("res://scripts/minimap_hud.gd")
const PauseController := preload("res://scripts/pause_controller.gd")
const PerfOverlay := preload("res://scripts/perf_overlay.gd")
const MotionDebug := preload("res://scripts/motion_debug.gd")
const MobileInput := preload("res://scripts/mobile_input.gd")
const TouchControls := preload("res://scripts/touch_controls.gd")
const MobileSettingsPanel := preload("res://scripts/mobile_settings_panel.gd")
const SkillTreeUi := preload("res://scripts/skill_tree_ui.gd")
const CityMapPanel := preload("res://scripts/city_map_panel.gd")
const TowerLiftMenu := preload("res://scripts/tower_lift_menu.gd")
const LandmarkToast := preload("res://scripts/landmark_toast.gd")
const PlayerController := preload("res://scripts/player_controller.gd")

## `[input-map action, the key legend its row must carry]`. The legend may list
## several keys ("W / S"); the action's own key has to be one of them.
const ACTION_ROWS: Array = [
	["move_forward", "W / S"],
	["move_backward", "W / S"],
	["turn_left", "Q / E"],
	["turn_right", "Q / E"],
	["step_left", "A / D"],
	["step_right", "A / D"],
	["jump", "Space"],
	["run", "Shift"],
	["duck", "Ctrl"],
	["switch_character", "R"],
	["special_ability", "F"],
	["toggle_camera", "C"],
]

var _overlay: Control = null


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	Sentinel.isolate_user_state()
	_run()


func _run() -> void:
	# The pure checks first — they need no scene, so a failure there is reported
	# without waiting two seconds for a world to build.
	var failure := _check_table()
	if failure.is_empty():
		failure = _check_translations()
	if failure.is_empty():
		failure = _check_german_widths()
	if failure.is_empty():
		failure = await _check_live()
	if failure.is_empty():
		Sentinel.finish(self)
	else:
		printerr("SELFCHECK FAILED: " + failure)
		quit(1)


# ============================================================================
# 3. THE TABLE MATCHES THE GAME'S REAL KEYS
# ============================================================================

func _check_table() -> String:
	var desktop: Array = HelpOverlay.visible_rows(false)
	var touch: Array = HelpOverlay.visible_rows(true)
	if desktop.is_empty() or touch.is_empty():
		return "one of the session row lists is empty (desktop %d, touch %d)" \
			% [desktop.size(), touch.size()]
	# The two lists must actually differ, or the touch variants are dead weight.
	if desktop.size() == touch.size() and _legends(desktop) == _legends(touch):
		return "the desktop and touch lists are identical — the per-row variants do nothing"
	for row: Array in desktop:
		if int(row[2]) == HelpOverlay.Mode.TOUCH:
			return "a touch row (%s) is shown on a keyboard session" % row[0]
	for row: Array in touch:
		if int(row[2]) == HelpOverlay.Mode.DESKTOP:
			return "a keyboard row (%s) is shown on a touch session" % row[0]

	# --- The input map ------------------------------------------------------
	var legends: Array = _legends(HelpOverlay.ROWS)
	for entry: Array in ACTION_ROWS:
		var action: String = entry[0]
		var legend: String = entry[1]
		if not InputMap.has_action(action):
			return "input action \"%s\" no longer exists, but the help still lists it" % action
		if not legends.has(legend):
			return "no help row carries the legend \"%s\" for action \"%s\"" % [legend, action]
		var keys: Array = _action_key_names(action)
		if keys.is_empty():
			return "input action \"%s\" has no key bound, but the help lists \"%s\"" % [action, legend]
		var parts: PackedStringArray = legend.split(" / ")
		for key_name: String in keys:
			if not parts.has(key_name):
				return ("action \"%s\" is bound to %s, but its help row says \"%s\" — the " \
					+ "keymap drifted (this is the exact failure the old print() had)") \
					% [action, key_name, legend]

	# --- The raw-keycode HUD and debug keys ---------------------------------
	var raw: Array = [
		[MinimapHud.TOGGLE_KEYCODE, "M", "minimap_hud.TOGGLE_KEYCODE"],
		[PauseController.PAUSE_KEY, "P", "pause_controller.PAUSE_KEY"],
		[SkillTreeUi.TOGGLE_KEY, "K", "skill_tree_ui.TOGGLE_KEY"],
		[CityMapPanel.TOGGLE_KEY, "B", "city_map_panel.TOGGLE_KEY"],
		[TowerLiftMenu.TOGGLE_KEY, "L", "tower_lift_menu.TOGGLE_KEY"],
		[PerfOverlay.TOGGLE_KEYCODE, "F3", "perf_overlay.TOGGLE_KEYCODE"],
		[MotionDebug.TOGGLE_KEYCODE, "F4", "motion_debug.TOGGLE_KEYCODE"],
		[MobileInput.FORCE_ENABLE_KEYCODE, "F5", "mobile_input.FORCE_ENABLE_KEYCODE"],
		[TouchControls.FORCE_SHOW_KEYCODE, "F6", "touch_controls.FORCE_SHOW_KEYCODE"],
		[MobileSettingsPanel.FORCE_SHOW_KEYCODE, "F7", "mobile_settings_panel.FORCE_SHOW_KEYCODE"],
		# The zoom pair only asserts that a row for them EXISTS. Their keycodes are
		# punctuation whose `OS.get_keycode_string` name ("Equal", "Minus") is not the
		# legend a player reads, and re-listing the accepted keycodes here would only
		# restate the constant back to itself — a tautology, not a check.
		[MinimapHud.ZOOM_IN_KEYCODES[0], "+ / -", "minimap_hud.ZOOM_IN_KEYCODES[0]"],
		[MinimapHud.ZOOM_OUT_KEYCODES[0], "+ / -", "minimap_hud.ZOOM_OUT_KEYCODES[0]"],
	]
	for entry: Array in raw:
		var legend: String = entry[1]
		if not legends.has(legend):
			return "no help row carries the legend \"%s\" (%s)" % [legend, entry[2]]
		# The zoom keys are punctuation whose keycode name ("Equal", "Minus") is not
		# the legend a player reads, so only their presence is asserted; the letter
		# and function keys are compared by name.
		if legend == "+ / -":
			continue
		var actual: String = OS.get_keycode_string(int(entry[0]))
		if actual != legend:
			return "%s is now %s, but the help row still says \"%s\"" % [entry[2], actual, legend]

	# --- The landmark quiz answer keys --------------------------------------
	# THREE keycodes behind ONE legend, which is why they cannot ride the `raw`
	# table above: every row there is one keycode compared to one legend. Each row
	# of ANSWER_KEYCODES is the main-row/numpad pair for one option slot, and the
	# MAIN-ROW key's name is the digit the help card prints — so the whole legend
	# is rebuilt from the constant and compared. That makes this a real check and
	# not the presence-only exemption "+ / -" gets: rebind the quiz to F1-F3 and
	# the rebuilt legend stops matching the row.
	var quiz_keys := PackedStringArray()
	for pair: Array in LandmarkToast.ANSWER_KEYCODES:
		quiz_keys.append(OS.get_keycode_string(int(pair[0])))
	var quiz_legend: String = " ".join(quiz_keys)
	if not legends.has(quiz_legend):
		return ("no help row carries the legend \"%s\" — landmark_toast.ANSWER_KEYCODES " \
			+ "answers the quiz with keys the help card does not name") % quiz_legend

	# --- The hero hotkeys ---------------------------------------------------
	# Same shape, and the same reasoning, as the quiz block above: one legend over
	# four main-row/numpad pairs, rebuilt from the constant so a rebind cannot
	# leave the card naming keys that no longer pick a hero. It is a DIFFERENT
	# legend from the quiz's ("1 2 3 4" vs "1 2 3") on purpose — the two rows read
	# the same digits and the card has to say which does what.
	var hero_keys := PackedStringArray()
	for pair: Array in PlayerController.HERO_KEYCODES:
		hero_keys.append(OS.get_keycode_string(int(pair[0])))
	var hero_legend: String = " ".join(hero_keys)
	if not legends.has(hero_legend):
		return ("no help row carries the legend \"%s\" — player_controller.HERO_KEYCODES " \
			+ "switches hero with keys the help card does not name") % hero_legend
	if hero_legend == quiz_legend:
		return ("the hero hotkey row and the quiz row would share the legend \"%s\" — " \
			+ "two different actions on one legend is exactly the drift this checks for") % hero_legend

	# --- The per-hero ability one-liner -------------------------------------
	var ability_row := _row_text("F")
	if ability_row.is_empty():
		return "no help row for the F key"
	for ability_name: String in PlayerController.ABILITY_NAME.values():
		if not ability_row.contains(ability_name):
			return ("the F row does not name the \"%s\" ability — player_controller." \
				+ "ABILITY_NAME has %d abilities and the help lists a different set") \
				% [ability_name, PlayerController.ABILITY_NAME.size()]
	# ...AND THE ONE THAT IS NOT IN THAT DICT. Air Sight is a SECOND ability on an
	# existing hero — Windman's F under the HQ's roof — rather than a fifth hero, so
	# walking `ABILITY_NAME` cannot see it and the card was free to keep telling
	# players that F flies indoors (codex review). Read off the same const
	# `get_ability_name()` returns, so renaming it fails here rather than drifting.
	if not ability_row.contains(PlayerController.INDOOR_ABILITY_NAME):
		return ("the F row does not name \"%s\" — player_controller hands it to the HUD " \
			+ "indoors and the card still promises only the outdoor ability") \
			% PlayerController.INDOOR_ABILITY_NAME

	# --- The gait modifier reads as a MODIFIER ------------------------------
	# Bead `godot-test1-kov` inverted the gait: nothing held is the fast gait and
	# Shift slows you. The legend check above CANNOT SEE THAT — it compares the
	# action's bound key against the row's legend, and the binding did not move, so
	# a card still promising "Run." passes every assertion in this block. The
	# BEHAVIOUR half is `wade_selfcheck` check 5, which presses the real action and
	# reads the shipped `calculate_current_speed()`; this half is the card, held to
	# the same string-content strength as the F row's ability names below.
	var gait_row := _row_text(_legend_for_action("run"))
	if gait_row.is_empty():
		return "no help row for the gait modifier"
	if not gait_row.to_lower().contains("slow"):
		return ("the gait-modifier row says \"%s\" — the key SLOWS the hero since bead " \
			+ "godot-test1-kov and the card has to say so") % gait_row
	if gait_row.to_lower().contains("run."):
		return ("the gait-modifier row says \"%s\" — it still advertises the key as RUN, " \
			+ "which is the behaviour godot-test1-kov reversed") % gait_row

	# --- The heroes ---------------------------------------------------------
	var switch_row := _row_text("R")
	for character: Dictionary in PlayerController.CHARACTERS:
		var hero: String = String(character["name"]).capitalize()
		if not switch_row.to_lower().contains(hero.to_lower()):
			return "the switch-hero row does not name \"%s\"" % hero

	print("table: %d desktop rows, %d touch rows, %d actions checked against the input map" \
		% [desktop.size(), touch.size(), ACTION_ROWS.size()])
	Sentinel.done("table")
	return ""


## Every key name bound to an action, as `OS.get_keycode_string` reports it. The
## project binds by PHYSICAL keycode, so that is what is read.
func _action_key_names(action: String) -> Array:
	var names: Array = []
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			var code: int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
			names.append(OS.get_keycode_string(code))
	return names


func _legends(rows: Array) -> Array:
	var out: Array = []
	for row: Array in rows:
		out.append(String(row[0]))
	return out


## The legend `ACTION_ROWS` pairs with an action — so the row an action's card
## lives on is never spelled twice in this file.
func _legend_for_action(action: String) -> String:
	for entry: Array in ACTION_ROWS:
		if String(entry[0]) == action:
			return String(entry[1])
	return ""


func _row_text(legend: String) -> String:
	for row: Array in HelpOverlay.ROWS:
		if String(row[0]) == legend:
			return String(row[1])
	return ""


# ============================================================================
# 4. EVERY NON-DEBUG STRING IS TRANSLATED
# ============================================================================

func _check_translations() -> String:
	var previous: String = TranslationServer.get_locale()
	TranslationServer.set_locale("de")
	var failure := ""
	# The DESCRIPTIONS are held to the strict rule. A key legend is exempt because
	# "Space", "Esc" and "?" are deliberately the same in both languages (they are
	# what is printed on the key), and a missing CSV row is indistinguishable from
	# that — while a description is never legitimately identical.
	var required: Array = ["CONTROLS", "Press ? or Esc to close"]
	for row: Array in HelpOverlay.ROWS:
		if int(row[2]) == HelpOverlay.Mode.DEBUG:
			continue  # excluded from localization by design — see the header
		required.append(String(row[1]))
	for english: String in required:
		if tr(english) == english:
			failure = ("%s has no German row in ui.csv — it would render in English " \
				+ "inside a German game, silently") % english.c_escape()
			break
	TranslationServer.set_locale(previous)
	Sentinel.done("translations")
	return failure


# ============================================================================
# 5. GERMAN FITS THE COLUMNS
# ============================================================================

func _check_german_widths() -> String:
	var font: Font = ThemeDB.get_default_theme().get_font("font", "Label")
	if font == null:
		font = ThemeDB.fallback_font
	if font == null:
		return "no font available — the width check would pass vacuously"
	# Prove the ruler works first: a headless build on the dummy text server
	# measures everything as 0, which turns every assertion below into a pass.
	if font.get_string_size("MMMM", HORIZONTAL_ALIGNMENT_LEFT, -1,
			HelpOverlay.ROW_FONT_SIZE).x <= 0.0:
		return "font measured a non-empty string as 0 wide — the width check would pass vacuously"

	var previous: String = TranslationServer.get_locale()
	TranslationServer.set_locale("de")
	var failure := ""
	var widest := 0.0
	for row: Array in HelpOverlay.ROWS:
		# The KEY column does not wrap, so the whole legend has to fit. Multi-line
		# legends ("SPECIAL\n(F)") are judged per line, like locale_selfcheck does.
		for line: String in tr(String(row[0])).split("\n"):
			var key_width: float = font.get_string_size(
				line, HORIZONTAL_ALIGNMENT_LEFT, -1, HelpOverlay.ROW_FONT_SIZE).x
			if key_width > HelpOverlay.KEY_WIDTH:
				failure = "key legend %s is %.1f px, over the %.0f px key column" \
					% [line.c_escape(), key_width, HelpOverlay.KEY_WIDTH]
				break
		if not failure.is_empty():
			break
		# The DESCRIPTION column wraps, so only a single unbreakable word can
		# overflow it — measure the longest one.
		for word: String in tr(String(row[1])).replace("\n", " ").split(" ", false):
			var word_width: float = font.get_string_size(
				word, HORIZONTAL_ALIGNMENT_LEFT, -1, HelpOverlay.ROW_FONT_SIZE).x
			widest = maxf(widest, word_width)
			if word_width > HelpOverlay.DESC_WIDTH:
				failure = ("the German word %s is %.1f px, wider than the %.0f px " \
					+ "description column — wrapping cannot break it") \
					% [word.c_escape(), word_width, HelpOverlay.DESC_WIDTH]
				break
		if not failure.is_empty():
			break
	TranslationServer.set_locale(previous)
	if failure.is_empty():
		print("german widths: widest unbreakable word %.1f px of %.0f px" \
			% [widest, HelpOverlay.DESC_WIDTH])
	Sentinel.done("german_widths")
	return failure


# ============================================================================
# 1 + 2. THE LIVE OVERLAY: OPENS, CLOSES, AND LEAVES THE PAUSE AS IT FOUND IT
# ============================================================================

func _check_live() -> String:
	root.add_child(load("res://scenes/main.tscn").instantiate())
	# ONE FRAME before touching anything: `_initialize()` runs before the main
	# loop, so nothing added here has had `_ready()` called yet. (The lesson
	# `minimap_selfcheck.gd` records at length.)
	await process_frame
	var failure := _start_the_game()
	if not failure.is_empty():
		return failure
	_overlay = root.get_node_or_null("Main/HUD/HelpOverlay") as Control
	if _overlay == null:
		return "no HelpOverlay under Main/HUD — was it dropped from main.tscn?"
	if not _overlay.has_method("toggle"):
		return "HelpOverlay has no script — run `godot --headless --path . --import` first, " \
			+ "or class_name types fail to resolve and this check passes vacuously"

	failure = await _check_open_close()
	if failure.is_empty():
		failure = await _check_escape_closes()
	if failure.is_empty():
		failure = await _check_pause_is_shared()
	if failure.is_empty():
		failure = await _check_no_double_capture()
	Sentinel.done("live")
	return failure


func _start_the_game() -> String:
	"""Press PLAY SOLO — main.tscn no longer starts on its own, and `start_overlay`
	holds a pause of its own that would make every pause assertion below meaningless.
	Verbatim in spirit from `minimap_selfcheck._start_the_game()`."""
	var overlay: Node = root.get_node_or_null("Main/HUD/StartOverlay")
	if overlay == null:
		return "no StartOverlay under Main/HUD"
	if not overlay.has_method("_dismiss"):
		return "StartOverlay has no script — run `godot --headless --path . --import` first"
	overlay._dismiss()
	if paused:
		return "the tree is still paused after dismissing StartOverlay"
	return ""


## Press "?" the way a player does — through `Input.parse_input_event`, so the
## event takes the real route (viewport → `_unhandled_input`). Calling the handler
## directly would prove nothing about whether the key ever arrives.
func _press_help_key() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_QUESTION
	event.unicode = 63
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func _press_escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func _check_open_close() -> String:
	await _press_help_key()
	if not _overlay._open:
		return "\"?\" did not open the help overlay"
	if not paused:
		return "the help overlay is open but the tree is not paused"
	if not _overlay._body.visible:
		return "the help overlay is open but nothing is visible"

	await _press_help_key()
	if _overlay._open:
		return "\"?\" a second time did not close the help overlay"
	# THE negative control for the whole feature: a close that forgets to release
	# the pause freezes the game forever with nothing on screen to explain it.
	if paused:
		return "STUCK PAUSE — the help overlay closed but the tree is still paused"
	if _overlay._body.visible:
		return "the help overlay closed but its body is still visible"
	Sentinel.done("open_close")
	return ""


func _check_escape_closes() -> String:
	await _press_help_key()
	if not _overlay._open:
		return "\"?\" did not re-open the help overlay"
	await _press_escape()
	if _overlay._open:
		return "Esc did not close the help overlay"
	if paused:
		return "STUCK PAUSE — Esc closed the help overlay but the tree is still paused"
	Sentinel.done("escape_closes")
	return ""


func _check_pause_is_shared() -> String:
	"""Open and close the help UNDER somebody else's pause; the pause must survive.

	This is what `_paused_by_us` is for. Without it the help would drop the P-pause
	(or the start menu's, or the MP panel's) out from under a still-visible overlay
	— a game running behind a card that says PAUSED. It doubles as the positive
	control for the stuck-pause assertions above: here the tree is *supposed* to
	still be paused afterwards, which is only distinguishable from a bug because
	the hub still has the other holder in it.

	THE FOREIGN PAUSE IS A REAL `PauseHub` CLAIM, not a bare `paused = true`. It
	used to be the bare write, and back then this check asserted the OPPOSITE of
	what it does now — that the help claimed nothing over an existing pause. That
	was the bug (godot-test1-42y): whichever owner released first started the world
	under every overlay still on screen. The help now always claims, so the thing
	worth asserting is that the OTHER holder's claim outlives ours. The overlapping
	lifecycle itself, and the P/?/P repro this describes, live in
	`scripts/pause_selfcheck.gd`."""
	var other := Node.new()
	root.add_child(other)
	PauseHub.take(other)  # stand in for pause_controller's P
	if not paused:
		return "the stand-in holder did not pause the tree — this check would be vacuous"
	await _press_help_key()
	if not _overlay._open:
		return "the help overlay would not open under a foreign pause"
	if not _overlay._paused_by_us:
		return ("the help overlay opened over a foreign pause without claiming one — " \
			+ "the other holder's release would strand it over a running game")
	await _press_help_key()
	if _overlay._open:
		return "the help overlay would not close under a foreign pause"
	if not paused:
		return ("the help overlay released a pause it did not take — a foreign " \
			+ "overlay is now up over a running game")
	PauseHub.release(other)
	if paused:
		return "STUCK PAUSE — the last holder released and the tree is still paused"
	other.free()
	Sentinel.done("pause_is_shared")
	return ""


func _check_no_double_capture() -> String:
	"""Opening with an ALREADY FREE cursor must not arm the re-capture.

	Headless has no pointer lock, so the capture handover itself cannot be driven
	here — but this half needs none: the rule is "only give back what we took",
	and a `_recapture_mouse` armed after opening over a free cursor is exactly the
	bug that grabs the pointer from a player who had deliberately released it.

	It SETS the cursor free and opens the overlay itself rather than reading the
	flag after the checks above: those all end with the overlay closed, and
	closing clears the flag — so a version that armed it wrongly on every open
	would still show false here. Measure the effect, do not read the state back."""
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return "could not free the cursor — the re-capture check would be vacuous"
	await _press_help_key()
	if not _overlay._open:
		return "the help overlay would not open for the mouse check"
	var armed: bool = _overlay._recapture_mouse
	await _press_help_key()
	if armed:
		return "the help overlay armed a mouse re-capture without ever releasing the cursor"
	if paused:
		return "STUCK PAUSE — the mouse check left the tree paused"
	print("pause: taken and released cleanly, foreign pause survives, no phantom re-capture")
	Sentinel.done("no_double_capture")
	return ""
