extends SceneTree
## ============================================================================
## LOCALIZATION SELF-CHECK — run headless, prints "SELFCHECK OK", exits 0
## ============================================================================
##
##     godot --headless --path . --script res://scripts/locale_selfcheck.gd
##
## Sibling of `fauna_selfcheck.gd` / `mp_selfcheck.gd` / `minimap_selfcheck.gd`,
## and written for the same reason they were: it guards the parts of the en/de
## localization that fail **silently**.
##
## There are three of those, and each one is a real way this feature dies without
## a single error in the log:
##
##  1. **The CSV never got imported, or a row got mangled.** `tr()` returns its
##     own key when a lookup misses, so a translation table that failed to import
##     produces a perfectly working game — in English, in every locale. Nothing
##     warns. The CSV also carries genuine multi-line values (the pause overlay,
##     the phone onboarding copy, the two-line touch buttons), which are legal
##     CSV — `FileAccess.get_csv_line()` keeps reading while the quote count is
##     odd — but are exactly what a naive spreadsheet round-trip breaks. So every
##     row is re-read from source and required to resolve in BOTH locales, and
##     the German is required to actually differ from the English (an empty or
##     copy-pasted `de` column otherwise reads as a pass).
##
##  2. **A German string overflows a fixed-width control.** German runs ~30%
##     longer, and this game's touch buttons are hard-sized squares and pills
##     (`ACTION_BUTTON_SIZE` 120, the 72 px View square, the 110 px ⚙ pill) whose
##     labels do not wrap and do not clip — they just spill. Measuring the real
##     font at the real size against the real budget is the only honest way to
##     know, and it is why this check exists at all rather than a note saying the
##     strings "look short enough".
##
##  3. **The saved-language round trip.** `user://locale.cfg` is the same
##     ConfigFile pattern as `best_run.cfg` / `mobile_tuning.cfg`, and the same
##     "silently do nothing on a bad read" rule — which means a broken write is
##     invisible until a player notices their choice is forgotten.
##
## Deliberately NOT covered: that each translated string is *good* German (not a
## machine-checkable property), and the debug surfaces (F3 perf overlay, F4
## motion read-out, the ⚙ panel's raw sensor telemetry), which are excluded from
## localization by design.

const CSV_PATH: String = "res://assets/translations/ui.csv"

## The overlay script owns the locale save/load, so the round-trip test drives
## the real functions rather than a copy of them. Static, so no scene is needed.
const StartOverlay := preload("res://scripts/start_overlay.gd")

