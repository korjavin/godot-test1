extends Control
## Hero portrait HUD — the Commandos-style squad row, and since bead
## godot-test1-0bc the HUD's only death display: the heroes ARE the lives.
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
## It repaints only when what it would draw actually changed — the HUD widget
## idiom in this project — so the common case costs one integer comparison a
## frame and no `_draw`.
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
##
## ---------------------------------------------------------------------------
## VOICE (bead godot-test1-xtr.8) — TWO GLYPHS, AND ONLY IN A BROWSER ROOM
## ---------------------------------------------------------------------------
## The MP panel and the floating name tags are both places you have to be LOOKING
## to learn that voice works. This row is on screen always, so it carries the two
## readings the owner asked for: a MIC BADGE on the tile of the hero you are
## driving (plus a headphone-slash beside it while deafened), and a pulsing green
## SPEAKING RING on the tile of whichever hero's holder is talking.
##
## Both are read off the `"voice"` group through `has_method` guards and both are
## answered by `voice_chat.gd` — `mic_badge()` and `is_hero_speaking()`. The hero
## -> holder mapping and the browser's `me` level key stay over there beside the
## camera tiles that already need them; this widget only draws. Off the web, with
## no voice node, or outside a room every answer is "nothing", so the row DRAWS
## exactly what bead .7's did and repaints exactly as rarely — the whole cost on a
## desktop or headless run is two dynamic dispatches a frame, and `mic_badge()`
## itself short-circuits before touching anything.
##
## THE BADGE RIDES THE HERO YOU DRIVE, NOT THE ACTIVE TILE — see `_badge_index`;
## and the two draw decisions are `badge_on_tile()` / `deafen_on_tile()`, public
## because a `_draw` outside the tree has no canvas item and they are the only
## part of the painting a headless check can measure.
##
## The green is `remote_avatar.gd`'s `LABEL_SPEAKING_COLOR`, mirrored rather than
## preloaded (the discovery convention refuses a hard reference to another node's
## script) so a speaking teammate reads the same colour on his name tag and on his
## tile; `hero_hud_selfcheck` check 7 binds the two numbers.

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

# --- Colours, and they all come off `HudTheme` -------------------------------
## THE PILOT PANEL for bead `godot-test1-y1o.24`: this row is the first thing in
## the game drawn in the films' palette, and it is what the owner rules the whole
## HUD spec from. Not one of the six hexes is typed here — `hud_theme.gd` is their
## one home and `hero_hud_selfcheck` check 8 greps the tree to keep it that way.
const COLOR_BACKDROP: Color = Color(HudTheme.INK, HudTheme.PANEL_ALPHA)
const COLOR_FRAME: Color = HudTheme.STEEL                # thin frame, every tile
const COLOR_ACTIVE_BORDER: Color = HudTheme.VISOR_AMBER  # the "this is you" ring
## SEMANTIC, not stylistic — the one colour on this row the palette does not own.
## A cell is a cell; see the note at the foot of `HudTheme`'s palette.
const COLOR_BARS: Color = Color(0.85, 0.16, 0.14, 0.92) # the cell bars
const COLOR_DIGIT: Color = HudTheme.BONE

const ACTIVE_BORDER_WIDTH: float = 3.0
const DIGIT_FONT_SIZE: int = 13
## Three bars across a captive tile, Commandos-style.
const BAR_COUNT: int = 3
const BAR_WIDTH: float = 3.0

# --- Voice (bead godot-test1-xtr.8) -----------------------------------------
## `voice_chat.MIC_BADGE_*`, mirrored rather than preloaded — the voice node is
## found through its group like every other system here, and `voice_chat.gd`
## mirrors this row's `STATE_CAPTIVE` in the other direction for exactly the same
## reason. `hero_hud_selfcheck` check 7 binds all five numbers.
const MIC_BADGE_NONE: int = 0
const MIC_BADGE_OFF: int = 1
const MIC_BADGE_TX: int = 2
const MIC_BADGE_MUTED: int = 3
const MIC_BADGE_DENIED: int = 4

