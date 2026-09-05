extends Control
## Game Over screen.
##
## Shown by the player (via the "game_over_ui" group) when the FULL-CUSTODY PROTOCOL
## is lost — the corporation held every hero and the recall clock ran out. Heroes are
## the lives (owner ruling 2026-08-31), so that is the only ending in the game; a
## re-entered archived world reopens this same panel.
## It dims the screen, reports the final coin tally, and offers a "Play Again"
## button that starts a fresh run. The whole UI is built in code in _ready() so
## main.tscn only needs to declare one node with this script attached — the same
## "set yourself up in code" approach the other HUD scripts use.
##
## Decoupling: the button finds the player through the "player" group and calls
## restart_game(); it never holds a hard reference, matching the rest of the
## project's group-based wiring.
##
## ---------------------------------------------------------------------------
## IT IS THE FILM'S TITLE CARD (bead godot-test1-y1o.31)
## ---------------------------------------------------------------------------
## The look comes off `HudTheme` and nothing here types a colour: an OPAQUE INK
## card (`HudTheme.card(true)` — the modal case) behind a 1 px BONE hairline,
## "GAME OVER" in Oswald Bold caps with the hard (2,2) shadow, the subtitle at
## ~40%, the tally as fine print, and the corporate cutlery stamp bottom-right.
## The one warm accent on the card is "NEW BEST!", which the spec reserves for
## the transient shouts.
##
## **THE TITLES ARE ALREADY CAPS IN `ui.csv` ("GAME OVER" / "SPIEL VORBEI",
## "VICTORY!" / "SIEG!"), so there is no `.to_upper()` anywhere in this file** —
## which is the safe end of the caps rule: the transform would run on a
## TRANSLATED string, and Godot's `to_upper()` leaves ß alone while the German
## table is free to grow one. The subtitle and the button keep their authored
## case for the same reason; the subtitle is prose, which the spec sets in
## sentence case regardless.
##
## THE WON OUTCOME IS THE SAME CARD WITH A DIFFERENT TITLE LINE, and that is a
## simplification the palette forces rather than one it merely allows: the
## retired red/gold pair spent the accent twice on a card that also shouts
## "NEW BEST!" in it. The two endings are told apart by the WORD and by the
## subtitle under it, in both languages.

## THE TITLE-CARD SIZE LADDER, and it is the panel's own. `HudTheme` carries a
## heading size (20) and a body size (14) for a PANEL; a full-screen ending card
## is a different scale entirely and the theme has no title size to read — named
## in the bead's PR as the gap it is. The three below are the spec's own ladder:
## the title, the subtitle at ~40% of it, and fine print under that.
const TITLE_FONT_SIZE: int = 72
const SUBTITLE_FONT_SIZE: int = 29
const FINE_FONT_SIZE: int = 24
## The transient shout ("NEW BEST!") — the comic SFX lettering, and the one amber
## thing on this card.
const SHOUT_FONT_SIZE: int = 40
const BUTTON_FONT_SIZE: int = 32

## How dark the world goes behind the card. The RGB is INK; this alpha is the
## panel's own and is exactly the dim this screen has always used — a title card
## is opaque, but the world around it is still only veiled.
const DIM_ALPHA: float = 0.65

## The labels we rewrite each time the screen appears.
var title_label: Label = null
var story_label: Label = null
## Coins is the HEADLINE score (bigger, above the all-time best).
var coins_label: Label = null
## All-time records line ("Best: NN coins") — the player persists these
## across sessions (user://best_run.cfg), we just display what it hands us.
var best_label: Label = null
## "NEW BEST!" flash, shown only when this run set a new coin record. Pulsed
## by a code-built Tween (no assets) each time the screen appears with a record.
var new_best_label: Label = null
var new_best_tween: Tween = null

## True while the shared IntroVideo lifecycle is covering the game-over state.
## The panel remains hidden for the duration; a false/off-web start falls back to
## showing the ordinary panel below.
var _ending_film_playing: bool = false


