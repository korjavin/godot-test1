extends Control
## Landmark toast — the educational half of the geo-landmark feature, plus the
## FIRST-VISIT TREASURE that pays for the detour.
##
## Walk within a few metres of Stonehenge, the Pyramids of Giza or the Eiffel
## Tower and a small card slides up at the bottom of the screen naming the place
## and giving one real fact about it. That card IS the reward for detouring to a
## landmark (the coin ring round the base is a garnish — see the REWARD DECISION
## in endless_terrain.gd's GEO LANDMARKS constant banner).
##
## THE FIRST APPROACH TO EACH LANDMARK IN A RUN ASKS YOU TO NAME IT, and the
## coin burst is what a right answer pays — see the QUIZ and TREASURE sections
## below. The ring round the base is the lure you can see from across the field;
## the burst is the payoff for actually walking over AND knowing the place.
##
## THE QUIZ, in one paragraph.
##   * WHY IT GATES THE TREASURE rather than sitting beside it: the burst is the
##     only thing this card pays, so hanging the question on it is the only way an
##     answer can matter at all. A wrong answer still reveals the name and the
##     fact — the education is not the prize, it is the point — it just does not
##     pay.
##   * WHY IT PAUSES THE WORLD WHILE THE QUESTION IS UP — and why it used not to.
##     OWNER RULING, 2026-08-28, verbatim: "when quizz shown, game should be
##     paused, as player need time to read/answer, after this game unpauses
##     automatically." This card was built to run live and the argument for that
##     was real: it is a HUD toast, not a panel; the landmark footprint is already
##     a crocodile-free pocket by construction, and 1/2/3 collide with no movement
##     key, so you CAN answer while walking. What the ruling settles is that being
##     ABLE to answer while running is not the same as having time to read three
##     place names — a question you guess at is the opposite of the point of
##     having one. So a pending question now takes `get_tree().paused` and its
##     resolution (a digit, a tap, or QUIZ_TIMEOUT) gives it straight back.
##     The two things the old argument was right about survive the reversal
##     intact, and both live in the PAUSE banner below `_answer`: the MULTIPLAYER
##     one — `get_tree().paused` is local and the simulation is not, so in a room
##     the pause is skipped outright rather than inflicted on three other people —
##     and the INPUT one, now sharper than before: the digits must answer under
##     OUR pause and stay dead under anyone else's.
##   * WHY "ONCE PER RUN" IS FREE: `_visited` is marked at ARRIVAL, exactly as the
##     treasure always marked it, so walking away from an unanswered question and
##     coming back shows the plain card. There is no second latch and no way to
##     re-roll a question you got wrong.
##   * THE TIMEOUT (QUIZ_TIMEOUT) resolves the card as wrong with its own verdict.
##     It exists because leaving range does NOT cancel a pending quiz: the card
##     has to end somehow, and a card that ended when you walked out would be a
##     quiz you could refuse for free. A marker freed under a pending question
##     (its chunk streamed out) resolves the same way immediately — which is why
##     the name and fact are COPIED at ask time, not read back off the node.
##   * THE OPTION ROWS ARE TWO CONTROLS EACH, a digit badge and a button holding
##     the raw registry name, never one composed "1. Stonehenge" string — see the
##     localization rule below, which is the whole reason for the split.
##
## ponytail: IN A ROOM, where the pause is deliberately skipped, a player who
## walks away from a pending question burns the remaining
## QUIZ_TIMEOUT seconds of card before the toast is free to announce anything
## else — up to 12 s of screen spent on a question nobody is reading. Solo, the
## pause makes walking away impossible, so this is now a multiplayer-only
## ceiling rather than the general case it was written for. Cancelling
## on departure was the alternative and is worse (a free refusal), and a shorter
## timeout punishes the player who is genuinely thinking. Upgrade path, if it ever
## reads as dead card: resolve as timeout the moment the player passes radius +
## LEAVE_PAD *and* the question has been up for more than a second or two. The
## natural sequel — a SECOND fact revealed only on a right answer — is parked for
## the same kind of reason: 38 more en+de CSV rows for marginal value, so the
## existing fact is the reveal for both outcomes.
##
## Built entirely in code in _ready(), like touch_controls.gd and
## mobile_settings_panel.gd, so scenes/main.tscn needs exactly ONE node and one
## script line — this project ships a web build and every extra .tscn is another
## resource to import, parse and keep in step with a script that already knows the
## whole layout.
##
## DISCOVERY IS GROUP-BASED, with no hard references anywhere, exactly like the
## rest of this codebase (CLAUDE.md "Node discovery is group-based, not
## reference-based"):
##   * the player comes from the "player" group — which by the multiplayer
##     isolation contract means the LOCAL player and nothing else, so a remote
##     peer's avatar can never pop somebody else's card on our screen;
##   * landmarks come from the "landmark" group, which their marker Node3D joins
##     in spawn_landmark_in_chunk. Those markers are parented to the chunk mesh,
##     so they are freed with the chunk and this script needs no registry, no
##     bookkeeping and nothing to leak.
## Both are re-fetched every tick and both are allowed to be absent, so this
## control runs (blank, costing one group lookup a quarter second) in any scene
## that has neither.
##
## ⚠ LOCALIZATION IS FREE HERE AND MUST STAY FREE — DO NOT ADD tr().
## The registry's `name` and `fact` are the ENGLISH SOURCE STRINGS, and in this
## project the translation KEY *is* the English source string (CLAUDE.md
## Localization RULE 1). Every Control runs its own `text` through the
## TranslationServer at draw time and re-runs it on
## NOTIFICATION_TRANSLATION_CHANGED, which TranslationServer.set_locale()
## broadcasts to the whole tree. So assigning the raw string to Label.text gives
## translation AND live locale-switching with zero code — and gives readable
## English as the automatic fallback for a place whose CSV row somebody forgot.
## RULE 2 (tr() on the format string) applies only to text COMPOSED at runtime;
## nothing here is composed, so wrapping these in tr() would buy nothing and a
## later "fix" that composes "Name — fact" into one label would silently break
## both languages.
##
## ponytail: a locale switch WHILE a card is up re-renders both labels live (that
## is RULE 1 doing its job — NOTIFICATION_TRANSLATION_CHANGED reaches them like
## any other Control) but does NOT extend the card's remaining display time, so a
## player who switches language with one second left gets one second of German.
## Purely cosmetic, and the alternative — listening for the notification here just
## to top _hold back up — is more moving parts than the case is worth. Upgrade
## path: override _notification(NOTIFICATION_TRANSLATION_CHANGED) and reset _hold
## to TOAST_DURATION while visible.
##
## PERFORMANCE SHAPE (this is a web-build feature, so it is the design)
##   * The proximity scan runs on a throttled TICK_INTERVAL tick, NEVER per frame
##     — the same discipline as minimap_hud.gd's 5 Hz tick and
##     crocodile_lod_manager.gd's 9 Hz scan.
##   * The scan walks the "landmark" group, which holds typically 0-3 nodes:
##     landmarks are ~1 per 40-60 chunks and only 49 (web) to 121 (desktop) chunks
##     are ever active. That is why the nearest-in-range search is a plain linear
##     walk with no spatial index — an index over three items costs more than it
##     saves.
##   * A hidden card is `visible = false`, so it is not laid out and not drawn.

