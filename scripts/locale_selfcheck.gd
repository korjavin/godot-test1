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
##     warns. The CSV also carries genuine multi-line values (the pause overlay
##     text), which are legal
##     CSV — `FileAccess.get_csv_line()` keeps reading while the quote count is
##     odd — but are exactly what a naive spreadsheet round-trip breaks. So every
##     row is re-read from source and required to resolve in BOTH locales, and
##     the German is required to actually differ from the English (an empty or
##     copy-pasted `de` column otherwise reads as a pass).
##
##  2. **A German string overflows a fixed-width control.** German runs ~30%
##     longer, and fixed-width controls remain all over the HUD — panel buttons,
##     opener buttons, waypoint rows, draw_string captions — whose labels do not
##     wrap and do not clip: they just spill. Measuring the real
##     font at the real size against the real budget is the only honest way to
##     know, and it is why this check exists at all rather than a note saying the
##     strings "look short enough".
##
##  3. **The saved-language round trip.** `user://locale.cfg` is the same
##     ConfigFile pattern as `best_run.cfg`, and the same
##     "silently do nothing on a bad read" rule — which means a broken write is
##     invisible until a player notices their choice is forgotten.
##
## Deliberately NOT covered: that each translated string is *good* German (not a
## machine-checkable property), and the debug surfaces (F3 perf overlay, F4
## motion read-out), which are excluded from localization by design.

const CSV_PATH: String = "res://assets/translations/ui.csv"

## The overlay script owns the locale save/load, so the round-trip test drives
## the real functions rather than a copy of them. Static, so no scene is needed.
const StartOverlay := preload("res://scripts/start_overlay.gd")
## The waypoint travel panel, for the budgets below — read off its own constants
## so a retuned card width retunes the gate rather than drifting from it.
const WaypointHub := preload("res://scripts/waypoint_hub.gd")
const PassportPanel := preload("res://scripts/passport_panel.gd")
## The skill tree panel, for the budgets below — read off its own constants
## rather than retyped, so retuning COLUMN_WIDTH or CARD_WIDTH retunes the gate
## with it (bead godot-test1-1m3x: the literals measured the OLD widths while
## the real panel overflowed in German).
const SkillTreeUi := preload("res://scripts/skill_tree_ui.gd")