func _ready() -> void:
	add_to_group("game_over_ui")

	# Cover the whole screen and sit on top. STOP so clicks behind the panel don't
	# leak through to the game while the screen is up (the button still gets its
	# own clicks because it is a child control).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# The skin, adopted on THIS root and nowhere wider (see `HudTheme`): it is what
	# gives the Play Again button its INK_RAISED face, STEEL frame, amber hover and
	# Oswald lettering with no per-button override here.
	theme = HudTheme.theme()

	_build_ui()

	# Hidden until a run actually ends. `_trigger_game_over()` / `end_run()` is the
	# one thing that raises this screen.
	visible = false


func _build_ui() -> void:
	"""Construct the dim backdrop, the centred CARD, and its contents."""
	# Semi-transparent backdrop so the world reads as "stopped" behind the card.
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(HudTheme.INK, DIM_ALPHA)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	# Centre everything on screen.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# THE CARD. `card(true)` is the modal case — opaque INK, a 2 px STEEL frame,
	# the hard (2,2) shadow — and it hands out a FRESH box (documented in
	# `HudTheme`), so widening its padding here restyles nothing else. The TOP
	# margin goes to zero because the hairline below has to sit on the very edge.
	var card_box := HudTheme.card(true)
	card_box.set_content_margin_all(HudTheme.CARD_PADDING * 3)
	card_box.content_margin_top = 0
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", card_box)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", HudTheme.GRID * 3)
	card.add_child(vbox)

	# THE FILM'S LETTERBOX LINE: a 1 px BONE hairline across the top edge of the
	# modal card. `HudTheme` has no builder for it (its own note says the modal
	# card beads are its only consumers), so it is one ColorRect here — which is
	# also the only shape that reaches the card's actual edge, since a StyleBoxFlat
	# carries ONE border colour and this card's frame is STEEL.
	var hairline := ColorRect.new()
	hairline.color = HudTheme.BONE
	hairline.custom_minimum_size = Vector2(0.0, float(HudTheme.BORDER_PX))
	hairline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hairline)

	# Title (GAME OVER or VICTORY!) — the card's lettering, and the whole reason a
	# font ships. The shadow is INK_RAISED rather than INK: a shadow in the card's
	# OWN ground is an invisible shadow.
	title_label = Label.new()
	title_label.text = "GAME OVER"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", HudTheme.heading_font())
	title_label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title_label.add_theme_color_override("font_color", HudTheme.BONE)
	title_label.add_theme_color_override("font_outline_color", HudTheme.INK)
	# READ THE UNIT: `OUTLINE_PX` is 2 px OF INK and Godot grows a glyph in BOTH
	# directions, so this is the spec's 1-px card outline — `hero_hud`'s doubling
	# note, the other way round, because the world-side contract is 2 px a side.
	title_label.add_theme_constant_override("outline_size", HudTheme.OUTLINE_PX)
	title_label.add_theme_color_override("font_shadow_color", HudTheme.INK_RAISED)
	title_label.add_theme_constant_override("shadow_offset_x",
			HudTheme.SHADOW_PANEL_OFFSET.x)
	title_label.add_theme_constant_override("shadow_offset_y",
			HudTheme.SHADOW_PANEL_OFFSET.y)
	vbox.add_child(title_label)

	# Story subtitle line for the win outcome — the same face at ~40%, and prose,
	# so it stays sentence case.
	story_label = Label.new()
	story_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	story_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story_label.custom_minimum_size = Vector2(560.0, 0)
	story_label.add_theme_font_size_override("font_size", SUBTITLE_FONT_SIZE)
	story_label.visible = false
	vbox.add_child(story_label)

	# "NEW BEST!" record flash — hidden unless this run beat the all-time coin
	# record (see show_game_over). THE COMIC SFX SHOUT: Oswald Bold in the one
	# accent colour with a heavier ink outline, which is exactly what the spec
	# reserves the amber for. It is the only amber on this card.
	new_best_label = Label.new()
	new_best_label.text = "NEW BEST!"
	new_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	new_best_label.add_theme_font_override("font", HudTheme.heading_font())
	new_best_label.add_theme_font_size_override("font_size", SHOUT_FONT_SIZE)
	new_best_label.add_theme_color_override("font_color", HudTheme.VISOR_AMBER)
	new_best_label.add_theme_color_override("font_outline_color", HudTheme.INK)
	new_best_label.add_theme_constant_override("outline_size", HudTheme.OUTLINE_PX * 2)
	new_best_label.visible = false
	vbox.add_child(new_best_label)

	# Final coin tally (rewritten by show_game_over) — FINE PRINT on the card now,
	# not a second headline: the title is what this screen says, and the number is
	# still the run's score in the palette's own lettering.
	coins_label = Label.new()
	coins_label.text = "Coins collected: 0"
	coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coins_label.add_theme_font_size_override("font_size", FINE_FONT_SIZE)
	vbox.add_child(coins_label)

	# All-time records line (rewritten by show_game_over). Same size, UNIT_KHAKI:
	# it is context rather than this run's score, which is the corporation's own
	# neutral in this palette — hierarchy by colour rather than by a fourth size.
	best_label = Label.new()
	best_label.text = "Best: 0 coins"
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	best_label.add_theme_font_size_override("font_size", FINE_FONT_SIZE)
	best_label.add_theme_color_override("font_color", HudTheme.UNIT_KHAKI)
	vbox.add_child(best_label)

	# "Play Again" button, centred under the text. Face, frame, hover and font all
	# come from the Theme adopted on the root — only the SIZE is ours, because the
	# theme's is a panel's and this is a card.
	var button := Button.new()
	button.text = "Play Again"
	button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	button.custom_minimum_size = Vector2(300.0, 76.0)
	button.pressed.connect(_on_restart_pressed)

	var button_wrap := CenterContainer.new()
	button_wrap.add_child(button)
	vbox.add_child(button_wrap)

	# THE CORPORATE STAMP, bottom-right of a GastroDefense-voiced card.
	var stamp := CutleryStamp.new()
	stamp.size_flags_horizontal = Control.SIZE_SHRINK_END
	vbox.add_child(stamp)