# ============================================================================
# CONFIGURATION
# ============================================================================

## Seconds between proximity scans. 4 Hz: a player crosses at most ~2.7 m between
## ticks at Windman's air-rush speed, which is far inside the APPROACH_PAD below,
## so no landmark can be missed by flying past one.
const TICK_INTERVAL: float = 0.25

## Metres added to the landmark's OWN radius to get the trigger distance. Deriving
## it from the marker's radius (rather than using one flat distance) is what makes
## a 9.4 m Pyramids of Giza and a 5.4 m Statue of Liberty both fire where they
## look like they should — roughly 12-15 m out, i.e. close enough that you are
## clearly visiting the thing rather than walking past its postcode.
const APPROACH_PAD: float = 6.0

## Metres beyond the landmark's radius at which the card RE-ARMS. Strictly greater
## than APPROACH_PAD, which makes it a dead-band: standing exactly on the trigger
## boundary cannot flicker the card on and off, the same hysteresis discipline
## crocodile_lod_manager.gd uses for its sleep/wake radii (45 in, 50 out).
const LEAVE_PAD: float = 14.0

## Seconds the card holds before it starts fading out. Long enough to read two
## lines without being long enough to sit over the game. Note the hold counts down
## THROUGH the fade-in rather than starting after it, so the card is on screen for
## TOAST_DURATION + FADE_DURATION (6.5 s) in total and fully opaque for about
## TOAST_DURATION - FADE_DURATION — near enough for a read-it-and-move-on card, and
## a phase that started the hold only once opaque would be two states, not one.
const TOAST_DURATION: float = 6.0

## Seconds the card takes to fade in and to fade out, via modulate.a.
const FADE_DURATION: float = 0.5

## Card colours. Translucent dark backing so the world reads through it — no
## texture assets, in keeping with the rest of this HUD.
const PANEL_COLOR := Color(0.05, 0.06, 0.09, 0.78)
const PANEL_BORDER := Color(1.0, 0.87, 0.55, 0.55)
const NAME_COLOR := Color(1.0, 0.93, 0.72, 1.0)
const FACT_COLOR := Color(0.92, 0.94, 0.97, 1.0)

const NAME_FONT_SIZE: int = 28
const FACT_FONT_SIZE: int = 18
const TREASURE_FONT_SIZE: int = 20
const TREASURE_COLOR := Color(1.0, 0.85, 0.35, 1.0)


# ============================================================================
# TREASURE CONFIGURATION — the first-visit coin burst
# ============================================================================
#
# WHY IT LIVES BESIDE THE APPROACH LATCH. The moment a landmark "opens" is
# exactly the moment its card fires, and this script already owns that moment,
# already knows which marker it was, and already runs a throttled tick. Putting
# the trigger anywhere else would mean a second proximity scan measuring the
# same distances against the same group.
#
# BUT IT IS A SEPARATE LATCH, and the difference is the whole design: `_active`
# is per-APPROACH memory that deliberately re-arms (walk away from Stonehenge
# and back and the card shows again — the card is the reward for the detour),
# while `_visited` is per-RUN memory that NEVER re-arms. A landmark pays exactly
# once per run; the card is what you can have as often as you like.
#
# HOW THE REWARD IS PAID — the treasure_chest.gd mechanism, verbatim, and for
# the same mechanical reason. The burst does NOT call collect_coin(N) once and
# does NOT spawn coin nodes: the coin economy counts PICKUPS, not value, so the
# streak multiplier steps every STREAK_COINS_PER_STEP *pickups* and a single fat
# collect_coin(20) would be one link in the chain and never light the streak up
# at all. `_award_one()` is called TREASURE amount times, spread over
# TREASURE_BURST_DURATION — comfortably inside the 2.5 s STREAK_WINDOW, so the
# whole burst is one unbroken chain — and the extra-life threshold, the HUD, the
# play_coin blip and the lifetime-coin credit for meta-progression all come free
# off the existing collect_coin path (progression takes the PRE-streak value, so
# a 20-coin burst credits 20 lifetime coins whatever the multiplier).
#
# DELIBERATELY NO GEM. The guaranteed gem is the ARTIFACTS' distinction (camps
# and chests were held to the same rule); a fourth source would flatten "an
# ancient prize worth a detour" into "another thing I walked past".
#
# MULTIPLAYER: THE TREASURE IS PERSONAL, WITH NO CLAIM ARBITRATION, ON PURPOSE.
# Visiting a landmark is an individual act — the card is already local and
# per-player by the isolation contract (the "player" group is the LOCAL player
# and nothing else) — so every member of a room gets their own first-visit burst
# for the same landmark, and there is deliberately no `claim_pickup` round trip
# the way treasure_chest.gd has one. A chest is ONE physical box that two peers
# race for, so paying both would pay the room twice for one object; a visit is
# not an object and cannot be raced for. The shared bank still receives it
# through the ordinary mechanics: collect_coin raises `own_coins`, which the
# presence packet already carries as this peer's contribution.
#
# ponytail: THE CEILING THAT LEAVES, stated plainly — in a room the burst does
# not advance the ROOM's streak. The master owns `_room_streak` and only
# `_resolve_claim()` advances it, so a treasure's 15-25 pickups are paid at
# whatever multiplier the room currently shows without building it further,
# while solo the same burst reliably steps the multiplier a rank. It is the same
# ceiling Adrenaline records for the same reason (a claim's pickup COUNT is not
# recoverable from a confirm), and it is the price of the personal-treasure
# decision above: making the room's streak move would need this to be claimed,
# and a claimed landmark has exactly one winner — which is the thing the design
# rules out. It is never WRONG, only less generous. Upgrade path, if it ever
# matters: a room verb that reports N pickups without arbitrating a winner,
# which is a wire-format change and belongs with the Adrenaline one.

## Coins paid by one landmark's first visit, drawn from that landmark's OWN
## deterministic roll (see `_claim_treasure`). Sized ABOVE a treasure chest's
## 8-15 so that walking 22 m off the road to a landmark beats brushing past a
## chest on it — the detour has to be worth more than the snack.
const TREASURE_COINS_MIN: int = 15
const TREASURE_COINS_MAX: int = 25