## `remote_avatar.LABEL_SPEAKING_COLOR` — one speaking colour for the whole game,
## and SEMANTIC like the bars: a talking teammate must read the same on his name
## tag and on his tile, and the palette has no green.
const COLOR_SPEAKING: Color = Color(0.55, 1.0, 0.55)
## The badge palette, off `HudTheme`: an idle mic is the corporation's neutral
## khaki, a refused one is the single amber accent, and a hand mute takes the
## cell bars' red because both mean "this is shut". TX takes the speaking green
## above, so "my mic is open" and "somebody is talking" are one language.
const COLOR_MIC_OFF: Color = HudTheme.UNIT_KHAKI
const COLOR_MIC_MUTED: Color = COLOR_BARS
const COLOR_MIC_DENIED: Color = HudTheme.VISOR_AMBER
## Ink disc under a glyph, so it reads over a light portrait.
const COLOR_BADGE_BACKDROP: Color = Color(HudTheme.INK, 0.72)

## The speaking ring, drawn INSIDE the frame so it can never be mistaken for the
## active border it sits next to.
const RING_INSET: float = 3.0
const RING_WIDTH: float = 2.0
## It pulses, and the pulse is QUANTIZED on purpose: this widget repaints only
## when its snapshot changes (the HUD idiom), so a continuous sine would repaint
## every frame for as long as anybody talks. Eight steps at 2 Hz is 16 repaints a
## second while somebody is speaking and none at all otherwise.
const RING_PULSE_HZ: float = 2.0
const RING_PULSE_STEPS: int = 8
const RING_ALPHA_MIN: float = 0.45
const RING_ALPHA_MAX: float = 1.0

## Glyph geometry, in tile pixels. One badge box in each bottom corner.
const BADGE_SIZE: float = 15.0
const BADGE_MARGIN: float = 2.0

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

## Cached voice node, re-fetched like `player` when it goes away. Null on every
## desktop and headless run — there is no voice node off the web export.
var voice: Node = null

## The voice snapshot, written by `_process` and read by `_draw` exactly like
## `_heroes`/`_states`. `_speaking` is a BITMASK over the row (bit i = tile i), so
## the change-check stays one integer comparison; `_pulse` is the quantized ring
## phase and is 0 whenever nothing is speaking, which is what stops the pulse from
## repainting an idle row.
var _mic_badge: int = MIC_BADGE_NONE
var _deafened: bool = false
var _speaking: int = 0
var _pulse: int = 0
## Which tile the mic badge rides: the hero you are DRIVING, which is deliberately
## NOT "the ACTIVE tile". Captivity outranks ACTIVE, and a BENCHED peer keeps
## driving the hero the lobby says they hold while that hero is in a cell — so a
## row with no ACTIVE tile at all is a normal state of a room, and it is precisely
## the state in which somebody is on the microphone asking to be let out.
var _badge_index: int = -1


func _ready() -> void:
	add_to_group("hero_hud")
	# A HUD overlay must never eat clicks meant for the game or the touch controls.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")

	var heroes := _read_roster()
	var states := _read_states(heroes)
	var badge := _read_mic_badge()
	var driven := _driven_index(heroes)
	var deaf := badge != MIC_BADGE_NONE and _read_deafened()
	var speaking := _read_speaking(heroes, badge)
	# The ring's phase is only asked for while something is actually ringing, so
	# an idle row's snapshot is as static as it was before voice existed.
	var pulse: int = 0
	if speaking != 0:
		pulse = int(fmod(float(Time.get_ticks_msec()) * 0.001 * RING_PULSE_HZ, 1.0)
			* float(RING_PULSE_STEPS))
	# Repaint only on change (the HUD widget idiom) — `_draw` is comparatively
	# expensive and the roster is unchanged on almost every frame of a run.
	if heroes == _heroes and states == _states and badge == _mic_badge \
			and driven == _badge_index and deaf == _deafened \
			and speaking == _speaking and pulse == _pulse:
		return
	_heroes = heroes
	_states = states
	_mic_badge = badge
	_badge_index = driven
	_deafened = deaf
	_speaking = speaking
	_pulse = pulse
	queue_redraw()


