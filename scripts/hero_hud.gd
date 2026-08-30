extends Control
## Hero portrait HUD — the Commandos-style squad row under the hearts.
##
## Four tiles, one per `PlayerController.CHARACTERS` entry, in that array's order,
## each carrying its 1-4 hotkey digit. The tile says, at a glance, WHO YOU ARE and
## WHO YOU HAVE LEFT — which is the whole point once systemic capture starts taking
## heroes off the roster (see "Systemic capture" in CLAUDE.md): a hero in a cell has
## to read as *taken*, not merely as "not selected".
##
## Four states, and they are deliberately three different visual languages so none
## of them can be mistaken for another at 48 px:
##
##   ACTIVE   full brightness + a bright border   this is the body you are driving
##   FREE     full brightness, no border          yours to switch to
##   HELD     dimmed                              a teammate in the room has him
##   CAPTIVE  dimmed + red bars across the tile   the corporation is holding him
##
## HELD and CAPTIVE are both "you cannot be him", and they are still drawn apart on
## purpose: one is a lobby fact that resolves itself when a teammate switches, the
## other is a thing you fix by walking into the tower.
##
## Like every other widget in this HUD it is DISCOVERY-BASED and POLLED — it finds
## the player through the "player" group, re-fetching when the reference goes stale,
## and mirrors state read off the player every frame (there is no capture signal to
## subscribe to, and inventing one would put a second roster system in the game).
## It repaints only when what it would draw actually changed, the `lives_hud.gd`
## idiom, so the common case costs one integer comparison a frame and no `_draw`.
##
## It is READ-ONLY: no input handling, `MOUSE_FILTER_IGNORE`, and the capture and
## liberation paths in `player_controller` need no edit at all — the HUD reads the
## roster, it is never told about it.
##
## ---------------------------------------------------------------------------
## PORTRAITS — one asset path, and a placeholder that is always there
## ---------------------------------------------------------------------------
## `res://assets/portraits/<hero>.png`, the hero being the `CHARACTERS` name. The
## four shipped images are 256x256 crops of the owner's generated art; dropping a
## replacement in by filename needs no code change, and a MISSING file is not an
## error — the tile falls back to the procedural placeholder (the hero's identity
## colour plus his initial), so a hero added to `CHARACTERS` with no art yet still
## gets a legible tile.

## The roster's ONE definition, reached the way `mp_manager` reaches it: the
## script's const, not a copy. A fifth playable character is a `CHARACTERS` entry,
## a `HERO_COLORS` row and a portrait file, with nothing else in here to edit.
## (This is a SCRIPT dependency, not a node reference — the live player is still
## found through the "player" group, per the discovery convention.)
const PLAYER_SCRIPT := preload("res://scripts/player_controller.gd")

## One tile, and the gap between two of them. Four tiles = 4*48 + 3*6 = 210 px.
const TILE_SIZE: float = 48.0
const TILE_GAP: float = 6.0

## Hero identity colours — the placeholder fill, and the tint of the active border.
##
## They live HERE and nowhere else on purpose: nothing else in the game needs a
## per-hero colour yet (`mp_manager.peer_color` is per PEER, which is a different
## question with a different answer in a room), so a shared table would be one more
## thing to keep in sync for a single reader. The violet/orange pair matches the
## identity-pad language the tower interior already speaks.
const HERO_COLORS: Dictionary = {
	"windman": Color(0.36, 0.68, 0.95),   # sky blue
	"primm": Color(0.62, 0.40, 0.88),     # violet
	"teibi": Color(0.95, 0.60, 0.18),     # orange
	"phoboman": Color(0.36, 0.75, 0.42),  # green
}
## A hero with no row above (a new `CHARACTERS` entry, say) still gets a tile.
const FALLBACK_COLOR: Color = Color(0.55, 0.55, 0.60)

# --- Tile states (what `_states` holds, one per hero) ------------------------
const STATE_FREE: int = 0
const STATE_ACTIVE: int = 1
const STATE_HELD: int = 2
const STATE_CAPTIVE: int = 3

# --- Colours ----------------------------------------------------------------
const COLOR_BACKDROP: Color = Color(0, 0, 0, 0.45)      # dark disc behind a tile
const COLOR_FRAME: Color = Color(0, 0, 0, 0.75)         # thin outline, every tile
const COLOR_ACTIVE_BORDER: Color = Color(1, 1, 1, 0.95) # the "this is you" ring
const COLOR_DIM: Color = Color(0, 0, 0, 0.62)           # veil over held/captive
const COLOR_BARS: Color = Color(0.85, 0.16, 0.14, 0.92) # the cell bars
const COLOR_DIGIT: Color = Color(1, 1, 1, 0.9)

