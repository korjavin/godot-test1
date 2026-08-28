extends Control
## ============================================================================
## START OVERLAY — the first thing a player sees, and the only place
## multiplayer is impossible to miss
## ============================================================================
## The problem it exists for, from the owner's playtest of the deployed build:
## *"opened the URL, game just starts, no idea multiplayer exists."* The MP
## button was there the whole time, 110 px wide in the bottom-left corner of a
## running game whose mouse had already been captured — functional, and in
## practice invisible. Two hidden steps (press ESC to free the cursor, then find
## a small button) is not a feature a first-time visitor discovers.
##
## So the game no longer starts on its own. It opens on one screen with two
## choices:
##
##     PLAY SOLO        — one press, and everything is exactly as it was
##     MULTIPLAYER      — one press, and the room list is open
##
## Solo stays **one action deep**: a returning player who never wants
## multiplayer presses one button (or Enter/Space) and is in the game. That is
## the whole tax, and it buys the other half of the audience an entry point they
## can actually find.
##
## ----------------------------------------------------------------------------
## Built in code, no assets — the project convention
## ----------------------------------------------------------------------------
## `touch_controls.gd`, `mobile_settings_panel.gd`, `game_over_ui.gd` and
## `mp_ui.gd` all build their entire UI in `_ready()` from bare `Control`s and a
## `StyleBoxFlat`, so `main.tscn` carries nothing but a `Control` with this
## script on it. This one does the same, and it borrows `mp_ui`'s `_make_button`
## rule wholesale — see `_make_button()` below for why FOCUS_NONE is load-bearing
## and not a style preference.
##
## ----------------------------------------------------------------------------
## It pauses the tree, and it is the reason the mouse is not captured yet
## ----------------------------------------------------------------------------
## Two things have to be true while this screen is up, and one pause gives both:
##
##   * the world must not run — crocodiles chase, coins spawn and the fauna timer
##     ticks the moment `main.tscn` loads, and a player reading a menu should not
##     be losing hearts behind it; and
##   * the player must not be *driven* — `player_controller` reads gameplay
##     through the global polled `Input` state and through `_input()`, neither of
##     which a `Control` on top suppresses, so Space (Play Solo's own shortcut)
##     would also jump.
##
## `process_mode` gates `_input` and `_physics_process` together, so pausing is
## the one-line fix for both — exactly the argument `mp_ui._set_panel_open()`
## makes for the MP panel, and the `_paused_by_us` claim bit here is the same one
## `pause_controller.gd`, `mobile_input.gd` and `mp_ui.gd` carry on each other:
## only ever release a pause WE took. The pause itself is refcounted by
## `PauseHub` (scripts/pause_hub.gd), so this node's claim survives — and keeps
## the world frozen — for as long as the menu and the film are up, whatever else
## opens or closes over the top of them.
##
## **Mouse capture is handed over rather than suppressed.** `player_controller`
## captures the mouse in its own `_ready()`, which runs *before* this node's
## (`Player` is an earlier child of `Main` than `HUD`), so this overlay simply
## releases it while the menu is up and captures it again on dismiss — meaning
## `player_controller.gd` needed **no edit at all**. Capturing at dismiss is
## strictly better than the old boot-time capture on desktop web, where a
## browser refuses pointer lock outside a user gesture: the button press IS the
## gesture, so the camera now works from the first frame of play instead of
## waiting for the click-to-capture fallback.
##
## ----------------------------------------------------------------------------
## ----------------------------------------------------------------------------
## It is also the game's language switcher (EN / DE)
## ----------------------------------------------------------------------------
## This screen is the one place every player passes through exactly once before
## play, with the cursor already free and the tree already paused — so it is where
## the language switch lives, rather than in a settings screen this game does not
## have.
##
## **Almost all of the localization is the ENGINE's, not this file's.** Every
## user-facing string in the project is keyed by its own English text in
## `assets/translations/ui.csv`, and Godot's `Control` auto-translation runs
## `Label.text` / `Button.text` through the `TranslationServer` at draw time —
## re-running it on `NOTIFICATION_TRANSLATION_CHANGED`, which
## `TranslationServer.set_locale()` broadcasts to the whole tree. So pressing DE
## re-renders every open label in German with **no rebuild, no reload and no
## per-screen re-apply hook**. See CLAUDE.md's "Localization" section.
##
## The startup language is likewise free: Godot seeds `TranslationServer` from
## `OS.get_locale()`, so a German browser is already in German before this node
## exists. `apply_saved_locale()` only applies an explicit OVERRIDE the player
## chose on a previous visit — and being a nice-to-have is why a missing or
## unreadable config file is silently ignored rather than reported (`user://` is
## IndexedDB-backed on web and is known to be flaky there; auto-detection is the
## load-bearing half).
##
## ----------------------------------------------------------------------------
## On a phone it waits its turn
## ----------------------------------------------------------------------------
## `touch_controls.gd` opens with a full-rect "tap to enable motion controls"
## overlay, and that tap is the ONE user gesture iOS grants
## `DeviceMotionEvent.requestPermission()` and the browser grants WebAudio. This
## Control is the last `HUD` child, so it draws above that overlay and would
## steal the tap — killing motion and all audio for the session. It therefore
## hides itself (and drops its pause) while `touch_controls.has_modal()`, the
## same three lines `mp_ui.gd` and `mobile_settings_panel.gd` run for the same
## reason. On a phone the order is: enable motion → choose Solo or Multiplayer.