## Widths a German label must fit into, as
## `[csv key, font size, usable width px, what it is]`.
##
## The usable width is the control's own fixed width minus its padding, taken
## from the constants in the scripts that build them — these are the layouts a
## longer string can actually break. Everything omitted is omitted for a reason
## stated in CLAUDE.md: the MP room rows set `clip_text = true` (structurally
## unable to overflow), the game-over and start-overlay labels autowrap inside a
## container that grows, and the panel bodies are 340–356 px wide against strings
## a third of that. The landmark toast's name and fact labels have the same
## structural exemption as the start-overlay ones — they autowrap inside a
## VBoxContainer that grows to fit — so the geo-landmark names and facts need NO
## budget entry here and none may be added.
const WIDTH_BUDGETS: Array = [
	# touch_controls.gd — ACTION_BUTTON_SIZE 120 square, font 26, no wrap.
	["JUMP", 26, 112.0, "touch Jump button"],
	["SPECIAL\n(F)", 26, 112.0, "touch Special button"],
	["SWITCH\n(R)", 26, 112.0, "touch Switch button"],
	# touch_controls.gd — View square is TOGGLE_HEIGHT (72) on a side, font 24.
	# The tightest budget in the game.
	["View", 24, 64.0, "touch View button"],
	# touch_controls.gd — steer pill, TOGGLE_WIDTH 200 x 72, font 30.
	["Tilt/Twist", 30, 184.0, "touch steer toggle (both modes)"],
	["Steer: Tilt", 30, 184.0, "touch steer toggle (tilt)"],
	["Steer: Twist", 30, 184.0, "touch steer toggle (twist)"],
	# mobile_settings_panel.gd — GEAR_WIDTH 110 x 60, font 26, default theme
	# Button stylebox (measured: 8 px of horizontal padding), leaving 102 px; the
	# budget keeps 4 px of that as slack.
	["⚙ Tune", 26, 98.0, "⚙ tune gear button"],
	# mobile_settings_panel.gd — panel vbox is PANEL_WIDTH - 24 = 356, font 22
	# for the action buttons and 20 for the stepper name labels.
	["How to play", 22, 340.0, "⚙ panel action button"],
	["Recalibrate (re-zero)", 22, 340.0, "⚙ panel action button"],
	["Reset to defaults", 22, 340.0, "⚙ panel action button"],
	["Close", 22, 340.0, "⚙ panel action button"],
	# The CheckButton reserves room for its own toggle glyph, so it gets less.
	["Invert steering", 22, 290.0, "⚙ panel invert checkbox"],
	["TUNING  (tap −/+)", 18, 356.0, "⚙ panel section title"],
	["Step threshold", 20, 356.0, "⚙ panel stepper label"],
	["Step power", 20, 356.0, "⚙ panel stepper label"],
	["Walk decay", 20, 356.0, "⚙ panel stepper label"],
	["Step min interval", 20, 356.0, "⚙ panel stepper label"],
	["Steer deadzone", 20, 356.0, "⚙ panel stepper label"],
	["Steer full angle", 20, 356.0, "⚙ panel stepper label"],
	# mp_ui.gd — panel is PANEL_WIDTH 360 with a 10 px content margin each side;
	# every button is BODY_FONT_SIZE 18 and full-width.
	["Open rooms", 18, 320.0, "MP panel label"],
	["Refresh", 18, 320.0, "MP panel button"],
	["Host a new room", 18, 320.0, "MP panel button"],
	["…or join by invite code", 18, 320.0, "MP panel label"],
	["Join", 18, 320.0, "MP panel button"],
	["Hero", 18, 320.0, "MP panel label"],
	["Copy", 18, 320.0, "MP panel button"],
	["Leave room", 18, 320.0, "MP panel button"],
	["Tap a room to join", 18, 320.0, "MP panel status"],
	# start_overlay.gd — CARD_WIDTH 420 with a 20 px content margin each side.
	["PLAY SOLO", 26, 380.0, "start overlay Play Solo"],
	["MULTIPLAYER", 24, 380.0, "start overlay Multiplayer"],
]

var _failures: Array[String] = []