class CutleryStamp:
	extends Control
	## The crossed fork and knife — GastroDefense's mark, small and UNIT_KHAKI in
	## the corner of any card that speaks in their voice.
	##
	## Drawn rather than shipped: it is six lines of `draw_line`, where a texture
	## would be an asset to import, an import file to gitignore and a second thing
	## to recolour the day the palette moves. An inner class because it needs a
	## `_draw`, and it carries its own numbers because an inner class cannot read
	## the outer script's consts.
	const STAMP_SIZE: float = 30.0
	const STROKE: float = 2.0

	func _init() -> void:
		custom_minimum_size = Vector2(STAMP_SIZE, STAMP_SIZE)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := STAMP_SIZE
		var c := HudTheme.UNIT_KHAKI
		# The knife: handle at bottom-left, a thicker blade toward the tip.
		draw_line(Vector2(0.10, 0.90) * s, Vector2(0.90, 0.10) * s, c, STROKE)
		draw_line(Vector2(0.60, 0.40) * s, Vector2(0.86, 0.14) * s, c, STROKE * 2.0)
		# The fork: handle at bottom-right, three tines off its head.
		draw_line(Vector2(0.90, 0.90) * s, Vector2(0.28, 0.28) * s, c, STROKE)
		for tine: Vector2 in [Vector2(0.10, 0.34), Vector2(0.20, 0.18),
				Vector2(0.36, 0.10)]:
			draw_line(Vector2(0.28, 0.28) * s, tine * s, c, STROKE)


func _unhandled_input(event: InputEvent) -> void:
	# Keyboard shortcut for "Play Again": Enter or Space (both are bound to the
	# built-in ui_accept action out of the box, so no project.godot change).
	# Only while the screen is actually up — otherwise this node must stay inert.
	if visible and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_on_restart_pressed()