# ============================================================================
# CONSTANTS — layout
# ============================================================================

## The centred card's minimum width — wide enough for the title, narrow enough to
## fit a portrait phone's short edge. Its HEIGHT is deliberately not a constant:
## the card sits in a `CenterContainer` and sizes to its own content, so a long
## game title that wraps to two lines grows the card instead of overflowing it.
const CARD_WIDTH: float = 420.0

## Buttons are past the ~44-48 pt minimum touch target, and PLAY SOLO is the
## taller of the two: it is the default action, and on a phone the difference in
## size is the fastest way to read which one that is.
const BUTTON_HEIGHT: float = 64.0

const TITLE_FONT_SIZE: int = 40
const BUTTON_FONT_SIZE: int = 24
const HINT_FONT_SIZE: int = 16

# ============================================================================
# CONSTANTS — language switcher
# ============================================================================

## Where an explicit language choice is remembered, in the same shape as
## `best_run.cfg` and `mobile_tuning.cfg`.
const LOCALE_CONFIG_PATH: String = "user://locale.cfg"
const LOCALE_CONFIG_SECTION: String = "locale"
const LOCALE_CONFIG_KEY: String = "code"

## The languages offered, as `[locale code, button label]`. The labels are
## deliberately NOT translated — "EN" and "DE" must read the same whichever
## language is currently active, or a player who cannot read the current one
## cannot find their way out of it.
const LOCALES: Array = [["en", "EN"], ["de", "DE"]]

## Font size of the small EN/DE pills, and their fixed size. Small on purpose:
## the two gameplay choices are the point of this screen, and on a correctly
## auto-detected locale nobody ever needs to touch these.
const LOCALE_BUTTON_FONT_SIZE: int = 16
const LOCALE_BUTTON_SIZE: Vector2 = Vector2(52.0, 36.0)

## Font colours marking which language is active. The inactive one is dimmed
## rather than disabled — a disabled Button greys its label to near-invisible,
## and this row has to stay readable to a player who is in the wrong language.
const LOCALE_ACTIVE_COLOR: Color = Color(1.0, 0.92, 0.6)
const LOCALE_INACTIVE_COLOR: Color = Color(0.62, 0.65, 0.72)

# ============================================================================
# STATE
# ============================================================================

## True once a choice has been made. From then on this node is inert forever —
## hidden, not processing, holding no pause. There is no way back to the menu by
## design: "Play Again" restarts in place and the MP panel is the way into a
## room, so a second visit to this screen would only be a way to lose the run.
var _dismissed: bool = false

## Whether the CURRENT tree pause is ours to release. See the header.
var _paused_by_us: bool = false

## True while the web intro film is on screen. This is NOT dismissal: the node
## still holds the pause and the free cursor, and the card is merely hidden behind
## the video — `_process` polls `_film_finished()` and runs the ordinary
## `_dismiss()` when the film ends or is skipped, so mouse capture and the audio
## unlock still happen exactly once and exactly where they always did. Never true
## off-web: `IntroVideo.start()` answers false there without touching
## `JavaScriptBridge`, the same desktop-safety shape `MobileSensors` uses.
var _intro_playing: bool = false

## Cached once — the touch-session probe can reach into JavaScriptBridge, so it
## is not re-evaluated per frame (the same caching `touch_controls.gd` does).
var _is_touch: bool = false

# --- Child node references (built in _ready, not from a .tscn) --------------