## Seconds the burst is spread over. Must stay well under player_controller's
## STREAK_WINDOW (2.5 s) or the shower breaks into two streak chains.
const TREASURE_BURST_DURATION: float = 1.2

## Fixed salt for the treasure's hash stream, in the ARTIFACT_SALT / CAMP_SALT /
## CHEST_SALT family: an arbitrary fixed constant that keeps the amount roll
## independent of every other deterministic site, so it can never correlate with
## (or perturb) one. It draws from no shared RandomNumberGenerator at all.
const TREASURE_SALT: int = 0x7EA5

## coin.gd is preloaded ONLY for its static `id_at()` — the project's one
## "identify a deterministic world thing by where it stands" helper, which is
## exactly what a landmark needs (its marker never moves, so the id is stable by
## construction — unlike a coin, whose id had to be latched against its bob).
## Reusing it is also why nothing had to be threaded out of endless_terrain.gd.
const COIN_SCRIPT := preload("res://scripts/coin.gd")


# ============================================================================
# QUIZ CONFIGURATION — the question that gates the treasure
# ============================================================================

## Seconds a question stays askable before it resolves itself as wrong. Sized
## above TOAST_DURATION on purpose: the plain card is a thing you read, this one
## is a thing you answer, and 12 s is long enough to read three names while still
## running from something.
##
## IT IS NOW ALSO THE SOFTLOCK BACKSTOP, and that is the more important of its two
## jobs. With the world paused for the card, "the player walked out of range" is no
## longer even a way for a question to end (solo, the player cannot walk anywhere),
## so this is the ONLY thing that guarantees the pause lifts for someone who never
## presses a key — AFK, or a controller the number row is not reaching. It is
## deliberately NOT lengthened for the paused reader: 12 s frozen in front of three
## names, with nothing chasing you and nothing to react to, is already more
## generous than the running case it was sized for. Whatever else is retuned here
## it must stay finite, and `_update_quiz` must stay wired into `_process` — see
## the PAUSE banner for why this node keeps processing while the tree does not.
const QUIZ_TIMEOUT: float = 12.0

## How many options a card offers. Not a tunable — `LandmarkBuilders.quiz_options`
## returns exactly three and ANSWER_KEYCODES has exactly three rows; the constant
## exists so the places that loop over them say the same thing.
const OPTION_COUNT: int = 3

## THE CARD'S FOUR STRINGS, held as constants because two files read them: this
## one writes them, and landmark_selfcheck.gd asserts every one has a German row
## (they are CSV KEYS — see the localization rule at the top of the file). Held
## here rather than duplicated there so the pair cannot drift.
##
## QUIZ_CORRECT is the only COMPOSED one, hence the only tr() in this file:
## Localization RULE 2, tr() on the FORMAT string, never on the result. The other
## three go straight onto Label.text under RULE 1 and translate themselves.
const QUIZ_PROMPT: String = "Which landmark is this?"
const QUIZ_CORRECT: String = "Correct! +%d coins"
const QUIZ_WRONG: String = "Not quite!"
const QUIZ_TIMEOUT_VERDICT: String = "Time's up!"

## Keys that answer slot 0, 1 and 2. RAW KEYCODES, outside project.godot's input
## map, for exactly the reason minimap_hud.gd's M and +/- are raw: a named action
## is for rebindable GAMEPLAY input, and a key that only answers a HUD card has
## nothing to rebind against. Both the number row and the numpad are accepted,
## the same pair minimap_hud.gd accepts for its zoom.
##
## help_selfcheck.gd reads this array to prove the help card's "1 2 3" row still
## names the keys that actually answer.
const ANSWER_KEYCODES: Array = [
	[KEY_1, KEY_KP_1],
	[KEY_2, KEY_KP_2],
	[KEY_3, KEY_KP_3],
]

const OPTION_FONT_SIZE: int = 20
const BADGE_COLOR := Color(1.0, 0.85, 0.35, 1.0)

# ============================================================================
# STATE
# ============================================================================

## The two labels, built in _ready(). Held as members because the tick writes
## them; nothing outside this script ever touches them.
var name_label: Label = null
var fact_label: Label = null

## The "+N coins" line, shown only on the approach that actually paid. Hidden the
## rest of the time, so a re-visit's card is visibly the plain educational card.
var treasure_label: Label = null

## The landmark whose card this approach belongs to, or null when re-armed. This
## single reference IS the "once per approach" rule: a card is shown when the
## nearest in-range marker is not this one, and this is cleared once the player is
## past radius + LEAVE_PAD (or the marker's chunk unloaded under it).
##
## ponytail: this is per-APPROACH memory, NOT per-run memory — there is
## deliberately no "you have already seen this one" set. Walk away from Stonehenge
## and back and the card shows again, because the card IS the reward for the
## detour and suppressing it would punish returning to a landmark you liked. It
## also means a landmark whose chunk streamed out and back re-announces itself,
## which is the same behaviour and costs nothing to allow. What does NOT re-arm is
## the QUESTION: `_visited` below is keyed on the PLACE, so a re-approach shows
## the plain card — no second ask, and nothing to farm.
var _active: Node3D = null

## Seconds of full visibility left before the fade-out starts. > 0 means "fade
## toward opaque", <= 0 means "fade toward transparent".
var _hold: float = 0.0

## Throttle accumulator for the proximity scan.
var _tick_timer: float = 0.0

## THE TREASURE LATCH — landmark id (COIN_SCRIPT.id_at of the marker's world
## position) -> true, for every landmark this run has already paid out. Unlike
## `_active` it NEVER re-arms: leaving and coming back re-shows the card and pays
## nothing. Keyed on the PLACE rather than on the node, so a landmark whose chunk
## streamed out and back is still remembered as visited.
var _visited: Dictionary = {}

## The run the `_visited` set belongs to. `endless_terrain.run_seed` IS the run
## identity — new_run() re-rolls it, and restart_game() goes through new_run() —
## so watching it clears the set on a restart and on a multiplayer room's shared
## world arriving, while a RESPAWN (which touches nothing about the world) leaves
## it standing, which is exactly the rule the design asks for. Reading the seed
## the terrain already publishes needs no new API and no signal to subscribe to.
##
## ponytail: a new_run that happened to re-roll the identical seed would keep the
## old visited set (1 in 2^32, and the world would be identical anyway, so the
## landmarks in it are the ones you already emptied). Upgrade path if that ever
## matters: a monotonically increasing run counter on the terrain.
var _visited_run_seed: int = 0

## The three option rows and the buttons inside them, built once in _ready() and
## hidden whenever no question is pending. Held as members for the same reason the
## labels are: the ask and the reveal write them, nothing outside does.
var _option_rows: Array[HBoxContainer] = []
var _option_buttons: Array[Button] = []