func _driven_index(heroes: PackedStringArray) -> int:
	"""
	The slot of the hero this player is DRIVING, or -1. Not a state — see
	`_badge_index`: a captive or benched hero is still the body you are in.
	"""
	if heroes.is_empty() or player == null or not is_instance_valid(player):
		return -1
	if not ("current_character_index" in player):
		return -1
	var index: int = int(player.current_character_index)
	return index if index >= 0 and index < heroes.size() else -1


func _voice_node() -> Node:
	"""The voice module, or null — group discovery, re-fetched when it goes away."""
	if voice != null and is_instance_valid(voice):
		return voice
	# Outside the tree there is no group to search, and `get_tree()` there is a
	# logged error rather than a null — `tile_rect()`'s guard, one seam along.
	if not is_inside_tree():
		return null
	voice = get_tree().get_first_node_in_group("voice")
	return voice


func _read_deafened() -> bool:
	"""Is the local player deafened? False with no voice node, or one without it."""
	var node := _voice_node()
	if node == null or not node.has_method("is_deafened"):
		return false
	return bool(node.is_deafened())


func _read_mic_badge() -> int:
	"""
	The local microphone's badge state, or `MIC_BADGE_NONE`.

	`voice_chat.mic_badge()` already answers NONE off the web and outside a room,
	so this is only the `has_method` degrade: a build with no voice node at all
	(every desktop run, every headless check) draws no badge.
	"""
	var node := _voice_node()
	if node == null or not node.has_method("mic_badge"):
		return MIC_BADGE_NONE
	return int(node.mic_badge())


func _read_speaking(heroes: PackedStringArray, badge: int) -> int:
	"""
	A bitmask of the tiles whose hero's HOLDER is talking, bit i = tile i.

	Gated on `badge` rather than on a second room test: `mic_badge()` is NONE in
	exactly the cases there is no voice to indicate, so one query decides whether
	this row says anything about voice at all.
	"""
	if badge == MIC_BADGE_NONE or heroes.is_empty():
		return 0
	var node := _voice_node()
	if node == null or not node.has_method("is_hero_speaking"):
		return 0
	var mask: int = 0
	for i: int in heroes.size():
		if bool(node.is_hero_speaking(heroes[i])):
			mask |= 1 << i
	return mask


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


func hero_names() -> PackedStringArray:
	"""
	The roster this row is drawing, in `CHARACTERS` order — EMPTY with no player.

	Exists for `voice_chat.gd` (bead godot-test1-xtr.6), which needs the hero list
	to ask the lobby who HOLDS each one. It reads the same `_heroes` snapshot
	`_draw` does, so a caller can never be handed a name this row is not drawing.
	"""
	return _heroes


func tile_state(hero: String) -> int:
	"""
	That hero's tile state (the STATE_* consts), or `STATE_FREE` for a name this
	row is not drawing.

	Exists beside `tile_rect()` for the camera overlay: a picture drawn over a
	CAPTIVE tile hides the cell bars, which are the one state this row says with a
	SHAPE rather than a brightness. Reads the same `_states` snapshot `_draw` does.
	"""
	var index := _index_of(hero)
	if index < 0 or index >= _states.size():
		return STATE_FREE
	return _states[index]