## Everything visible, in one child so the touch-modal yield is a single
## `visible` flip. The ROOT stays MOUSE_FILTER_IGNORE, so while this is hidden
## the overlay is completely transparent to input.
var _body: Control = null

## The EN/DE pills, keyed by locale code, so `_refresh_locale_buttons()` can
## re-tint them without a node lookup.
var _locale_buttons: Dictionary = {}


func _ready() -> void:
	# Must keep running under its own pause, like every other always-available
	# HUD piece (`mp_ui.gd`, `mobile_settings_panel.gd`, `MpManager`).
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Discoverable, so `build_version.gd` can ask whether this card is still up —
	# "no run has started yet" is one of its two safe points for an auto-reload.
	add_to_group("start_overlay")

	# The root spans the screen but is never a hit-test target itself; `_body`
	# below is the modal that actually swallows input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Before the UI is built, so the card is drawn in the chosen language from its
	# very first frame rather than flipping one frame later. (Every OTHER screen
	# in the game is fixed up for free by the engine's translation-changed
	# notification, so only this one needs the ordering.)
	apply_saved_locale()

	_is_touch = MobileSensors.is_touch_session()
	_build_ui()

	# Take the pause and the cursor now, before the first gameplay frame runs.
	_apply_pause(true)

	# Build the (hidden) intro <video> now so the browser buffers it while the
	# player reads this card and playback starts instantly on the press. A no-op
	# off-web, and nothing downstream depends on it having worked — `start()`
	# rebuilds if it is missing.
	IntroVideo.preload_element()


func _process(_delta: float) -> void:
	if _dismissed:
		return

	# The intro film owns the screen. Hold the pause and the free cursor exactly as
	# the menu did, keep the card hidden behind the video, and do nothing else
	# until the browser says the film ended or was skipped. This cannot wedge:
	# every failure path inside `IntroVideo` reports finished (see its header), and
	# off-web `is_finished()` is a constant true.
	if _intro_playing:
		_apply_pause(true)
		if _film_finished():
			_intro_playing = false
			# `_dismiss()` tears the film's element down before it releases the
			# pause — see the invariant note there. This branch therefore does not
			# have to trust the ANSWER: right or wrong, the element is gone in the
			# same step the world starts running.
			_dismiss()
		return

	# Yield the screen to TouchControls' full-rect overlays — see the header for
	# why stealing that one tap would cost the session its motion permission and
	# all of its audio. Re-evaluated every frame rather than latched at _ready:
	# the enable overlay is dismissed by a tap, and this must come back when it
	# does.
	var blocked: bool = _touch_modal_up()
	if _body != null:
		_body.visible = not blocked
	# HIDE, BUT KEEP THE PAUSE. The overlay that is actually up at this moment on
	# every phone is the first-run "tap to enable motion controls" one
	# (`touch_controls` shows it whenever motion is not yet enabled), so releasing
	# here meant `_ready()`'s pause lasted exactly one frame and the world ran live
	# — crocodiles closing on a spawn bubble only 25 m wide — while the player had
	# not yet chosen PLAY SOLO or MULTIPLAYER. That is the one thing this node
	# exists to prevent.
	#
	# Nothing is stranded behind the held pause: all three of `has_modal()`'s
	# overlays are PROCESS_MODE_ALWAYS and dismiss themselves, and the resume
	# overlay in particular can never be the blocker here — it is gated on
	# `mobile_input.paused_by_driver`, which is false while WE own the pause.
	_apply_pause(true)


## The film's two browser calls, each behind a one-line wrapper.
##
## They exist so `intro_selfcheck.gd` can drive the WEB branch of `_process()`
## above, which is the branch that shipped a bug nothing asserted: a headless
## Godot is off-web, where `IntroVideo.is_finished()` is a constant `true`, so
## without a seam the film cannot be held "still playing" for even one frame and
## "the world stays paused while the film is up" is untestable. The check's
## subclass overrides these two and nothing else does — every caller in this file
## goes through them.
func _film_finished() -> bool:
	return IntroVideo.is_finished()


func _film_teardown() -> void:
	IntroVideo.discard()


## True while the start CARD itself owns the screen — i.e. no run has begun and no
## film is playing. Read through the `start_overlay` group by `build_version.gd`,
## for which that is a safe moment to reload the tab: there is nothing in memory
## yet for a reload to destroy.
##
## `_dismissed` rather than `visible`, because the node stays visible-but-
## transparent while a touch modal is up, and it is one-way — this screen never
## comes back. And NOT `_intro_playing`: the film is 47 s during which this node is
## technically still undismissed, but a reload there throws the player back to the
## card and makes them press PLAY SOLO again, which is not "nothing to lose".
func is_showing() -> bool:
	return not _dismissed and not _intro_playing