## QUIZ STATE. `_quiz_pending` is the whole state machine: true between the ask
## and the resolution, and the one thing `_scan`, `_update_fade` and
## `_unhandled_input` all gate on.
##
## The name, the fact and the landmark id are COPIED at ask time rather than read
## back off `_quiz_marker`, because the marker frees with its chunk and a player
## who runs off mid-question must still get a reveal that names the place (and,
## on a right answer, the amount that place was always going to pay). That is also
## why `_quiz_marker` is kept at all: only to notice it went away.
var _quiz_pending: bool = false
var _quiz_marker: Node3D = null
var _quiz_correct_slot: int = -1
var _quiz_id: int = 0
var _quiz_name: String = ""
var _quiz_fact: String = ""
var _quiz_timer: float = 0.0

## Whether the tree's pause is OURS — the shared guard every pauser in this
## project carries (pause_controller.gd, mp_ui.gd, skill_tree_ui.gd,
## start_overlay.gd, mobile_input.gd), for the shared reason: only ever release a
## pause you took. It is read in two places, and the second is the one that is
## easy to miss — `_unhandled_input`, where it is what tells OUR pause (digits
## must work: being frozen to answer is the whole point) from anybody else's
## (digits must not, or closing a panel with the number row answers blind).
var _paused_by_us: bool = false

## Whether the app has lost focus (tab switched, phone backgrounded) since it last
## had it. Only ever read by `_update_quiz`; see `_notification` for why it exists.
var _unfocused: bool = false

## Burst state, the treasure_chest.gd shape: how many single-coin awards are
## still owed, the gap between them, and the countdown to the next one.
var _burst_remaining: int = 0
var _burst_interval: float = 0.0
var _burst_timer: float = 0.0


func _ready() -> void:
	# The card must never eat a click: the MP panel, the touch buttons and the
	# start overlay all live in this same CanvasLayer, and a full-width Control
	# swallowing input over them would be invisible and maddening.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	modulate.a = 0.0

	# Backing panel. A PanelContainer + StyleBoxFlat is the cheapest rounded,
	# translucent card Godot has that needs no texture.
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	name_label = Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", NAME_COLOR)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	name_label.add_theme_constant_override("outline_size", 6)
	name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	box.add_child(name_label)

	fact_label = Label.new()
	fact_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# The facts are one sentence and German runs ~30% longer, so the fact line
	# wraps rather than clipping — which is also why this card needs no
	# WIDTH_BUDGETS entry in locale_selfcheck.gd (that file measures FIXED-width
	# controls; an autowrapping label inside a container that grows is exempt by
	# construction, exactly like the start-overlay and game-over labels).
	fact_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fact_label.add_theme_color_override("font_color", FACT_COLOR)
	fact_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	fact_label.add_theme_constant_override("outline_size", 5)
	fact_label.add_theme_font_size_override("font_size", FACT_FONT_SIZE)
	box.add_child(fact_label)

	# The treasure line. Same "no tr() needed" rule does NOT apply here — this one
	# is COMPOSED at runtime (a count formatted into a sentence), so it is
	# Localization RULE 2: tr() on the FORMAT STRING, never on the result. See
	# _show(). It autowraps inside the same growing container as the fact line, so
	# it needs no locale_selfcheck.gd WIDTH_BUDGETS row either.
	# THE THREE OPTION ROWS, built once and hidden until a question is asked.
	#
	# A row is a digit badge Label plus a Button carrying the NAME, and the split
	# is load-bearing: the name is a raw registry string that Godot translates by
	# itself (RULE 1 at the top of the file), so composing "1. Stonehenge" into
	# one control would hand the TranslationServer a key that is in no table and
	# silently lose German for every landmark name. The Button is the tap target
	# (tap == hotkey, on desktop too); the badge is decoration.
	#
	# FOCUS_NONE matters more than it looks: a focused Button eats Space, and
	# Space is the jump key.
	#
	# The names are short and the card is 640 px wide, so like the fact line these
	# need no locale_selfcheck.gd WIDTH_BUDGETS row — the row grows with its
	# container and nothing here has a fixed width to overflow.
	for slot: int in OPTION_COUNT:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 10)
		row.visible = false
		box.add_child(row)

		var badge := Label.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.text = str(slot + 1)
		badge.add_theme_color_override("font_color", BADGE_COLOR)
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		badge.add_theme_constant_override("outline_size", 5)
		badge.add_theme_font_size_override("font_size", OPTION_FONT_SIZE)
		row.add_child(badge)

		var option := Button.new()
		# IGNORE until a question is pending — see _hide_options. The MP panel,
		# the touch buttons and the start overlay share this CanvasLayer.
		option.mouse_filter = Control.MOUSE_FILTER_IGNORE
		option.focus_mode = Control.FOCUS_NONE
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# `flat` so the default theme's grey button panel does not sit on the dark
		# card: the option reads as a line of the card that happens to be tappable,
		# and hover/pressed still draw, so a mouse still gets feedback.
		option.flat = true
		option.alignment = HORIZONTAL_ALIGNMENT_LEFT
		option.add_theme_color_override("font_color", FACT_COLOR)
		option.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		option.add_theme_constant_override("outline_size", 5)
		option.add_theme_font_size_override("font_size", OPTION_FONT_SIZE)
		option.pressed.connect(_answer.bind(slot))
		row.add_child(option)

		_option_rows.append(row)
		_option_buttons.append(option)

	treasure_label = Label.new()
	treasure_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	treasure_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	treasure_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	treasure_label.add_theme_color_override("font_color", TREASURE_COLOR)
	treasure_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	treasure_label.add_theme_constant_override("outline_size", 5)
	treasure_label.add_theme_font_size_override("font_size", TREASURE_FONT_SIZE)
	treasure_label.visible = false
	box.add_child(treasure_label)


func _process(delta: float) -> void:
	_update_burst(delta)
	_update_quiz(delta)
	_update_fade(delta)

	_tick_timer += delta
	if _tick_timer < TICK_INTERVAL:
		return
	_tick_timer = 0.0
	_scan()


# ============================================================================
# PROXIMITY
# ============================================================================