func tile_rect(hero: String) -> Rect2:
	"""
	Where that hero's tile is ON SCREEN, in window pixels — an empty `Rect2` when
	the hero is not on this row (no player, or a name that is not in `CHARACTERS`).

	The arithmetic is `_draw`'s, moved into a helper both call, so the video
	overlay of bead godot-test1-xtr.6 can never drift from the tile it covers.

	THE TRANSFORM IS THE VIEWPORT'S FINAL ONE, NOT `get_screen_transform()` (bead
	godot-test1-xtr.10, and this was a shipped bug). `get_screen_transform()` is
	`get_viewport().get_popup_base_transform() * get_global_transform_with_canvas()`,
	and a Window that EMBEDS its subwindows answers IDENTITY for the first factor —
	which is the project default and is unconditional on the web export. So it hands
	back the rect in the 1920x1080 DESIGN space of the `canvas_items` stretch, with
	the stretch scale dropped, while the one caller (`voice_chat._poll_tiles`)
	divides by `get_window().size` — the canvas BACKING size in the browser. The
	fraction came out short by the whole stretch scale, and a teammate's camera
	landed above and left of the tile and smaller than it.
	`get_viewport().get_final_transform()` is the aspect-keep letterbox margin times
	that stretch, so the rect comes out in the same window pixels the divisor
	measures, on every stretch mode.

	CONSEQUENCE, and it is the reason the comments around the caller say what they
	say: the fraction the caller derives is NOT resize-invariant. A resize that
	keeps the window's ASPECT moves nothing (rect and window scale together), but
	one that changes it moves which axis BINDS the stretch — and under `keep` the
	letterbox margin with it — while the divisor changes on both axes. That is fine
	rather than a hole: `_poll_tiles` is change-gated at 5 Hz and pushes the new
	fraction within 200 ms, and the browser re-places the picture against the new
	canvas box on its own `resize` listener meanwhile.
	"""
	var index := _index_of(hero)
	if index < 0:
		return Rect2()
	var local := _tile_rect_local(index)
	# Outside the tree there is no screen to map onto and Godot logs an error for
	# asking — a headless harness reads the row's own arithmetic instead.
	if not is_inside_tree():
		return local
	var xform := get_viewport().get_final_transform() * get_global_transform_with_canvas()
	return Rect2(xform * local.position, xform.basis_xform(local.size))


func _index_of(hero: String) -> int:
	"""That hero's slot in the row this widget is drawing, or -1."""
	for i: int in _heroes.size():
		if _heroes[i] == hero:
			return i
	return -1


func _tile_rect_local(index: int) -> Rect2:
	"""One tile's rect in this control's own space. The row's ONE description."""
	return Rect2(
		Vector2(index * (TILE_SIZE + TILE_GAP), 0.0),
		Vector2(TILE_SIZE, TILE_SIZE)
	)


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
	# THE FILMS' FACE, not the engine's: Oswald Bold, tall and condensed, is what
	# makes a 13 px digit legible over a bright sky at all (bead y1o.24).
	var font: Font = HudTheme.heading_font()
	for i: int in _heroes.size():
		var hero := _heroes[i]
		var state: int = _states[i]
		var rect := _tile_rect_local(i)
		var tint: Color = HERO_COLORS.get(hero, FALLBACK_COLOR)

		# Backdrop, so a portrait with light edges still reads over a bright sky.
		draw_rect(rect, COLOR_BACKDROP)
		var portrait := _portrait(hero)
		if portrait != null:
			draw_texture_rect(portrait, rect, false)
		else:
			# Placeholder: the identity colour plus the hero's initial, drawn the
			# way ability_hud draws its labels (Oswald Bold, INK outline).
			draw_rect(rect, tint)
			_draw_initial(font, hero.substr(0, 1).to_upper(), rect)

		# Held and captive are both unavailable, so both take the veil; only
		# captivity adds the bars on top of it.
		if state == STATE_HELD or state == STATE_CAPTIVE:
			# `HudTheme.veil()` and not a const of our own: it is the palette's
			# answer to "you cannot have this", and the skill tree and the MP
			# panel will want the same grey-brown.
			draw_rect(rect, HudTheme.veil())
		if state == STATE_CAPTIVE:
			_draw_bars(rect)

		# Frame: the one amber accent for the body you are driving, a thin STEEL
		# frame for everyone else so the tiles stay separable against the sky.
		# The ring is FLAT amber and no longer lerped toward the hero tint — the
		# accent is rationed to one amber thing per screen region, and the tint
		# already has the whole placeholder tile to say who this is.
		if state == STATE_ACTIVE:
			draw_rect(rect, COLOR_ACTIVE_BORDER, false, ACTIVE_BORDER_WIDTH)
		else:
			draw_rect(rect, COLOR_FRAME, false, 1.0)

		# VOICE, and the two decisions are `badge_on_tile` / `deafen_on_tile` so a
		# self-check can drive them without a canvas. The mic badge is drawn FIRST
		# and the ring over it: the badge's dark backdrop reaches into the ring's
		# band at that corner, and the ring is the tile-level statement.
		var badge := badge_on_tile(i)
		if badge != MIC_BADGE_NONE:
			_draw_mic_badge(_badge_box(rect, true), badge)
		if deafen_on_tile(i):
			_draw_deafen_badge(_badge_box(rect, false))

		# The ring goes INSIDE the frame so it reads beside the active border
		# rather than replacing it; a captive tile keeps its bars, and the ring is
		# drawn over the veil so a HELD teammate talking still shows.
		if (_speaking & (1 << i)) != 0:
			var t: float = 0.5 - 0.5 * cos(TAU * float(_pulse) / float(RING_PULSE_STEPS))
			var ring := COLOR_SPEAKING
			ring.a = lerp(RING_ALPHA_MIN, RING_ALPHA_MAX, t)
			draw_rect(rect.grow(-RING_INSET), ring, false, RING_WIDTH)

		# The hotkey digit, top-left of the tile. A LABEL ONLY — this HUD binds
		# nothing and depends on no hotkey bead; the digits match the 1-4 order
		# the roster is already in.
		_draw_digit(font, str(i + 1), rect)