## True while `touch_controls.gd` has one of its own full-rect overlays up.
## Null-safe group lookup with a `has_method` guard, like every other cross-node
## reach in this project.
func _touch_modal_up() -> bool:
	var touch_ui: Node = get_tree().get_first_node_in_group("touch_controls")
	return touch_ui != null and touch_ui.has_method("has_modal") and bool(touch_ui.has_modal())


# ============================================================================
# UI CONSTRUCTION
# ============================================================================

func _build_ui() -> void:
	_body = Control.new()
	_body.name = "Body"
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP, not IGNORE: this is a modal. It has to swallow every click, or the
	# desktop-web click-to-capture in `player_controller._input()` fires through
	# it and warps the cursor to screen centre while the menu is still up.
	_body.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_body)

	# Dim the running world behind the card rather than hiding it: the terrain,
	# the sky and the fog are the game's own best screenshot, and a solid splash
	# would only be one more thing to art-direct.
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.03, 0.05, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(dim)

	# A CenterContainer rather than centre anchors + hand-computed offsets: it
	# centres its child at the child's OWN minimum size, so the card grows to fit
	# whatever the title turns out to be instead of clipping it.
	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(centre)

	var card := PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.05, 0.06, 0.09, 0.94)
	card_style.set_corner_radius_all(14)
	card_style.set_content_margin_all(20)
	card.add_theme_stylebox_override("panel", card_style)
	centre.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.name = "Choices"
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)

	var title := Label.new()
	# Read from the project settings rather than hardcoded, so the game's name
	# lives in exactly one place and a rename never leaves the title screen
	# saying something else.
	title.text = String(ProjectSettings.get_setting("application/config/name", "")).to_upper()
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Run the road. Outrun the crocodiles."
	subtitle.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	var solo := _make_button("PLAY SOLO", _on_play_solo_pressed)
	# The default action, and the taller of the two so which one that is reads at
	# a glance rather than from the label.
	solo.custom_minimum_size = Vector2(0.0, BUTTON_HEIGHT + 8.0)
	solo.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE + 2)
	vbox.add_child(solo)

	vbox.add_child(_make_button("MULTIPLAYER", _on_multiplayer_pressed))

	var hint := Label.new()
	hint.text = "Multiplayer: play the same world with up to 4 friends"
	hint.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	vbox.add_child(_build_locale_row())


## The EN / DE pills, centred under the hint. One press sets the locale, saves it
## and re-tints the row; every visible label in the game re-translates itself,
## because that is what `TranslationServer.set_locale()` notifies the tree to do.
func _build_locale_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "Language"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	for entry: Array in LOCALES:
		var code: String = entry[0]
		var button := Button.new()
		button.text = entry[1]
		# FOCUS_NONE for the same reason every other button on this card has it —
		# see `_make_button()`. Space is `ui_accept` AND `jump`, and this card's
		# `ui_accept` handler starts the game, so a focused pill would re-fire on
		# the player's first jump.
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", LOCALE_BUTTON_FONT_SIZE)
		button.custom_minimum_size = LOCALE_BUTTON_SIZE
		button.pressed.connect(_on_locale_pressed.bind(code))
		row.add_child(button)
		_locale_buttons[code] = button
	_refresh_locale_buttons()
	return row


func _on_locale_pressed(code: String) -> void:
	save_locale(code)
	_refresh_locale_buttons()


## Tint the pill of the active language and dim the rest. `get_locale()` can be a
## full code like "de_DE" (that is what a German browser reports), so the match is
## on the LANGUAGE part — otherwise no pill would ever look active on the very
## locale auto-detection got right.
func _refresh_locale_buttons() -> void:
	var active: String = TranslationServer.get_locale().split("_")[0]
	for code: String in _locale_buttons:
		var button: Button = _locale_buttons[code]
		var colour: Color = LOCALE_ACTIVE_COLOR if code == active else LOCALE_INACTIVE_COLOR
		button.add_theme_color_override("font_color", colour)
		button.add_theme_color_override("font_hover_color", colour)
		button.add_theme_color_override("font_pressed_color", colour)


# ============================================================================
# LANGUAGE PERSISTENCE
#
# Static so they need no node — `_ready()` above applies the saved choice before
# it builds anything, and `scripts/locale_selfcheck.gd` drives the round trip
# headlessly without instancing a scene.
# ============================================================================