const ACTIVE_BORDER_WIDTH: float = 3.0
const DIGIT_FONT_SIZE: int = 13
## Three bars across a captive tile, Commandos-style.
const BAR_COUNT: int = 3
const BAR_WIDTH: float = 3.0

## Cached player reference — re-fetched whenever it goes away (respawn, restart,
## character switch all keep the same node, but a scene reload does not).
var player: Node = null

## The roster we last read, in `CHARACTERS` order, and the state of each tile.
## Both are written by `_process` and read by `_draw`, so the change-check and the
## drawing can never disagree. An empty roster means "nothing to draw" — which is
## how this degrades when the scene is run standalone with no player at all.
var _heroes: PackedStringArray = PackedStringArray()
var _states: PackedInt32Array = PackedInt32Array()

## Portrait cache, hero name -> Texture2D or null. Loaded ONCE per hero on the
## first frame we know the roster; a null entry means "looked, not there, use the
## placeholder" and is never retried — `load()` per frame would be the landmine.
var _portraits: Dictionary = {}


func _ready() -> void:
	add_to_group("hero_hud")
	# A HUD overlay must never eat clicks meant for the game or the touch controls.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")

	var heroes := _read_roster()
	var states := _read_states(heroes)
	# Repaint only on change (lives_hud idiom) — `_draw` is comparatively
	# expensive and the roster is unchanged on almost every frame of a run.
	if heroes == _heroes and states == _states:
		return
	_heroes = heroes
	_states = states
	queue_redraw()


func _read_roster() -> PackedStringArray:
	"""
	The hero names to draw, in `CHARACTERS` order — EMPTY when there is no player.

	The emptiness is the standalone degrade: with nothing in group "player" (this
	scene run on its own, or a headless harness) the row has no state to report, so
	it draws nothing at all rather than four misleading idle tiles.
	"""
	var out := PackedStringArray()
	if player == null or not is_instance_valid(player):
		return out
	for entry: Variant in PLAYER_SCRIPT.CHARACTERS:
		out.append(String((entry as Dictionary)["name"]))
	return out


func _read_states(heroes: PackedStringArray) -> PackedInt32Array:
	"""
	One state per hero — see the STATE_* consts.

	`reachable_character_indices()` is the game's single answer to "who may I
	PRESS right now" (hand INTERSECT free, plus the room's UNHELD free heroes,
	which `switch_to_character()` claims through the lobby — bead godot-test1-4zw);
	asking it here rather than re-deriving any of that is what keeps this HUD from
	becoming a second roster system. A hero a teammate is actually wearing still
	reads HELD, because that press is still refused.
	Everything is `has_method`-guarded, so a player that predates any of these
	methods simply reads as all-free instead of erroring.

	COST, so the next reader does not have to go and find it: that one call reaches
	`_mp()`, which is an uncached `get_first_node_in_group("mp")`, and allocates two
	small arrays — every frame, like the landmark quiz tick. It is a hash fetch and
	two four-element arrays against a frame that streams chunks and steers a hundred
	predators, so it is deliberately NOT throttled: the acceptance is that R moves
	the highlight on the SAME frame, and a 10 Hz roster poll buys nothing measurable
	in exchange for a latency nobody asked for.
	"""
	var out := PackedInt32Array()
	if heroes.is_empty():
		return out
	var active: int = -1
	if "current_character_index" in player:
		active = player.current_character_index
	var available: Array = []
	var has_available: bool = player.has_method("reachable_character_indices")
	if has_available:
		available = player.reachable_character_indices()
	var can_ask_captive: bool = player.has_method("is_hero_captive")

	for index: int in heroes.size():
		var hero := heroes[index]
		var state := STATE_FREE
		if can_ask_captive and player.is_hero_captive(hero):
			# Captivity outranks everything below: the ACTIVE hero can be grabbed
			# and the auto-switch happens a beat later, so for that one frame the
			# honest tile is "in a cell", not "this is you".
			state = STATE_CAPTIVE
		elif index == active:
			state = STATE_ACTIVE
		elif has_available and not available.has(index):
			state = STATE_HELD  # a teammate in the room is wearing him
		out.append(state)
	return out