func _draw_initial(font: Font, letter: String, rect: Rect2) -> void:
	"""The placeholder's big centred initial: BONE on the hero tint, with the
	palette's INK outline — the world-side lettering contract (`HudTheme.OUTLINE_PX`)."""
	var font_size := int(TILE_SIZE * 0.6)
	var width := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	# Baseline placed so the cap-height block sits visually centred in the tile.
	var pos := rect.position + Vector2(
		(rect.size.x - width) * 0.5,
		rect.size.y * 0.5 + font_size * 0.36
	)
	font.draw_string_outline(get_canvas_item(), pos, letter, HORIZONTAL_ALIGNMENT_LEFT,
		-1, font_size, HudTheme.OUTLINE_PX * 2, HudTheme.INK)
	font.draw_string(get_canvas_item(), pos, letter, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, HudTheme.BONE)


func _draw_digit(font: Font, digit: String, rect: Rect2) -> void:
	"""The 1-4 hotkey hint in the tile's top-left corner."""
	var pos := rect.position + Vector2(3.0, DIGIT_FONT_SIZE + 1.0)
	font.draw_string_outline(get_canvas_item(), pos, digit, HORIZONTAL_ALIGNMENT_LEFT,
		-1, DIGIT_FONT_SIZE, HudTheme.OUTLINE_PX * 2, HudTheme.INK)
	font.draw_string(get_canvas_item(), pos, digit, HORIZONTAL_ALIGNMENT_LEFT, -1,
		DIGIT_FONT_SIZE, COLOR_DIGIT)


func badge_on_tile(index: int) -> int:
	"""
	The mic badge that tile draws, `MIC_BADGE_NONE` for none — `_draw`'s ONE
	decision, public so `hero_hud_selfcheck` can drive it (a `_draw` on a control
	outside the tree has no canvas item, so the painting itself is untestable
	headless and only this ladder can be measured).

	ONE badge on the row, never four, and it rides `_badge_index` rather than the
	ACTIVE state — see that var for why a room can legitimately have no ACTIVE
	tile while the microphone is very much live.
	"""
	if _mic_badge == MIC_BADGE_NONE or index != _badge_index:
		return MIC_BADGE_NONE
	return _mic_badge


func deafen_on_tile(index: int) -> bool:
	"""The headphone-slash, which rides the mic badge's tile and its liveness."""
	return _deafened and badge_on_tile(index) != MIC_BADGE_NONE