func _initialize() -> void:
	var rows: Array = _read_csv()
	if not _failures.is_empty():
		_finish()
		return

	_check_translations(rows)
	_check_fallback()
	_check_live_switch()
	_check_locale_config()
	_check_widths(rows)
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("SELFCHECK OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	printerr("SELFCHECK FAILED (%d)" % _failures.size())
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


# ============================================================================
# CSV
# ============================================================================

## Re-read the translation source, so the check is against what a translator
## actually edits rather than against whatever happened to get imported.
## Returns an array of `{ "key", "en", "de" }`.
func _read_csv() -> Array:
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		_fail("cannot open %s (error %d)" % [CSV_PATH, FileAccess.get_open_error()])
		return []

	var header: PackedStringArray = file.get_csv_line()
	if header.size() < 3 or header[0] != "keys" or header[1] != "en" or header[2] != "de":
		_fail("%s header must be `keys,en,de`, got %s" % [CSV_PATH, String(",").join(header)])
		return []

	var rows: Array = []
	var seen: Dictionary = {}
	while not file.eof_reached():
		var line: PackedStringArray = file.get_csv_line()
		# A trailing newline yields one empty field — that is the normal end, not
		# a malformed row.
		if line.size() == 1 and line[0].is_empty():
			continue
		if line.size() != 3:
			_fail("row %d has %d columns, expected 3: %s"
				% [rows.size() + 1, line.size(), String(",").join(line)])
			continue
		var key: String = line[0]
		if key.is_empty():
			_fail("row %d has an empty key" % [rows.size() + 1])
			continue
		# A duplicate key is silent in Godot (last one wins), and it is the exact
		# shape a careless copy-paste takes.
		if seen.has(key):
			_fail("duplicate key %s" % [key.c_escape()])
			continue
		seen[key] = true
		rows.append({ "key": key, "en": line[1], "de": line[2] })
	return rows


# ============================================================================
# CHECKS
# ============================================================================

## Every key must resolve, in both locales, to exactly what the CSV says — which
## is what proves the import ran and the table is registered. The German must
## also differ from the English, which is what catches an unfilled column.
func _check_translations(rows: Array) -> void:
	if rows.is_empty():
		_fail("%s contains no rows" % CSV_PATH)
		return

	var restore: String = TranslationServer.get_locale()

	TranslationServer.set_locale("en")
	for row: Dictionary in rows:
		var got: String = tr(row["key"])
		if got != row["en"]:
			_fail("en: tr(%s) = %s, expected %s"
				% [String(row["key"]).c_escape(), got.c_escape(), String(row["en"]).c_escape()])

	TranslationServer.set_locale("de")
	for row: Dictionary in rows:
		var got: String = tr(row["key"])
		if got != row["de"]:
			_fail("de: tr(%s) = %s, expected %s"
				% [String(row["key"]).c_escape(), got.c_escape(), String(row["de"]).c_escape()])
		# A key deliberately identical in both languages would trip this; there
		# are none in the table, and the day one is added it should be dropped
		# from the CSV entirely rather than duplicated (a missing key already
		# falls back to its own English text).
		if row["de"] == row["en"]:
			_fail("de column is identical to en for %s — untranslated?"
				% [String(row["key"]).c_escape()])

	TranslationServer.set_locale(restore)


## A key with no entry must come back unchanged. This is the whole reason the
## keys ARE the English source strings: a string somebody forgets to add to the
## CSV renders as readable English, never as a raw identifier.
func _check_fallback() -> void:
	var restore: String = TranslationServer.get_locale()
	TranslationServer.set_locale("de")
	const MISSING := "This string is deliberately absent from ui.csv"
	if tr(MISSING) != MISSING:
		_fail("a missing key did not fall back to itself")
	# A regional locale must resolve through to the base language, because that
	# is what a real German browser reports from `OS.get_locale()`.
	TranslationServer.set_locale("de_DE")
	if tr("PLAY SOLO") == "PLAY SOLO":
		_fail("locale de_DE did not fall through to the de translation")
	TranslationServer.set_locale(restore)


## THE ACCEPTANCE CRITERION, asserted mechanically: an already-built Control
## re-renders in the new language when the locale changes, with nothing touching
## it.
##
## This is the load-bearing claim of the whole design — it is why nearly every
## call site needed no `tr()` and why no screen needs a rebuild or a re-apply
## hook. It rests on two engine behaviours that are invisible from the call
## sites and would break silently: `Control.auto_translate_mode` being enabled
## (`AUTO_TRANSLATE_MODE_INHERIT`, the default — but one `DISABLED` on a parent
## silently freezes its whole subtree in one language), and
## `TranslationServer.set_locale()` broadcasting NOTIFICATION_TRANSLATION_CHANGED
## through the tree.
##
## Both halves are checked: `atr()` proves the auto-translate PATH resolves (it
## is what a Control calls on its own text, honouring the mode), and the minimum
## size proves the node actually RE-LAID-OUT rather than merely knowing a better
## answer — a Label that kept its English width is one that never got the
## notification, which is exactly what the player would see.
func _check_live_switch() -> void:
	var restore: String = TranslationServer.get_locale()
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 26)
	root.add_child(label)
	label.text = "PLAY SOLO"

	TranslationServer.set_locale("en")
	var english_width: float = label.get_minimum_size().x
	if label.atr(label.text) != "PLAY SOLO":
		_fail("live switch: atr() did not resolve in en")

	TranslationServer.set_locale("de")
	if label.atr(label.text) != "ALLEIN SPIELEN":
		_fail("live switch: atr() did not resolve in de — auto_translate_mode disabled?")
	if label.get_minimum_size().x == english_width:
		_fail("live switch: the label did not re-lay-out after set_locale — "
			+ "NOTIFICATION_TRANSLATION_CHANGED did not reach it")

	label.queue_free()
	TranslationServer.set_locale(restore)