func _scan() -> void:
	"""
	One throttled proximity pass: find the nearest in-range landmark and, if it is
	not the one this approach already belongs to, pop its card.
	"""
	# Cast, don't assume: the marker loop below already refuses a non-Node3D in its
	# group, and the player group deserves the same treatment — a bare Node in
	# "player" would otherwise error on global_position rather than being ignored.
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		# No local player (a scene run standalone, or mid-teardown): re-arm and do
		# nothing, so the next player to appear gets a fresh approach.
		_active = null
		return
	var origin: Vector3 = player.global_position

	# Re-arm FIRST, so a marker that unloaded with its chunk, or one the player has
	# walked out of, cannot block the next approach — including a second approach
	# to the very same landmark.
	if _active != null:
		if not is_instance_valid(_active):
			_active = null
		elif _xz_distance(origin, _active.global_position) > _marker_radius(_active) + LEAVE_PAD:
			_active = null

	# Nearest in-range marker wins. Linear walk on purpose: this group holds 0-3
	# nodes (see the performance note at the top of the file).
	var nearest: Node3D = null
	var nearest_distance: float = INF
	for node in get_tree().get_nodes_in_group("landmark"):
		# No is_instance_valid() here on purpose: get_nodes_in_group() only ever
		# hands back live instances, so the only reachable miss is the cast failing
		# on a non-Node3D somebody added to the group. (The is_instance_valid on
		# `_active` above IS load-bearing — that one is a LATCHED reference, and a
		# marker frees with its chunk.)
		var marker := node as Node3D
		if marker == null:
			continue
		var distance := _xz_distance(origin, marker.global_position)
		if distance >= _marker_radius(marker) + APPROACH_PAD:
			continue
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = marker

	# ONE APPROACH AT A TIME: a card is only raised when nothing is latched. The
	# re-arm block above is the ONLY thing that clears `_active`, so a landmark
	# holds the approach until the player is genuinely `radius + LEAVE_PAD` away
	# from it.
	#
	# WHY THIS IS NOT "replace whatever is on screen with the nearest". Trigger
	# zones DO overlap: LANDMARK_EDGE_MARGIN (12) lets a landmark sit 13 m from a
	# chunk edge, so two in adjacent chunks can be ~26 m apart while two 15.4 m
	# trigger radii reach 30.8 m. Under a `nearest != _active` rule, a player
	# wandering the equidistant line between them flips `nearest` back and forth
	# and gets a FRESH CARD EVERY 0.25 s TICK, alternating, without ever leaving
	# either landmark — measured against this script: z=10.5 → "Stonehenge",
	# z=9.0 → "Taj Mahal", z=10.5 → "Stonehenge" again. The dead-band protects one
	# marker's range test; it cannot protect a comparison BETWEEN two markers.
	# Latching the first arrival is both the correct reading of "once per approach"
	# and the simpler rule.
	# `not _quiz_pending` is the third term because a pending question owns the
	# card until it resolves: the re-arm block above legitimately clears `_active`
	# when the player walks out of range mid-question (leaving does not cancel a
	# quiz, the timeout does), and without this term the very next landmark would
	# overwrite the question with its own card.
	if _active == null and nearest != null and not _quiz_pending:
		_active = nearest
		# The visited latch is marked on ARRIVAL, not on the answer: that is what
		# makes "one question per landmark per run, whatever you answered" free —
		# and it is the same mark the treasure has always made here.
		if _first_visit(nearest):
			_start_quiz(nearest)
		else:
			_show_plain(nearest)


func _marker_radius(marker: Node3D) -> float:
	"""The landmark's own footprint radius, published as a meta by the spawner."""
	return float(marker.get_meta("radius", 0.0))


func _xz_distance(a: Vector3, b: Vector3) -> float:
	"""
	Flat XZ distance. The world is flat (y = 0 ground) and a landmark is up to 18 m
	tall, so including y would make a tall tower trigger LATER than a short statue
	of the same footprint — the opposite of what the radius-derived pad is for.
	"""
	return Vector2(a.x - b.x, a.z - b.z).length()


# ============================================================================
# DISPLAY
# ============================================================================

func _show_plain(marker: Node3D) -> void:
	"""
	The re-visit card: this landmark's name and fact, no question and no coins.

	The two strings go STRAIGHT onto Label.text with no tr() — see the
	localization note at the top of the file before changing that.
	"""
	name_label.text = str(marker.get_meta("name_key", ""))
	fact_label.text = str(marker.get_meta("fact_key", ""))
	fact_label.visible = true
	treasure_label.visible = false
	_hide_options()
	_hold = TOAST_DURATION
	visible = true


func _update_fade(delta: float) -> void:
	"""
	Ease modulate.a toward 1 while the hold timer runs and toward 0 after it
	expires, then stop drawing entirely. A hidden card is `visible = false`, so it
	is not laid out and not drawn — the same "costs nothing when clear" rule
	danger_vignette.gd follows.
	"""
	if not visible:
		return
	var step := delta / FADE_DURATION
	# A pending question never fades: it ends when it is answered or when
	# QUIZ_TIMEOUT runs out, and a card fading out from under a player still
	# reading three names would be a question they could not answer.
	if _quiz_pending:
		modulate.a = minf(modulate.a + step, 1.0)
		return
	if _hold > 0.0:
		_hold -= delta
		modulate.a = minf(modulate.a + step, 1.0)
		return
	modulate.a = maxf(modulate.a - step, 0.0)
	if modulate.a <= 0.0:
		visible = false


# ============================================================================
# QUIZ — the question that gates the treasure (see the QUIZ CONFIGURATION banner)
# ============================================================================

func _start_quiz(marker: Node3D) -> void:
	"""
	Ask "which landmark is this?" for a landmark being visited for the first time
	this run: the prompt on the name line, three option rows, and a countdown.

	THE THREE OPTIONS ARE A PURE FUNCTION of (which place, where it stands,
	run_seed) — `LandmarkBuilders.quiz_options` — which is what makes every peer
	in a room see the same card with no packet, and what keeps this method free of
	any RandomNumberGenerator of its own.
	"""
	var run_seed: int = _sync_run()
	var id: int = COIN_SCRIPT.id_at(marker.global_position)
	# Clamped exactly as quiz_options clamps it, so the `find` below cannot miss:
	# `kind` arrives from a marker meta, i.e. from outside this file.
	var kind: int = clampi(int(marker.get_meta("kind", 0)), 0, LandmarkBuilders.LANDMARKS.size() - 1)
	var options: Array[int] = LandmarkBuilders.quiz_options(kind, id, run_seed)
	if options.size() < OPTION_COUNT:
		# The picker declines on a registry too small to ask a question — 38 rows
		# today, so unreachable, but three names is its contract and not ours.
		# Show the plain card and pay nothing; a landmark you cannot be asked
		# about cannot be answered right.
		_show_plain(marker)
		return

	_quiz_marker = marker
	_quiz_id = id
	_quiz_name = str(marker.get_meta("name_key", ""))
	_quiz_fact = str(marker.get_meta("fact_key", ""))
	_quiz_correct_slot = options.find(kind)
	for slot: int in OPTION_COUNT:
		# RULE 1: the RAW registry name onto the button, never a composed string.
		_option_buttons[slot].text = String(LandmarkBuilders.LANDMARKS[options[slot]]["name"])
		_option_buttons[slot].mouse_filter = Control.MOUSE_FILTER_STOP
		_option_rows[slot].visible = true

	name_label.text = QUIZ_PROMPT
	# The fact is the REVEAL — showing it beside the question would answer it.
	fact_label.text = ""
	fact_label.visible = false
	treasure_label.visible = false
	_quiz_timer = QUIZ_TIMEOUT
	_quiz_pending = true
	_hold = TOAST_DURATION
	visible = true
	# LAST, and deliberately after `_quiz_pending` is set: `_take_pause` flips this
	# node to PROCESS_MODE_ALWAYS, and everything that then keeps running while the
	# rest of the world is frozen reads that flag first.
	_take_pause()