func _badge_box(rect: Rect2, left: bool) -> Rect2:
	"""One badge's square, in a bottom corner of the tile. Two axes, two corners."""
	var x := rect.position.x + BADGE_MARGIN if left \
		else rect.end.x - BADGE_SIZE - BADGE_MARGIN
	return Rect2(Vector2(x, rect.end.y - BADGE_SIZE - BADGE_MARGIN),
		Vector2(BADGE_SIZE, BADGE_SIZE))


func mic_badge_color(badge: int) -> Color:
	"""
	The colour one `MIC_BADGE_*` state is drawn in — a function rather than a
	dictionary so `hero_hud_selfcheck` can drive every state through the same
	mapping `_draw` uses, TX included (which is the shared speaking green).
	"""
	match badge:
		MIC_BADGE_TX:
			return COLOR_SPEAKING
		MIC_BADGE_MUTED:
			return COLOR_MIC_MUTED
		MIC_BADGE_DENIED:
			return COLOR_MIC_DENIED
		_:
			return COLOR_MIC_OFF


func _draw_mic_badge(box: Rect2, badge: int) -> void:
	"""
	A microphone, vertex-drawn: capsule, cradle, stem, base — plus a slash when
	the mic cannot transmit. No texture and no node, like every other mark on this
	row; at 15 px the shape carries as much as the colour does, which is what
	makes the badge readable for a player who cannot tell the red from the amber.
	"""
	var color := mic_badge_color(badge)
	var w := box.size.x
	var h := box.size.y
	var cx := box.position.x + w * 0.5
	draw_rect(box, COLOR_BADGE_BACKDROP)
	# The capsule, and the cradle that turns it into a microphone rather than a pill.
	draw_rect(Rect2(Vector2(cx - w * 0.15, box.position.y + h * 0.18),
		Vector2(w * 0.30, h * 0.34)), color)
	draw_arc(Vector2(cx, box.position.y + h * 0.50), w * 0.28, 0.0, PI, 6, color, 1.5)
	draw_line(Vector2(cx, box.position.y + h * 0.50 + w * 0.28),
		Vector2(cx, box.position.y + h * 0.82), color, 1.5)
	draw_line(Vector2(cx - w * 0.20, box.position.y + h * 0.82),
		Vector2(cx + w * 0.20, box.position.y + h * 0.82), color, 1.5)
	if badge == MIC_BADGE_MUTED or badge == MIC_BADGE_DENIED:
		_draw_slash(box, color)


func _draw_deafen_badge(box: Rect2) -> void:
	"""
	Headphones with a slash — the SECOND axis, and it gets its own corner rather
	than a fifth mic state because muting what you say and muting what you hear
	are independent and can both be true.
	"""
	var color := COLOR_MIC_MUTED
	var w := box.size.x
	var h := box.size.y
	var cx := box.position.x + w * 0.5
	var band_y := box.position.y + h * 0.55
	draw_rect(box, COLOR_BADGE_BACKDROP)
	draw_arc(Vector2(cx, band_y), w * 0.32, PI, TAU, 8, color, 1.5)
	for side: int in [-1, 1]:
		draw_rect(Rect2(Vector2(cx + float(side) * w * 0.32 - w * 0.08, band_y),
			Vector2(w * 0.16, h * 0.26)), color)
	_draw_slash(box, color)


func _draw_slash(box: Rect2, color: Color) -> void:
	"""The "not" stroke, on a dark backing so it stays visible across the glyph."""
	var a := box.position + box.size * 0.15
	var b := box.position + box.size * 0.85
	draw_line(a, b, Color(HudTheme.INK, 0.9), 3.5)
	draw_line(a, b, color, 1.5)


func _draw_bars(rect: Rect2) -> void:
	"""Cell bars across a captive hero's tile — the Commandos read, and the one
	state that gets a shape of its own rather than a brightness of its own."""
	var step := rect.size.x / float(BAR_COUNT + 1)
	for b: int in BAR_COUNT:
		var x := rect.position.x + step * float(b + 1)
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), COLOR_BARS,
			BAR_WIDTH)