func _portrait(hero: String) -> Texture2D:
	"""The hero's portrait, or null to fall back to the placeholder. Cached both
	ways so the filesystem is touched at most once per hero per run."""
	if _portraits.has(hero):
		return _portraits[hero]
	var path := "res://assets/portraits/%s.png" % hero
	# `ResourceLoader.exists` first: a bare `load()` on a missing path is a red
	# console error every time a hero ships before his art does.
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_portraits[hero] = tex
	return tex


func _draw() -> void:
	# Drawn entirely from the _process snapshot — no player reads in here. An empty
	# roster draws nothing, which is also how the control clears itself.
	var font := get_theme_default_font()
	for i: int in _heroes.size():
		var hero := _heroes[i]
		var state: int = _states[i]
		var rect := Rect2(
			Vector2(i * (TILE_SIZE + TILE_GAP), 0.0),
			Vector2(TILE_SIZE, TILE_SIZE)
		)
		var tint: Color = HERO_COLORS.get(hero, FALLBACK_COLOR)

		# Backdrop, so a portrait with light edges still reads over a bright sky.
		draw_rect(rect, COLOR_BACKDROP)
		var portrait := _portrait(hero)
		if portrait != null:
			draw_texture_rect(portrait, rect, false)
		else:
			# Placeholder: the identity colour plus the hero's initial, drawn the
			# way ability_hud draws its labels (default font, dark outline).
			draw_rect(rect, tint)
			_draw_initial(font, hero.substr(0, 1).to_upper(), rect)

		# Held and captive are both unavailable, so both take the veil; only
		# captivity adds the bars on top of it.
		if state == STATE_HELD or state == STATE_CAPTIVE:
			draw_rect(rect, COLOR_DIM)
		if state == STATE_CAPTIVE:
			_draw_bars(rect)

		# Frame: a bright tinted ring for the body you are driving, a thin dark
		# outline for everyone else so the tiles stay separable against the sky.
		if state == STATE_ACTIVE:
			draw_rect(rect, COLOR_ACTIVE_BORDER.lerp(tint, 0.35), false,
				ACTIVE_BORDER_WIDTH)
		else:
			draw_rect(rect, COLOR_FRAME, false, 1.0)

		# The hotkey digit, top-left of the tile. A LABEL ONLY — this HUD binds
		# nothing and depends on no hotkey bead; the digits match the 1-4 order
		# the roster is already in.
		_draw_digit(font, str(i + 1), rect)


func _draw_initial(font: Font, letter: String, rect: Rect2) -> void:
	"""The placeholder's big centred initial, with a dark outline for legibility."""
	var font_size := int(TILE_SIZE * 0.6)
	var width := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	# Baseline placed so the cap-height block sits visually centred in the tile.
	var pos := rect.position + Vector2(
		(rect.size.x - width) * 0.5,
		rect.size.y * 0.5 + font_size * 0.36
	)
	font.draw_string_outline(get_canvas_item(), pos, letter, HORIZONTAL_ALIGNMENT_LEFT,
		-1, font_size, 4, Color(0, 0, 0, 0.8))
	font.draw_string(get_canvas_item(), pos, letter, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, Color(1, 1, 1, 0.95))


func _draw_digit(font: Font, digit: String, rect: Rect2) -> void:
	"""The 1-4 hotkey hint in the tile's top-left corner."""
	var pos := rect.position + Vector2(3.0, DIGIT_FONT_SIZE + 1.0)
	font.draw_string_outline(get_canvas_item(), pos, digit, HORIZONTAL_ALIGNMENT_LEFT,
		-1, DIGIT_FONT_SIZE, 4, Color(0, 0, 0, 0.9))
	font.draw_string(get_canvas_item(), pos, digit, HORIZONTAL_ALIGNMENT_LEFT, -1,
		DIGIT_FONT_SIZE, COLOR_DIGIT)


func _draw_bars(rect: Rect2) -> void:
	"""Cell bars across a captive hero's tile — the Commandos read, and the one
	state that gets a shape of its own rather than a brightness of its own."""
	var step := rect.size.x / float(BAR_COUNT + 1)
	for b: int in BAR_COUNT:
		var x := rect.position.x + step * float(b + 1)
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), COLOR_BARS,
			BAR_WIDTH)