## The round trip is driven against `StartOverlay.locale_config_path`, which
## `Sentinel.isolate_user_state()` has already moved into a directory private to
## this process — never the player's own `user://locale.cfg`, which a run that
## died mid-check used to leave speaking German. See `_check_locale_config`.

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
	["Voice: always on", 18, 320.0, "MP panel voice toggle"],
	["Voice: push to talk", 18, 320.0, "MP panel voice toggle"],
	["Mic: off — press V", 18, 320.0, "MP panel mic state"],
	["Mic: on — press V", 18, 320.0, "MP panel mic state"],
	["Mic: off — hold V", 18, 320.0, "MP panel mic state"],
	["Mic: transmitting", 18, 320.0, "MP panel mic state"],
	["Mic: blocked — listening only", 18, 320.0, "MP panel mic state"],
	["Mic: muted", 18, 320.0, "MP panel mic state"],
	# Every switch carries its chord in its label (bead godot-test1-k4l).
	["Mute (Ctrl+M)", 18, 320.0, "MP panel mic mute"],
	["Muted (Ctrl+M)", 18, 320.0, "MP panel mic mute"],
	["Deafen (Ctrl+D)", 18, 320.0, "MP panel deafen"],
	["Deafened (Ctrl+D)", 18, 320.0, "MP panel deafen"],
	# The volume readout is a FORMAT string, measured raw like the minimap's
	# countdowns above: "%d" stands in for at most three digits, and the label
	# autowraps in a container that grows, so the budget is the panel's own width.
	["Voice volume: %d%%", 18, 320.0, "MP panel voice volume"],
	["Camera off (Ctrl+G)", 18, 320.0, "MP panel camera toggle"],
	["Camera on (Ctrl+G)", 18, 320.0, "MP panel camera toggle"],
	["Camera blocked (Ctrl+G)", 18, 320.0, "MP panel camera toggle"],
	# The toggle itself: "Multiplayer (N)" offline, the code plus count plus key
	# online (a composed string, so unbudgeted — it measures 141 px at 19). The
	# toggle is MP_BUTTON_WIDTH_ONLINE 190 px at MP_BUTTON_FONT_SIZE_ONLINE 19,
	# less the button stylebox's horizontal padding: 166 px usable.
	["Multiplayer (N)", 19, 166.0, "MP toggle button"],
	# help_hint.gd — the "? (hotkeys)" chip bottom-right, font 18. The chip
	# auto-sizes (text plus the strip's 2*GRID padding), so the budget guards
	# corner-collision growth, not clipping: 85 px measured German plus a
	# 30 px named reserve for longer translations.
	["? (hotkeys)", 18, 85.0 + 30.0, "help hint"],
	# The per-member mute toggle is the one NARROW control in this panel: it sits
	# at the end of a member row beside a clipping 32-character name, so its
	# `MUTE_BUTTON_WIDTH` (104) less the default Button stylebox's horizontal
	# padding is the whole budget. The name label is exempt for the room rows'
	# reason — `clip_text` makes it structurally unable to overflow.
	["Mute", 18, 96.0, "MP panel per-peer mute"],
	["Muted", 18, 96.0, "MP panel per-peer mute"],

	# mp_ui.gd HUD voice/camera switches above the MP button (bead godot-test1-xtr.20)
	# HUD_VOICE_BUTTON_WIDTH 260 px less 2*CARD_PADDING (24) = 236.0 px usable
	# width, font 18 (bead godot-test1-k4l: the chord suffixes outgrew the 190).
	["Mute (Ctrl+M)", 18, 236.0, "HUD mic mute"],
	["Muted (Ctrl+M)", 18, 236.0, "HUD mic mute"],
	["Deafen (Ctrl+D)", 18, 236.0, "HUD deafen"],
	["Deafened (Ctrl+D)", 18, 236.0, "HUD deafen"],
	["Camera off (Ctrl+G)", 18, 236.0, "HUD camera toggle"],
	["Camera on (Ctrl+G)", 18, 236.0, "HUD camera toggle"],
	["Camera blocked (Ctrl+G)", 18, 236.0, "HUD camera toggle"],

	# start_overlay.gd — CARD_WIDTH 420 with a 20 px content margin each side.
	# One button since bead godot-test1-6pa dropped the SOLO / MULTIPLAYER fork.
	# The card's hint line is exempt for the reason stated in the header above: it
	# autowraps inside a container that grows.
	["PLAY", 24, 380.0, "start overlay Play"],
	# "PLAY SOLO" and "MULTIPLAYER" are no longer buttons, but their CSV rows stay
	# — they are this file's own translation sentinels in `_check_fallback()` and
	# `_check_live_switch()`, and `landmark_selfcheck` uses the first one too.
	# skill_tree_ui.gd — only the strings that CANNOT wrap are budgeted. The node
	# descriptions and the two hint lines autowrap inside their column, so German
	# grows the card downward (it scrolls) instead of overflowing it; that is the
	# same wrapping-not-clipping rule the help card uses, and it is why 11 long
	# sentences are absent from this table.
	#
	# BUTTON_WIDTH 166, font 18, the theme's 2*CARD_PADDING (24) of Button
	# padding — 142 usable — MINUS the " (12)" two-digit unspent-points suffix
	# past the "(K)" hotkey (review round 1: without the reserve a future
	# German string up to 142 would pass while the composed label clips).
	# The suffix measures ~37 px at this size, so the key itself is held to
	# 105: "Können (K) (12)" at 132 still fits the 142 the button offers.
	["Skills (K)", 18, 142.0 - 37.0, "skill tree opener"],
	# city_map_panel.gd — the Budapest map's opener, parked under the one above
	# and sharing its BUTTON_WIDTH (166) and font, so the same 142 usable px.
	# No composed suffix on this face, so it gets the whole budget.
	["Map (B)", 18, 142.0, "Budapest map opener"],

	# waypoint_hub.gd — the travel panel (epic godot-test1-sc6, bead .4). It has
	# NO opener button: the circle you stand on is the opener, so the only faces
	# here are the card's own. Every budget is read off the panel's constants
	# rather than retyped, so retuning `CARD_WIDTH` retunes the gate with it.
	#
	# The title is a Label across the card's inner width; the two wrapping lines
	# (the empty-list line and the close hint) are exempt for the reason the
	# header gives — they autowrap inside a container that grows.
	["Waypoints", WaypointHub.TITLE_FONT_SIZE, WaypointHub.CARD_WIDTH,
		"waypoint panel title"],
	# The price line does NOT wrap: it is one composed line under the rows.
	["Travel costs %d coins.", WaypointHub.LINE_FONT_SIZE, WaypointHub.CARD_WIDTH,
		"waypoint panel price"],
	# THE ROW NAMES, against what a row leaves the name after the distance column.
	# `clip_text` means an overflow here eats its own tail rather than running
	# under the distance — which is a silent failure, and so is exactly what wants
	# a budget. Two of the city rows borrow the landmark table's own names and are
	# budgeted with the rest.
	["HQ gate", WaypointHub.ROW_FONT_SIZE, WaypointHub.NAME_WIDTH, "waypoint row name"],
	["HQ approach", WaypointHub.ROW_FONT_SIZE, WaypointHub.NAME_WIDTH, "waypoint row name"],
	["The spawn", WaypointHub.ROW_FONT_SIZE, WaypointHub.NAME_WIDTH, "waypoint row name"],
	["Road, %d m", WaypointHub.ROW_FONT_SIZE, WaypointHub.NAME_WIDTH, "waypoint row name"],
	["Budapest gate", WaypointHub.ROW_FONT_SIZE, WaypointHub.NAME_WIDTH, "waypoint row name"],
	["Pest embankment", WaypointHub.ROW_FONT_SIZE, WaypointHub.NAME_WIDTH, "waypoint row name"],
	["Hungarian Parliament", WaypointHub.ROW_FONT_SIZE, WaypointHub.NAME_WIDTH, "waypoint row name"],
	["Great Market Hall", WaypointHub.ROW_FONT_SIZE, WaypointHub.NAME_WIDTH, "waypoint row name"],
	["Heroes' Square", WaypointHub.ROW_FONT_SIZE, WaypointHub.NAME_WIDTH, "waypoint row name"],
	# ...and the right-hand column, which is drawn in the same rect from the other
	# edge. Only "You are here" is budgeted: the other thing that column can hold
	# is `WaypointHub.DISTANCE_LINE` ("%d m"), which has NO CSV row on purpose —
	# German spells it the same, and `_check_translations` below fails a row whose
	# two columns match. It is four digits and a unit against twelve characters of
	# German here, so the wider of the two is the one that gates the column.
	["You are here", WaypointHub.ROW_FONT_SIZE, WaypointHub.DISTANCE_WIDTH,
		"waypoint row distance"],
	# passport_panel.gd — the discovery passport (bead godot-test1-0bnw.1). Card
	# width is fixed and the stamp face does not wrap, so every face the stamp
	# is drawn in gets a row: the title and the count across the panel inner
	# width, each of the 48 stamps against the card inner width at the stamp
	# size. All widths read off the panel constants, never retyped.
	["Discovery passport", PassportPanel.TITLE_FONT_SIZE, PassportPanel.PANEL_INNER_WIDTH,
		"passport title"],
	["%d strange places found", PassportPanel.COUNT_FONT_SIZE, PassportPanel.PANEL_INNER_WIDTH,
		"passport count"],
	["Stones. Arranged. Nobody says why.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Heads that outstared the sea.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Four thousand years, zero moving parts.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Painted orange so ships would see it.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["A gift that came in 350 crates.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["A square that burned down three times.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Meant to last twenty years.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["A tomb, not a palace.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Seated fifty thousand. Emptied in minutes.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["The bell, not the tower.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Started leaning before it was finished.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Nose missing since before anyone wrote it down.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Struck by lightning. Kept the arms open.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["A gate that floats at high tide.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Not visible from space. Visible from here.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["A gate that has faced both ways.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Built for one king. Seen by millions.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Six centuries to finish. Worth it.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Nine chapels wearing one hat.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["A million tiles, all the same shade.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["A staircase that turns into a serpent.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Carved in, not built up.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Four faces, no necks.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Faces west, toward the setting sun.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Never found by the conquistadors.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Water ran here, not traffic.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Nineteen mills against one sea.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["A lighthouse that outlived its city.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["A glass dome over a parliament.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["A sun-cross on a socialist sphere.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Roman, black, still standing.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Leaning inward, by mistake.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Rebuilt from its own rubble.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["A wave of glass on a warehouse.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["A cross where Germany runs out.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["A castle that hid a translator.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["The tallest church spire on Earth.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Four animals that never reached Bremen.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Its columns lean so it looks straight.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Still not finished. Still open.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Opens for boats. Not for cars.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Twelve avenues meet under one arch.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["One iron crystal, 165 billion times bigger.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Was an advert for houses.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Sketched on a napkin.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Burned, rebuilt, made of concrete.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Wood, tar, and 800 winters.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	["Toss a coin; they sweep it up nightly.", PassportPanel.STAMP_FONT_SIZE, PassportPanel.CARD_INNER_WIDTH,
		"passport stamp"],
	# skill_tree_ui.gd — every budget DERIVED, never retyped (bead
	# godot-test1-1m3x): node names against the column less the button's text
	# reserve, headings against the column itself. The second-skill names ride
	# both faces — a node button AND a branch heading — so both rows name them.
	["Quick Recovery", 18, SkillTreeUi.COLUMN_WIDTH - SkillTreeUi.NODE_TEXT_RESERVE, "skill node name"],
	["Second Wind", 18, SkillTreeUi.COLUMN_WIDTH - SkillTreeUi.NODE_TEXT_RESERVE, "skill node name"],
	["Fleet Foot", 18, SkillTreeUi.COLUMN_WIDTH - SkillTreeUi.NODE_TEXT_RESERVE, "skill node name"],
	["Long Gale", 18, SkillTreeUi.COLUMN_WIDTH - SkillTreeUi.NODE_TEXT_RESERVE, "skill node name"],
	["Updraft", 18, SkillTreeUi.COLUMN_WIDTH - SkillTreeUi.NODE_TEXT_RESERVE, "skill node name"],
	["Long Step", 18, SkillTreeUi.COLUMN_WIDTH - SkillTreeUi.NODE_TEXT_RESERVE, "skill node name"],
	["Phase Echo", 18, SkillTreeUi.COLUMN_WIDTH - SkillTreeUi.NODE_TEXT_RESERVE, "skill node name"],
	["Held Form", 18, SkillTreeUi.COLUMN_WIDTH - SkillTreeUi.NODE_TEXT_RESERVE, "skill node name"],
	["Scurry", 18, SkillTreeUi.COLUMN_WIDTH - SkillTreeUi.NODE_TEXT_RESERVE, "skill node name"],
	["Lingering Reek", 18, SkillTreeUi.COLUMN_WIDTH - SkillTreeUi.NODE_TEXT_RESERVE, "skill node name"],
	["Billowing Cloud", 18, SkillTreeUi.COLUMN_WIDTH - SkillTreeUi.NODE_TEXT_RESERVE, "skill node name"],
	# The active/exotic nodes (bead godot-test1-20z.4) share the same column.
	["Adrenaline", 18, SkillTreeUi.COLUMN_WIDTH - SkillTreeUi.NODE_TEXT_RESERVE, "skill node name"],
	["Feather Fall", 18, SkillTreeUi.COLUMN_WIDTH - SkillTreeUi.NODE_TEXT_RESERVE, "skill node name"],
	["Crush Quake", 18, SkillTreeUi.COLUMN_WIDTH - SkillTreeUi.NODE_TEXT_RESERVE, "skill node name"],
	["Air Sight", 18, SkillTreeUi.COLUMN_WIDTH - SkillTreeUi.NODE_TEXT_RESERVE, "skill node name"],
	["Twin Flash", 18, SkillTreeUi.COLUMN_WIDTH - SkillTreeUi.NODE_TEXT_RESERVE, "skill node name"],
	# Branch headings are plain Labels the full width of their column.
	["Focus", 16, SkillTreeUi.COLUMN_WIDTH, "skill branch heading"],
	["Air Rush", 16, SkillTreeUi.COLUMN_WIDTH, "skill branch heading"],
	["Phase Step", 16, SkillTreeUi.COLUMN_WIDTH, "skill branch heading"],
	["Resize", 16, SkillTreeUi.COLUMN_WIDTH, "skill branch heading"],
	["Stink Wave", 16, SkillTreeUi.COLUMN_WIDTH, "skill branch heading"],
	["Air Sight", 16, SkillTreeUi.COLUMN_WIDTH, "skill branch heading"],
	["Twin Flash", 16, SkillTreeUi.COLUMN_WIDTH, "skill branch heading"],
	# ability_hud.gd — the dial name under the dial, name_size 18, centred
	# across the AbilityHUD control's own 160 px width (main.tscn
	# offsets -176 / -16), no clip — so the control width IS the budget.
	["Air Rush", 18, 160.0, "ability dial name"],
	["Air Sight", 18, 160.0, "ability dial name"],
	["Phase Step", 18, 160.0, "ability dial name"],
	["Resize", 18, 160.0, "ability dial name"],
	["Stink Wave", 18, 160.0, "ability dial name"],
	# The card title is one non-wrapping line across the card less its inset.
	["%s — Level %d,  %d points", 22, SkillTreeUi.CARD_WIDTH - SkillTreeUi.CARD_INSET, "skill tree card title"],
	# minimap_hud.gd — the caption fragments (bead godot-test1-kox and godot-test1-8gw.13).
	# They are drawn under the disc, centred across the widget's own 202 px (MAP_CENTER.x * 2)
	# at TEXT_SIZE 15 (and BUDAPEST_TEXT_SIZE 13 for the third line) and do NOT clip.
	# The indoor fragments append to lines 1 and 2 (budget 80 px each).
	# The Budapest lines occupy their own non-wrapping third row across the 202 px widget (budget 190 px).
	["Floor %d", 15, 80.0, "minimap storey line"],
	["JAIL F%d", 15, 80.0, "minimap jail intent"],
	["NO LOCK", 15, 80.0, "minimap jail intent, jammed in the labyrinth"],
	["Budapest: %.1f km", 13, 190.0, "minimap Budapest countdown"],
	["Budapest %d/%d", 13, 190.0, "minimap Budapest explored count"],
	# event_log_hud.gd — the room log card is 360 px wide with CARD_PADDING 12
	# each side at BODY_FONT_SIZE 14, drawn with draw_string (no wrap, no
	# clip). Measured raw: the "%s" stands in for the name, exactly like the
	# "%d" in the MP volume row above.
	["%s joined", 14, 336.0, "event log line"],
	["%s left", 14, 336.0, "event log line"],
	["%s disconnected", 14, 336.0, "event log line"],
	["You left the room", 14, 336.0, "event log line"],
	["%s: mic on", 14, 336.0, "event log line"],
	["%s: mic off", 14, 336.0, "event log line"],
	["%s: camera on", 14, 336.0, "event log line"],
	["%s: camera off", 14, 336.0, "event log line"],
	["%s now plays %s", 14, 336.0, "event log line"],
	["%s was captured", 14, 336.0, "event log line"],
	["%s was freed", 14, 336.0, "event log line"],
	["Deafened", 14, 336.0, "event log line"],
	["Undeafened", 14, 336.0, "event log line"],
	# world_caption.gd — the lifetime-first stamp caption (bead godot-test1-wus8)
	# posts to LevelUpLabel, full-frame centred at size 40. No fixed control to
	# measure against, so the budget is the base viewport (project.godot's 1920)
	# less side margins — the line must never outgrow the frame it is centred
	# on. Measured raw like the minimap countdowns: each %d stands in for two
	# digits, %s for the one-key name. A spill on a narrow portrait phone is
	# shared with every other world caption (respawn, level-up — unbudgeted by
	# the same rule), so none of those buys an entry here either.
	["New passport stamp — %d of %d (press %s)", 40, 1820.0, "world stamp caption"],
]

var _failures: Array[String] = []


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	Sentinel.isolate_user_state()
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
		Sentinel.finish(self)
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
		Sentinel.done("translations")
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
	Sentinel.done("translations")


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
	Sentinel.done("fallback")


## THE ACCEPTANCE CRITERION, asserted mechanically: an already-built Control
## re-renders in the new language when the locale changes, with nothing acting
## on it.
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
	Sentinel.done("live_switch")


## The saved-language round trip, driven through `start_overlay.gd`'s own static
## functions — against a THROWAWAY config file, never the player's real
## `user://locale.cfg`. It used to snapshot the real file and put it back at the
## end, which left a developer's build stuck in German whenever the check died in
## between; redirecting the path is both shorter and safe however this run ends.
## Every assertion below is about state these lines arranged, so the machine's own
## saved choice cannot change the verdict either.
func _check_locale_config() -> void:
	var restore_locale: String = TranslationServer.get_locale()
	DirAccess.remove_absolute(StartOverlay.locale_config_path)

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

	DirAccess.remove_absolute(StartOverlay.locale_config_path)
	TranslationServer.set_locale(restore_locale)
	Sentinel.done("locale_config")


## Measure every budgeted German string in the real font at the real size. A
## multi-line label is judged on its widest line, which is what actually decides
## whether the control overflows.
func _check_widths(rows: Array) -> void:
	# THE RULER IS THE FACE WE DRAW WITH (bead godot-test1-y1o.24). It used to be
	# the engine default theme's Button font — right while every panel drew
	# in the engine default, and WRONG the moment one adopts `HudTheme.theme()`,
	# whose default font is Oswald. A budget measured on a font nobody draws with
	# passes vacuously in both directions: Oswald is CONDENSED, so it would hide a
	# real overflow if the panels were wider, and flag a fit that is fine if they
	# were narrower. One seam, so every per-panel bead after this one inherits it.
	# EVERY FACE A BUDGETED STRING COULD BE DRAWN IN, AND THE WIDEST ANSWER WINS.
	#
	# There are three, and picking any ONE of them is the vacuous-budget bug this
	# seam exists to stop:
	#
	#   * Oswald REGULAR — `HudTheme.theme()`'s default, so every `Label` on a
	#     panel that has adopted it;
	#   * Oswald BOLD — the theme's `Button` font, and 51 of the 94 rows below are
	#     on Button-class controls. Bold is ~9 points of budget wider than
	#     Regular, so a Regular-only ruler repeats the same mistake one weight on;
	#   * THE ENGINE DEFAULT — because 5 rows are drawn by something `theme()` can
	#     never reach: `minimap_hud` paints its labels with `draw_string`, where a
	#     `Theme` has nothing to say (bead y1o.27 restyles its chrome, not its
	#     face). The tightest budget in the whole table is one of
	#     those minimap rows, and it sits at 96.2% of its limit in the face it is
	#     really drawn in against 83.8% in Oswald — measuring it on Oswald alone
	#     would hand it 10 px of headroom that does not exist.
	#
	# Rather than classify 94 rows by their `where` string — which goes wrong in
	# silence the day a control changes class or a panel bead lands — every row is
	# held to whichever face is WIDEST. That is conservative by construction (a
	# string that fits the widest face fits the one it is actually drawn in), it
	# is never weaker than the pre-HudTheme gate, and it needs no edit as the nine
	# per-panel beads migrate their controls one at a time.
	var fonts: Array[Font] = []
	for f: Font in [HudTheme.body_font(), HudTheme.heading_font(),
			ThemeDB.get_default_theme().get_font("font", "Button")]:
		if f != null:
			fonts.append(f)
	if fonts.is_empty() and ThemeDB.fallback_font != null:
		fonts.append(ThemeDB.fallback_font)
	if fonts.is_empty():
		_fail("no font available — the width check would pass vacuously")
		Sentinel.done("widths")
		return
	var font: Font = fonts[0]
	# German needs ß and the umlauts, which is the whole reason Oswald was chosen
	# over Bebas Neue. `has_char`, NOT a width: a glyph the face is missing still
	# measures a non-zero advance (the notdef box), so a width test here would be
	# true of a tofu and would guard exactly nothing.
	# Asked of the SHIPPED faces only: the engine default is above as a ruler for
	# the rows nothing has migrated yet, not as a face this project chose.
	for glyph: String in ["ß", "ä", "ö", "ü", "Ä"]:
		for f: Font in [HudTheme.body_font(), HudTheme.heading_font()]:
			if f != null and not f.has_char(glyph.unicode_at(0)):
				_fail("the HUD font has no '%s' — the German budgets would be "
					% glyph + "measured on a notdef box")
	# Prove the ruler works before trusting any measurement it makes. A headless
	# build configured with the dummy text server measures everything as 0, which
	# would turn every assertion below into a silent pass.
	if font.get_string_size("MMMM", HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x <= 0.0:
		_fail("font measured a non-empty string as 0 wide — the width check would pass vacuously")
		Sentinel.done("widths")
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
				var width: float = 0.0
				for f: Font in fonts:
					width = maxf(width, f.get_string_size(
						line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
				if width > limit:
					_fail("%s: %s is %.1f px wide at font size %d, over the %.0f px budget"
						% [where, line.c_escape(), width, font_size, limit])
	Sentinel.done("widths")
