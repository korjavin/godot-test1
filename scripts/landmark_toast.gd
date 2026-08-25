extends Control
## Landmark toast — the educational half of the geo-landmark feature.
##
## Walk within a few metres of Stonehenge, the Pyramids of Giza or the Eiffel
## Tower and a small card slides up at the bottom of the screen naming the place
## and giving one real fact about it. That card IS the reward for detouring to a
## landmark (the coin ring round the base is a garnish — see the REWARD DECISION
## in endless_terrain.gd's GEO LANDMARKS constant banner).
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

## Seconds the card stays fully visible before it starts fading out. Long enough
## to read two lines without being long enough to sit over the game.
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

# ============================================================================
# STATE
# ============================================================================

## The two labels, built in _ready(). Held as members because the tick writes
## them; nothing outside this script ever touches them.
var name_label: Label = null
var fact_label: Label = null

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
## which is the same behaviour and costs nothing to allow. Upgrade path, if the
## repeat ever reads as noise: a seen-set keyed on the registry index (the marker
## would need to carry it as a fourth meta), which survives chunk unload because
## it is keyed on the PLACE and not on the node.
var _active: Node3D = null

## Seconds of full visibility left before the fade-out starts. > 0 means "fade
## toward opaque", <= 0 means "fade toward transparent".
var _hold: float = 0.0

## Throttle accumulator for the proximity scan.
var _tick_timer: float = 0.0


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


func _process(delta: float) -> void:
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
	var player := get_tree().get_first_node_in_group("player")
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
		var marker := node as Node3D
		if marker == null or not is_instance_valid(marker):
			continue
		var distance := _xz_distance(origin, marker.global_position)
		if distance >= _marker_radius(marker) + APPROACH_PAD:
			continue
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = marker

	# A new approach REPLACES whatever is on screen (new text, timer reset) rather
	# than queueing: two landmarks close enough to overlap triggers is rare, and a
	# queue would show the card for a place the player has already left.
	if nearest != null and nearest != _active:
		_active = nearest
		_show(nearest)


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

func _show(marker: Node3D) -> void:
	"""
	Put this landmark's name and fact on the card and start the hold timer.

	The two strings go STRAIGHT onto Label.text with no tr() — see the
	localization note at the top of the file before changing that.
	"""
	name_label.text = str(marker.get_meta("name_key", ""))
	fact_label.text = str(marker.get_meta("fact_key", ""))
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
	if _hold > 0.0:
		_hold -= delta
		modulate.a = minf(modulate.a + step, 1.0)
		return
	modulate.a = maxf(modulate.a - step, 0.0)
	if modulate.a <= 0.0:
		visible = false