func _answer(slot: int) -> void:
	"""
	Resolve the pending question and turn the card into the reveal: the name, the
	fact, and a verdict line. `slot` is the option chosen, or -1 for the timeout.

	Right answer -> the landmark's own treasure burst, exactly the amount and
	exactly the hash stream the first visit always paid. Wrong or out of time ->
	no coins, but the same reveal: the education is the point, the coins are the
	prize.

	Bound to the option Buttons' `pressed` signal AND called from
	`_unhandled_input`, so a tap and a digit are the same event by construction.
	"""
	if not _quiz_pending:
		return
	# A new run between the ask and the answer cancels the card outright (the
	# world it belonged to is gone), so read the run FIRST and let _sync_run say
	# so before anything is paid into it.
	var run_seed: int = _sync_run()
	if not _quiz_pending:
		return
	_quiz_pending = false
	# THE WORLD STARTS AGAIN HERE. All three resolutions — a digit, a tap on an
	# option Button, and the QUIZ_TIMEOUT expiry — arrive at this one function, so
	# this one line is the whole "and after this game unpauses automatically" half
	# of the ruling. The reveal that follows fades on the ordinary live schedule,
	# exactly like the plain card: what was paused was the QUESTION, not the toast.
	_release_pause()
	_hide_options()

	name_label.text = _quiz_name
	fact_label.text = _quiz_fact
	fact_label.visible = true
	treasure_label.visible = true
	# `slot >= 0` and not just the equality: -1 is the timeout, and a card that
	# somehow had no correct slot would otherwise pay the timeout as a win.
	var correct: bool = slot >= 0 and slot == _quiz_correct_slot
	if correct:
		var amount: int = _treasure_amount(_quiz_id, run_seed)
		_arm_burst(amount)
		# The one composed line on this card, hence the one tr() in this file:
		# Localization RULE 2, on the FORMAT string.
		treasure_label.text = tr(QUIZ_CORRECT) % amount
	elif slot < 0:
		treasure_label.text = QUIZ_TIMEOUT_VERDICT
	else:
		treasure_label.text = QUIZ_WRONG

	# The project's standard null-safe group + has_method shape, so a scene with
	# no SoundManager resolves silently instead of erroring.
	var sm := get_tree().get_first_node_in_group("sound_manager")
	if sm != null:
		if correct and sm.has_method("play_level_up"):
			sm.play_level_up()
		elif not correct and sm.has_method("play_buzz"):
			sm.play_buzz()

	_quiz_marker = null
	# The reveal then fades on the ordinary schedule, from now.
	_hold = TOAST_DURATION
	visible = true


# ----------------------------------------------------------------------------
# THE PAUSE — taken by a pending question, given back by its resolution
# ----------------------------------------------------------------------------
#
# WHY is the owner ruling at the top of the file. This is the HOW, and it is four
# decisions.
#
# 1. `_paused_by_us` IS THE SHARED GUARD, not a local convenience.
#    pause_controller.gd, mp_ui.gd, skill_tree_ui.gd, start_overlay.gd and
#    mobile_input.gd all take `get_tree().paused` and all carry this same flag for
#    the same reason: a pauser may only ever release a pause IT took. A card that
#    resolved while the skill tree was open and unpaused unconditionally would
#    hand the player a running world behind a panel they are still reading.
#
# 2. THE NODE PROCESSES WHILE — AND ONLY WHILE — THE PAUSE IS OURS, and this is
#    the trap the whole change turns on. The quiz clock is `_update_quiz`, driven
#    from `_process`, so under this HUD's default (pausable) process_mode the
#    timeout would freeze along with the tree it had just frozen: QUIZ_TIMEOUT
#    never fires, nothing else can lift the pause, and the run is over. Hence
#    PROCESS_MODE_ALWAYS — set HERE rather than in `_ready` or scenes/main.tscn so
#    it lasts exactly as long as our pause and not one frame longer. That
#    narrowness is what keeps every OTHER pause byte-identical to before this
#    change: under the skill tree, the pause screen or the MP panel this node is
#    pausable again, so it does not scan, does not pay a burst and is not offered
#    input — precisely as it behaved when it paused nothing at all.
#
# 3. IN A ROOM WE DO NOT PAUSE AT ALL. `get_tree().paused` is LOCAL and the
#    simulation is not: crocodiles are master-simulated, so a paused master
#    freezes the world for every peer in the room, and a paused non-master still
#    strands a teammate the others can see standing still. Twelve seconds of that
#    inflicted on three other people, so that one of them can read at leisure, is
#    a worse outcome than the problem being solved — so in a room the card stays
#    exactly what it was before this change (live, answerable while running, and
#    the pocket round a landmark is crocodile-free anyway), and the ruling applies
#    to solo play, where it costs nobody anything. `is_busy()` and not
#    `is_online()`, the same test build_version.gd makes for the same reason: a
#    join spends seconds in CONNECTING before it is IN_ROOM, and a freeze landing
#    in that window is just as visible to the peers already there.
#
# 4. THE MOUSE IS NOT HANDED BACK. pause_controller and mp_ui release a captured
#    cursor when they pause, because their buttons have to be clickable; this card
#    does not, because 1/2/3 answer it and a capture/release round trip at every
#    landmark would yank the camera twice for a card most players answer with a
#    digit. On a touchscreen nothing is captured and the option Buttons are
#    tappable as they stand.
#
# ponytail: THE CEILING THAT LEAVES, stated plainly — this project's pause
# discipline is FIRST-TAKER-OWNS, not a refcount, so an overlay that opens OVER an
# existing pause takes no ownership of it and is left behind when the owner
# releases. `help_overlay.gd` is PROCESS_MODE_ALWAYS and deliberately opens over a
# paused game (reading the keymap while paused is the point of it), so `?` pressed
# during a question, followed by our timeout firing, leaves the world running
# behind the open help card. That is not new and not ours: the identical thing
# already happens on master by opening help over the P pause and then pressing P
# again — what IS new is that our release can arrive on a timer, with the player
# doing nothing. The unattended half of that is closed below (the clock does not
# run while the app is unfocused, which is the case where nobody is watching);
# the `?` half is left, because the honest fix is a shared pause REFCOUNT across
# pause_controller / mp_ui / skill_tree_ui / start_overlay / mobile_input /
# help_overlay and this file, which is a change to six other scripts' contracts
# and belongs to none of them alone. Upgrade path: exactly that refcount, with
# `_paused_by_us` becoming "we hold a claim" instead of "we hold THE claim".