## The saved-language round trip, driven through `start_overlay.gd`'s own static
## functions. The player's real saved choice is snapshotted and put back, so
## running this check never changes the language of the developer's own build.
func _check_locale_config() -> void:
	var restore_locale: String = TranslationServer.get_locale()
	var previous: Variant = null
	var config := ConfigFile.new()
	if config.load(StartOverlay.LOCALE_CONFIG_PATH) == OK:
		previous = config.get_value(
			StartOverlay.LOCALE_CONFIG_SECTION, StartOverlay.LOCALE_CONFIG_KEY, null)

	StartOverlay.save_locale("de")
	if TranslationServer.get_locale() != "de":
		_fail("save_locale(de) did not switch the locale")
	TranslationServer.set_locale("en")
	StartOverlay.apply_saved_locale()
	if TranslationServer.get_locale() != "de":
		_fail("apply_saved_locale() did not restore the saved de choice")

	# An unknown code must be refused on both sides, or a hand-edited config file
	# strands the game in a locale with no translations and no active pill.
	StartOverlay.save_locale("xx")
	if TranslationServer.get_locale() != "de":
		_fail("save_locale() accepted an unknown locale")

	# Put the developer's own choice back.
	var restore_config := ConfigFile.new()
	if previous == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(
			StartOverlay.LOCALE_CONFIG_PATH))
	else:
		restore_config.set_value(
			StartOverlay.LOCALE_CONFIG_SECTION, StartOverlay.LOCALE_CONFIG_KEY, previous)
		restore_config.save(StartOverlay.LOCALE_CONFIG_PATH)
	TranslationServer.set_locale(restore_locale)


## Measure every budgeted German string in the real font at the real size. A
## multi-line label is judged on its widest line, which is what actually decides
## whether the control overflows.
func _check_widths(rows: Array) -> void:
	var font: Font = ThemeDB.get_default_theme().get_font("font", "Button")
	if font == null:
		font = ThemeDB.fallback_font
	if font == null:
		_fail("no font available — the width check would pass vacuously")
		return
	# Prove the ruler works before trusting any measurement it makes. A headless
	# build configured with the dummy text server measures everything as 0, which
	# would turn every assertion below into a silent pass.
	if font.get_string_size("MMMM", HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x <= 0.0:
		_fail("font measured a non-empty string as 0 wide — the width check would pass vacuously")
		return

	var german: Dictionary = {}
	for row: Dictionary in rows:
		german[row["key"]] = row["de"]

	for budget: Array in WIDTH_BUDGETS:
		var key: String = budget[0]
		var font_size: int = budget[1]
		var limit: float = budget[2]
		var where: String = budget[3]
		if not german.has(key):
			_fail("%s: budgeted key %s is not in %s" % [where, key.c_escape(), CSV_PATH])
			continue
		for text: String in [key, String(german[key])]:
			for line: String in text.split("\n"):
				var width: float = font.get_string_size(
					line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				if width > limit:
					_fail("%s: %s is %.1f px wide at font size %d, over the %.0f px budget"
						% [where, line.c_escape(), width, font_size, limit])