## Apply a language the player explicitly chose on an earlier visit, if any.
## Doing NOTHING is the correct behaviour for a missing/unreadable file or an
## unrecognised code: Godot has already seeded the locale from `OS.get_locale()`,
## which is the better default and the reason this is only a nice-to-have.
static func apply_saved_locale() -> void:
	var config := ConfigFile.new()
	if config.load(LOCALE_CONFIG_PATH) != OK:
		return
	var code: String = String(config.get_value(LOCALE_CONFIG_SECTION, LOCALE_CONFIG_KEY, ""))
	if code.is_empty() or not _is_known_locale(code):
		return
	TranslationServer.set_locale(code)


## Switch to `code` now and remember it for next time. The set happens first and
## unconditionally: a failed save costs the player the memory of their choice,
## never the choice itself.
static func save_locale(code: String) -> void:
	if not _is_known_locale(code):
		return
	TranslationServer.set_locale(code)
	var config := ConfigFile.new()
	config.set_value(LOCALE_CONFIG_SECTION, LOCALE_CONFIG_KEY, code)
	config.save(LOCALE_CONFIG_PATH)


## Guard on the way IN as well as out, so a corrupt or hand-edited config file
## cannot strand the game in a locale with no translations and no visible pill.
static func _is_known_locale(code: String) -> bool:
	for entry: Array in LOCALES:
		if String(entry[0]) == code:
			return true
	return false