func _notification(what: int) -> void:
	# WHY THE QUIZ CLOCK STOPS WITH THE WINDOW. `mobile_input.pause_game()` is
	# idempotent by early-returning on an already-paused tree, so a focus loss
	# during a question sees OUR pause, takes no ownership, and never raises the
	# "tap to resume" overlay. Left alone, QUIZ_TIMEOUT would then fire in a
	# backgrounded tab, unpause, and hand the player back a running world with a
	# crocodile in it — the one variant of the ceiling above where nobody is
	# watching it happen. Freezing the clock instead means a backgrounded question
	# is simply still there, still frozen, when the player comes back. The hold is
	# gated on `_paused_by_us` in `_update_quiz`, so it protects a frozen world and
	# never a room, where nothing was frozen in the first place.
	#
	# Deliberately NOT resumed on FOCUS_IN alone: this mirrors the resume the
	# player would have got, and there is nothing to recalibrate, so the flag just
	# flips back and the countdown continues where it stopped.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_unfocused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_unfocused = false

func _take_pause() -> void:
	"""
	Freeze the world for a question that has just been asked, or decline for one of
	the three reasons above it would be wrong to.
	"""
	var tree := get_tree()
	# Somebody else's pause is already up. There is nothing to take, and nothing we
	# would be allowed to give back — leave it alone entirely. (Unreachable while
	# this node is pausable, since `_scan` could not have run; it is here because
	# that is a property of decision 2 above, not of this function.)
	if tree.paused:
		return
	# A ROOM: the pause is local and the simulation is not — see decision 3.
	var mp: Node = tree.get_first_node_in_group("mp")
	if mp != null and mp.has_method("is_busy") and bool(mp.is_busy()):
		return
	# Never over the game-over screen: the same rule, and the same reason, that
	# pause_controller._toggle_pause, mp_ui._apply_pause and mobile_input all
	# carry — GameOverUI is PAUSABLE, so a pause there kills its Play Again button
	# and its ui_accept handler. The card still asks; it just freezes nothing.
	# `"x" in node`, not `node.get("x")`: get() answers null for a property that
	# does not exist and bool(null) is a hard error, so the property test is what
	# lets a scene whose player is a stand-in (a standalone scene, a headless
	# check) degrade instead of throwing. Same shape as the `"run_seed" in terrain`
	# read in _sync_run.
	var player: Node = tree.get_first_node_in_group("player")
	if player != null and "is_game_over" in player and bool(player.is_game_over):
		return
	tree.paused = true
	_paused_by_us = true
	process_mode = Node.PROCESS_MODE_ALWAYS


func _release_pause() -> void:
	"""
	Give back the pause this card took, and ONLY that one.

	Called from all three exits from `_quiz_pending` — `_answer` (digit, tap and
	timeout all land there) and `_cancel_quiz` — plus `_exit_tree`, so there is no
	path on which a pending question can hold the world frozen forever.
	"""
	if not _paused_by_us:
		return
	_paused_by_us = false
	process_mode = Node.PROCESS_MODE_INHERIT
	get_tree().paused = false


func _exit_tree() -> void:
	# A toast freed with a question still up — a scene change, or a headless check
	# tearing its fixture down — would otherwise leave the tree paused with nothing
	# alive that is allowed to unpause it.
	_release_pause()


func _update_quiz(delta: float) -> void:
	"""
	Run the pending question's clock. Two things end a question that nobody
	answered, and both resolve as a timeout:

	  * QUIZ_TIMEOUT running out — the card cannot hang forever, and walking away
	    deliberately does NOT cancel it (that would be a free refusal);
	  * the marker being freed under it, i.e. its chunk streamed out because the
	    player ran off. The reveal still renders: the name, the fact and the id
	    were copied at ask time precisely so this case has everything it needs.
	"""
	if not _quiz_pending:
		return
	# The window is gone (tab switched, phone backgrounded) AND the world is frozen
	# because of us: hold the question and its pause exactly where they are — see
	# _notification.
	#
	# `and _paused_by_us` is load-bearing, not defensive. In a room we take no
	# pause, so the world keeps running while the window is away — crocodiles
	# included — and a clock stopped there would hand an alt-tabbing player an
	# indefinite question the timeout can no longer end, which is exactly the free
	# refusal QUIZ_TIMEOUT exists to prevent. The hold protects a FROZEN world, and
	# only a frozen one.
	if _unfocused and _paused_by_us:
		return
	# A new run cancels a pending question the same way it cancels a shower in
	# flight, and for the same reason — see _sync_run. One group lookup per frame,
	# but ONLY while a question is up: at most QUIZ_TIMEOUT per landmark visited,
	# against a run measured in minutes, exactly the trade _update_burst makes.
	_sync_run()
	if not _quiz_pending:
		return
	if not is_instance_valid(_quiz_marker):
		_answer(-1)
		return
	_quiz_timer -= delta
	if _quiz_timer <= 0.0:
		_answer(-1)


func _unhandled_input(event: InputEvent) -> void:
	"""
	1/2/3 (number row or numpad) answer the pending question.

	UNHANDLED, not `_input`: a digit typed into a focused text field or consumed
	by anything above this card must not also answer a quiz.

	THE PAUSE GUARD IS EXPLICIT AND MUST STAY — and since the card now takes a
	pause of its own it can no longer be a plain `if get_tree().paused`. The digits
	have to WORK under our pause (being frozen so you can answer is the entire
	point of it) and stay DEAD under anybody else's, or a player closing the skill
	tree with the number row answers blind. Getting it wrong in either direction is
	a bug, and `_paused_by_us` is the one bit that separates them — the same
	one-line test skill_tree_ui.gd uses to decide whether a pause it can see is its
	own.

	It does NOT lean on process_mode. While somebody else's pause is up this node
	is pausable and the engine withholds the event anyway, but that is a property
	of `_take_pause` (decision 2 in the PAUSE banner), not of this function, and
	this guard is what survives the next person changing it. landmark_selfcheck.gd
	drives both directions directly.
	"""
	if not _quiz_pending:
		return
	if get_tree().paused and not _paused_by_us:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	for slot: int in OPTION_COUNT:
		if (ANSWER_KEYCODES[slot] as Array).has(key.keycode):
			_answer(slot)
			accept_event()
			return