func show_game_over(coins: int, best_coins: int, is_new_best: bool, outcome: int = 1) -> void:
	"""
	Reveal the ending screen:
	- For CAPTURED (outcome = 1): the "GAME OVER" title.
	- For WON (outcome = 2): the "VICTORY!" title with Budapest story text.
	Coins, all-time best coins, optional NEW BEST! pulse, and the web film.

	ONE CARD, TWO TITLE LINES: the outcome picks the words and the subtitle, never
	a colour — see the banner at the top of this file for why the retired red/gold
	pair could not survive the palette.
	"""
	var is_won := (outcome == 2)
	if title_label:
		title_label.text = tr("VICTORY!") if is_won else tr("GAME OVER")

	if story_label:
		if is_won:
			story_label.text = tr("The heroes vanished into Budapest and started a new life. Next adventure coming!")
			story_label.visible = true
		else:
			story_label.text = ""
			story_label.visible = false

	if coins_label:
		coins_label.text = tr("Coins collected: %d") % coins
	if best_label:
		best_label.text = tr("Best: %d coins") % best_coins
	if new_best_tween:
		new_best_tween.kill()
		new_best_tween = null
	if new_best_label:
		new_best_label.visible = is_new_best
		# Any previous pulse was already killed by _on_restart_pressed — the only
		# route between two game overs — so we can start fresh here.
		if is_new_best:
			new_best_label.pivot_offset = new_best_label.get_minimum_size() * 0.5
			new_best_tween = create_tween().set_loops()
			new_best_tween.tween_property(new_best_label, "scale",
					Vector2(1.15, 1.15), 0.4).set_trans(Tween.TRANS_SINE)
			new_best_tween.tween_property(new_best_label, "scale",
					Vector2.ONE, 0.4).set_trans(Tween.TRANS_SINE)
	# The ending film is the game-over / win screen on web. Start it through the
	# existing start overlay so IntroVideo.start() has one call site and its pause,
	# modal key handling and fail-open teardown are shared with the start card's PLAY press.
	visible = false
	var overlay := get_tree().get_first_node_in_group("start_overlay")
	if OS.has_feature("web") and overlay != null and overlay.has_method("play_film"):
		var video_url := IntroVideo.WIN_VIDEO_URL if is_won else IntroVideo.GAME_OVER_VIDEO_URL
		var started: Variant = overlay.play_film(
			video_url, Callable(self, "_on_ending_film_finished"))
		if bool(started):
			_ending_film_playing = true
			return

	# Desktop, headless, missing overlay and unreachable-CDN paths all preserve the
	# original panel fallback. There is no pause or delay added on these paths.
	_ending_film_playing = false
	visible = true


func show_win(coins: int, best_coins: int, is_new_best: bool) -> void:
	"""
	Reveal the VICTORY panel — `show_game_over` with the outcome already chosen.

	The one caller in the tree is `scripts/intro_selfcheck.gd`, which drives the
	win panel directly rather than staging a whole run to reach it; the game
	itself arrives here through `player_controller._end_run(Outcome.WON)`, which
	passes the outcome along the general path. `show_ending()` — a third spelling
	of the same call taking the outcome as an argument, i.e. `show_game_over` with
	a different name — was deleted in bead godot-test1-8gw.5 as the dead code it
	was.
	"""
	show_game_over(coins, best_coins, is_new_best, 2)


func hide_game_over() -> void:
	"""
	Take the screen down. Called by _on_restart_pressed below, and by the player
	when a mid-run multiplayer join revives a game-over run (see join_at).
	"""
	visible = false
	if _ending_film_playing:
		var overlay := get_tree().get_first_node_in_group("start_overlay")
		if overlay != null and overlay.has_method("cancel_film"):
			overlay.cancel_film()
		_ending_film_playing = false
	# Stop the "NEW BEST!" pulse — a looping tween must not keep ticking behind
	# a hidden screen for the whole next run.
	if new_best_tween:
		new_best_tween.kill()
		new_best_tween = null


func _on_ending_film_finished(_failed: bool) -> void:
	"""
	The film is over, however it ended — show this panel.

	**AND NOTHING ELSE.** This used to call `player.restart_game()` on a clean end,
	which reaches `BestRunStore.new_game()` and clears the `[world] archived` latch.
	On the boot path that is catastrophic and silent: an archived world reopens its
	ending at `_ready()`, so the film played itself and DESTROYED the archive with
	zero user input — the exact opposite of the contract the archive exists for
	("Continue reopens the ending; only Play Again mints a fresh world").

	So the film's end is a handoff to an interactive surface, never a decision. The
	one route to a fresh world is the button below, which is the player's press —
	and `_failed` no longer changes anything, because "the stream died" and "the
	film ended" want the same next screen.
	"""
	# Use the same cleanup path as the button. The shared film has already been
	# torn down by StartOverlay, so its cancellation guard is a no-op here, while
	# hide_game_over still kills any NEW BEST! tween.
	hide_game_over()
	visible = true


func _on_restart_pressed() -> void:
	"""Hide the screen and tell the player to start a fresh run."""
	hide_game_over()
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("restart_game"):
		player.restart_game()