## One full-width, thumb-sized button. FOCUS_NONE is copied from
## `mp_ui._make_button()` and carries the same warning: `ui_accept` is SPACE,
## SPACE is also `jump`, and Godot's `BaseButton` KEEPS the focus after a click.
## A focused button here would re-fire on the player's very first jump — and the
## first thing this one does is dismiss a menu, so the second press would land on
## whatever replaced it.
func _make_button(label: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	button.custom_minimum_size = Vector2(0.0, BUTTON_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(handler)
	return button


# ============================================================================
# CHOICES
# ============================================================================

## Enter / Space takes the default action, so a desktop player never has to reach
## for the mouse to start. Handled here rather than by focusing the button
## because focusing it is exactly the bug FOCUS_NONE exists to prevent (see
## `_make_button`) — this Control is PROCESS_MODE_ALWAYS, so it receives input
## under its own pause with nothing focused at all.
func _unhandled_input(event: InputEvent) -> void:
	# The touch-modal test is the same one `_process` uses to hide the body: while
	# one of `touch_controls`' full-rect overlays is up this card is INVISIBLE, and
	# without the test one Enter dismissed it anyway — permanently and unseen,
	# since `_dismissed` is one-way and there is no route back to this screen.
	# `_intro_playing` is in the same guard for a sharper reason than the others:
	# SPACE is `ui_accept` AND it is the film's skip key, so without it every skip
	# attempt would ALSO re-enter `_on_play_solo_pressed()` from Godot's side while
	# the film is still up.
	if _dismissed or _intro_playing or event == null or _touch_modal_up():
		return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_on_play_solo_pressed()


## Play the intro film first (web only), then start the game.
##
## Hooked HERE and deliberately not in `_dismiss()`: `_on_multiplayer_pressed()`
## dismisses too, but it opens a panel rather than starting a game, and a film in
## front of the room list would be nothing but a delay.
##
## The world stays paused behind the video for free — this node already holds the
## pause and does not release it until `_dismiss()` — so `player_controller.gd`
## needs no edit. `IntroVideo.start()` is false off-web and on every failure path
## it knows of, so desktop, the editor, and a web build whose CDN is unreachable
## all take the original one-line route unchanged.
func _on_play_solo_pressed() -> void:
	if _intro_playing:
		return
	if IntroVideo.start():
		_intro_playing = true
		# Hide the card but keep this node alive and processing: `_process` is what
		# notices the film finishing. (Not `_dismiss()` — that would hand the mouse
		# and the pause back with 47 seconds of film still to run.)
		if _body != null:
			_body.visible = false
		return
	_dismiss()


func _on_multiplayer_pressed() -> void:
	# The preloaded film is thrown away by `_dismiss()` below — this press opens a
	# panel rather than starting a game, so the film is never coming and a
	# still-buffering 20 MB source has no business surviving into the multiplayer
	# session. That teardown used to be an explicit call right here; it now lives
	# in `_dismiss()`, where EVERY exit from this screen passes it.
	#
	# NOT capturing the mouse: the panel is about to open and wants the cursor.
	# On web `Input.set_mouse_mode(CAPTURED)` only REQUESTS pointer lock — the
	# browser grants it on a later task — so `mp_ui._apply_pause()`'s
	# `mouse_mode == MOUSE_MODE_CAPTURED` test would read VISIBLE, decline to
	# release it, and the lock would then land with the panel open: cursor warped
	# to screen centre, Join/Copy/Leave/Close unreachable. Exactly the failure the
	# panel's pause exists to prevent.
	_dismiss(false)
	# Open the MP panel through the group, no hard reference — the same discovery
	# rule the rest of the HUD follows. `_dismiss()` released our pause and the
	# panel takes its own synchronously inside `open_panel()`, so the world is
	# never unpaused for even one frame in between.
	var panel: Node = get_tree().get_first_node_in_group("mp_ui")
	if panel != null and panel.has_method("open_panel"):
		panel.open_panel()


## Stand down for good: hide, stop processing, release the pause, hand the mouse
## back to the game.
func _dismiss(capture_mouse: bool = true) -> void:
	if _dismissed:
		return
	_dismissed = true
	if _body != null:
		_body.visible = false
	visible = false
	set_process(false)
	set_process_unhandled_input(false)

	# THE INVARIANT: the world must never run while the film's element is on
	# screen. This is the single place the pause is handed back, so it is the
	# single place the film has to be taken down, and the two must happen in this
	# order and in the same step. Every ending routes through here — the film
	# ending or being skipped, MULTIPLAYER's "never coming", and above all a
	# `_film_finished()` that answered true for a reason the browser could not
	# report.
	#
	# `IntroVideo.is_finished()` is deliberately FAIL-OPEN (its header: "the only
	# thing worse than losing the intro is not being able to start the game"), and
	# that is right — a dead CDN must never block play. But before this line the
	# generosity cost a life instead of a film: a bogus "finished" released the
	# pause and captured the mouse while the <video> still covered the canvas, so
	# the player watched 47 s of film with a live world and a live crocodile behind
	# it. Tearing down here rather than trusting the answer is what makes fail-open
	# safe DURING playback too — a wrong answer can now only ever cost the film.
	# Idempotent and a no-op off-web, so the desktop path is unchanged.
	_film_teardown()
	_apply_pause(false)

	# A button press is a real user gesture, which is exactly what browsers
	# require for both of the things below — and the whole reason doing them HERE
	# is better than at boot.
	#
	# 1. Audio. `sound_manager` gates every `play_*` behind `unlock_audio()` and
	#    normally unlocks on its own `_input()` — which does not run while the
	#    tree is paused, so this press would otherwise not count and the first
	#    sound would wait for the next key or click in play.
	var sound: Node = get_tree().get_first_node_in_group("sound_manager")
	if sound != null and sound.has_method("unlock_audio"):
		sound.unlock_audio()

	# 2. Pointer lock. After the intro film this can arrive one browser task too
	#    late to still count as a gesture (the press was 47 s ago), in which case
	#    the request is simply declined and the existing desktop-web
	#    click-to-capture fallback in `player_controller._input()` — the one
	#    `capture_hint.gd` exists to advertise — picks it up on the first click,
	#    exactly as it did before this screen existed.
	#    Skipped on a touch session for the same reason
	#    `player_controller._ready()` skips it: there is no mouse to capture and
	#    the request would pop a useless prompt over the touch controls.
	if capture_mouse and not _is_touch:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Take or release the pause for the overlay's current state, and hand the mouse
## across with it. Mirrors `mp_ui._apply_pause()`, including the "only ever
## release OUR pause" guard.
func _apply_pause(active: bool) -> void:
	if not active and not _paused_by_us:
		return
	if active:
		# Taken once and HELD — through the menu, through the whole intro film,
		# and handed to `_dismiss()`. `_apply_pause(true)` is re-asserted every
		# frame from `_process` (see the callers), so the claim guard is what keeps
		# that to one dictionary write; `PauseHub.take()` would be idempotent
		# anyway.
		if not _paused_by_us:
			PauseHub.take(self)
			_paused_by_us = true
		# Free the cursor so the buttons are clickable. Unconditional — unlike
		# `mp_ui`, this node has no handover to remember: `_dismiss()` always
		# captures (on a non-touch session), whichever button was pressed.
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		_paused_by_us = false
		PauseHub.release(self)