func _hide_options() -> void:
	"""
	Put the option rows away. Hidden AND back to MOUSE_FILTER_IGNORE: the card
	shares its CanvasLayer with the MP panel, the touch buttons and the start
	overlay, and a stray click-eating rectangle over any of them is invisible and
	maddening (the whole reason this Control is IGNORE in the first place).
	"""
	for slot: int in OPTION_COUNT:
		_option_rows[slot].visible = false
		_option_buttons[slot].mouse_filter = Control.MOUSE_FILTER_IGNORE


func _cancel_quiz() -> void:
	"""
	Drop a pending question and its card without resolving it — the run it belongs
	to no longer exists. Called only from _sync_run's run-change branch, beside
	the burst cancel it mirrors.
	"""
	if not _quiz_pending:
		return
	_quiz_pending = false
	# The third and last exit from `_quiz_pending`, and the one with no card left
	# on screen to explain a pause it forgot to give back.
	_release_pause()
	_quiz_marker = null
	_hide_options()
	_hold = 0.0
	modulate.a = 0.0
	visible = false
	# Re-arm the approach latch too, or the first landmark of the NEW run would be
	# blocked by a marker from the old one.
	_active = null


# ============================================================================
# TREASURE — the first-visit coin burst (see the TREASURE CONFIGURATION banner)
# ============================================================================

func _first_visit(marker: Node3D) -> bool:
	"""
	Answer whether this is the run's FIRST arrival at this landmark, MARKING it
	visited if so. Marking here — at arrival, before any question is asked — is
	what makes "one question per landmark per run, whatever you answered" free:
	walking away from an unanswered card and coming back finds it already marked.
	"""
	_sync_run()
	var id: int = COIN_SCRIPT.id_at(marker.global_position)
	if _visited.has(id):
		return false
	_visited[id] = true
	return true


func _treasure_amount(id: int, run_seed: int) -> int:
	"""
	How many coins this landmark pays, drawn from a private RandomNumberGenerator
	seeded from its own hash stream, so it consumes no draw from anything else in
	the project.

	A PURE FUNCTION OF (landmark id, run_seed), and that purity is what makes the
	multiplayer promise honest: every peer in a room shares run_seed and generates
	the landmark in the same place, so the same landmark pays the same amount to
	everyone — with no packet, no arbitration and no server involved.

	It takes the ID rather than the marker deliberately: it is called at ANSWER
	time, by which point the marker may have streamed out with its chunk, and the
	id was copied when the question was asked.
	"""
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(id, TREASURE_SALT, run_seed))
	return rng.randi_range(TREASURE_COINS_MIN, TREASURE_COINS_MAX)


func _arm_burst(amount: int) -> void:
	"""
	Owe `amount` more single coins and (re)spread the whole debt over
	TREASURE_BURST_DURATION.
	"""
	# ADD to whatever is still owed, never REPLACE it. Trigger zones genuinely
	# overlap (see the selection-rule note in _scan: two landmarks in adjacent
	# chunks can be ~26 m apart against 15.4 m trigger radii), and 1.2 s of Air
	# Rush covers 30 m — so leaving one landmark and arriving at the next one
	# mid-shower is reachable, and a plain assignment would silently swallow most
	# of the first card's advertised reward. Re-dividing the FULL debt across
	# TREASURE_BURST_DURATION is what keeps the merged shower inside the 2.5 s
	# STREAK_WINDOW, which is the whole reason the stagger is timed at all.
	_burst_remaining += amount
	_burst_interval = TREASURE_BURST_DURATION / float(_burst_remaining)
	_burst_timer = _burst_interval
	# First coin on arrival, treasure_chest.gd's rule; the rest follow.
	_award_one()


func _sync_run() -> int:
	"""
	Answer the run this treasure state belongs to, emptying the per-run state
	first if the run has changed underneath us. Returns the current run seed.

	THE RUN GATE, and it is read fresh rather than latched in _ready(), which is
	what makes the whole feature work with no signal and no reset plumbing: a
	new_run() — an explicit restart, or a multiplayer room's shared world arriving
	— re-rolls `endless_terrain.run_seed`, and this notices. A RESPAWN re-rolls
	nothing, so a death costs you no landmark you had already emptied.

	A RUNNING BURST — AND A PENDING QUESTION — IS CANCELLED WITH THE VISITED SET,
	not left to drain into the new run. new_run() can land in the middle of the 1.2 s shower (Play Again, or
	a room seed arriving), and restart_game() wipes the run's coins immediately
	before it — so coins from a world that no longer exists would trickle into the
	fresh run's counter for a second afterwards. That is also why this is called
	from _update_burst and not only from the claim: nothing else runs while coins
	are owed, and a lazy check on "the next claim" is a check that may be a
	kilometre away.
	"""
	var terrain := get_tree().get_first_node_in_group("terrain")
	var run_seed: int = 0
	if terrain != null and "run_seed" in terrain:
		run_seed = int(terrain.run_seed)
	if run_seed != _visited_run_seed:
		_visited_run_seed = run_seed
		_visited.clear()
		_burst_remaining = 0
		# A question asked about the old world cannot be answered into the new
		# one — same event, same reason, as the shower cancel above it.
		_cancel_quiz()
	return run_seed


func _update_burst(delta: float) -> void:
	"""
	Pay out whatever the burst still owes. Runs from _process, ABOVE the fade and
	outside the proximity throttle, so the shower keeps paying at the frame rate
	while the card is fading and after it has gone.

	A `while`, not an `if`, for treasure_chest.gd's reason: at TREASURE_COINS_MAX
	over TREASURE_BURST_DURATION the gap is ~48 ms, which one frame hitch (or a
	browser tab regaining focus) easily overruns — paying a single coin per frame
	would silently stretch the burst past the streak window.
	"""
	if _burst_remaining <= 0:
		return
	# One group lookup per frame, but ONLY while coins are actually owed — at most
	# 1.2 s per landmark visited, against a run measured in minutes. See _sync_run.
	_sync_run()
	if _burst_remaining <= 0:
		return
	_burst_timer -= delta
	while _burst_remaining > 0 and _burst_timer <= 0.0:
		_burst_timer += _burst_interval
		_award_one()


func _award_one() -> void:
	"""
	One ordinary coin, through the ordinary path — the whole point of the burst
	(see the TREASURE CONFIGURATION banner for why it is never collect_coin(N)).

	The player is re-fetched per coin rather than held: a respawn, a restart or a
	room's join placement can all move or free things underneath a running burst,
	and a group lookup 20 times over a second is nothing. Both lookups are the
	project's standard null-safe group + has_method shape, so a scene with neither
	a player nor a SoundManager pays silently instead of erroring.
	"""
	_burst_remaining -= 1
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("collect_coin"):
		player.collect_coin(1)
	var sm := get_tree().get_first_node_in_group("sound_manager")
	if sm != null and sm.has_method("play_coin"):
		sm.play_coin()
