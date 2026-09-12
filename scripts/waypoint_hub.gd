extends Control
## ============================================================================
## THE WAYPOINT HUB — the enter edge that finds a circle, the only hand that
## lights a beam, and the travel panel that edge opens
## ============================================================================
## Epic `godot-test1-sc6`, beads .2 and .4. `.1` put eleven indigo rings in the world with
## their beams built and hidden and gave no hero any way to notice them. This is
## the noticing: a 5 Hz scan that latches when you step onto one, sets its bit,
## pops a card, plays a cue, tells the room — and, every tick, drives every loaded
## beam's `visible` off the found mask.
##
## IT IS `landmark_toast.gd` ONE FEATURE ALONG and it is written to be read beside
## it. The throttled tick, the re-arm-first ordering, the nearest-in-range latch
## and the dead band are that file's, term for term, and the reasoning behind each
## is there in full (`_scan`, `landmark_toast.gd:619-700`) rather than repeated
## here. What is different is listed below, and only that.
##
## ----------------------------------------------------------------------------
## ONE WRITER FOR EVERY BEAM, AND IT IS THIS TICK
## ----------------------------------------------------------------------------
## Nothing else in the game ever touches a beam's `visible`. That is what makes
## three otherwise awkward things free:
##
##   * A TEAMMATE'S FIND LIGHTS IT HERE. The `wp` verb ORs into the player's mask
##     (`MpManager._apply_waypoints`) and this tick reads the mask — so a circle
##     found 2 km away is a pillar of light on the next tick with no packet
##     reaching this file and no registry of markers to keep in step.
##   * A CHUNK THAT STREAMS BACK IN LIGHTS ITSELF. Markers are chunk-parented and
##     freed with their chunk (`TerrainWaypoints._build_ring`), so a rebuilt one
##     arrives with `visible = false` off the constructor and is corrected within
##     200 ms. A one-shot "light it now" call could not do that without a registry
##     that outlives the node it names.
##   * TRAVEL (.3) NEEDS NO NEW NOTIFICATION. Relocating the world frees every
##     marker and builds new ones; this tick repaints them.
##
## The pass walks the "waypoint" group, which holds AT MOST TWO nodes in practice
## (eleven circles in the world, 49-121 chunks loaded, and they are hundreds of
## metres apart), so it is a plain loop with no index.
##
## ----------------------------------------------------------------------------
## THE TOAST IS THE FINDER'S ALONE — OWNER RULING, 2026-09-12
## ----------------------------------------------------------------------------
## Verbatim, on the architect's seventh question: *"teammate's find lights the
## beam, no toast"*. That falls out of the shape rather than needing a rule: the
## card is raised on THIS peer's enter edge and only when `activate_waypoint()`
## reports the bit was new, so a bit that arrived over the wire has nobody
## standing on anything and raises nothing. The beam pass below is the only thing
## a relayed find reaches.
##
## The consequence, stated because it is deliberate and not an oversight: walking
## onto a circle a teammate already found is SILENT — no card, no cue, and nothing
## published. It is not your discovery, and the epic's set is the crew's.
##
## ----------------------------------------------------------------------------
## WHY THE TRIGGER IS BIGGER THAN THE PAINT
## ----------------------------------------------------------------------------
## The disc is `RING_RADIUS` (2.6 m) and `APPROACH_PAD` adds three more. That is
## not generosity, it is the tick: a sampled scan can only see where you were at
## each tick, and Windman's air rush moves `WINDMAN_AIR_SPEED` (25 m/s) — 5 m per
## 200 ms tick. A path that crosses the painted disc therefore has a sample within
## `RING_RADIUS + 2.5 m` of the centre, so a pad at or above half the per-tick
## step is what makes "stepped on it" impossible to sprint or fly past. Three is
## that bound with slack.
##
## `LEAVE_PAD` is strictly larger, which is the dead band — `landmark_toast`'s
## hysteresis discipline, and the same one `crocodile_lod_manager` keeps between
## its sleep and wake radii.
##
## ----------------------------------------------------------------------------
## THE FLAT RULE
## ----------------------------------------------------------------------------
## Distances are XZ, `landmark_toast._xz_distance`'s reason: the world is flat and
## the circle is 8 cm proud of it, so a y-aware distance would refuse to fire for
## a hero standing on a bridge deck over the circle... and equally would fire for
## one flying 20 m above it. Both are the flat rule doing what the rest of this
## project's proximity tests do; a hero at altitude over a waypoint is a hero who
## walked to that waypoint.
##
## ----------------------------------------------------------------------------
## AND THE TRAVEL PANEL, GROWN ONTO THE SAME NODE (bead .4)
## ----------------------------------------------------------------------------
## The panel opens on the ENTER EDGE above and closes when the latch lets go, so
## it is a reader of exactly the event `_scan()` already computes. A second node
## would have to re-derive that edge from `standing_on()` polled at its own rate,
## and the two would disagree for a tick every time — which on this feature means
## a panel that opens a beat after the card or hangs on past the circle.
##
## DIABLO'S RULE, AND THE OWNER'S (2026-09-12): there is NO KEY and NO OPENER
## BUTTON. You stand on a found circle and the list is there; you walk off it and
## it is gone. That is worth stating as the absence it is — nothing to reserve
## against `city_map_selfcheck` check 1, nothing to place in
## `skill_tree_ui.gd`'s touch column, and one fewer gesture to explain.
##
## Everything about the CARD is `city_map_panel.gd`'s, term for term, and is not
## re-argued here: `HudTheme.theme()` on this node's own root, the
## `CenterContainer` backdrop that closes on a tap, the `MOUSE_FILTER_STOP` card,
## `FOCUS_NONE` on every button (`ui_accept` is Space is `jump`), `ui_cancel`
## handled only while open, and `_apply_pause()` re-asserted from `_process`.
## The PAUSE POLICY is that file's too — solo yes, in a room no, over Game Over
## no — and its reasons are written out at `_apply_pause()` below.
##
## WHAT IS ON IT: one row per FOUND circle, in index order, with the distance
## from the hero right-aligned; the row you are standing on is listed and
## DISABLED (it is where you are, not somewhere to go); a row you cannot afford
## is disabled too, over a line that says what the fare is. A press calls
## `PlayerController.travel_to_waypoint()` and the panel is gone.
## `ponytail:` a LIST and not a drawn road strip — a strip is eleven dots on a
## line for eleven places, and it would need its own projection, its own scale
## and its own self-check to say less than the names do. Draw one if the count
## ever outgrows a column (epic open question 5).
##
## Built as ONE NODE with ONE SCRIPT LINE in `scenes/main.tscn`. Until bead .4 it
## had no layout at all; the tick and the group lookup are still the whole of the
## file's world-facing half, and the card below only ever exists while a hero is
## standing on a circle.

## The end of every proximity tick, in seconds. 5 Hz — the bead's number and
## `minimap_hud`'s cadence. See the trigger-size note above for what it costs the
## pads.
const TICK_INTERVAL: float = 0.2

## Metres added to `TerrainWaypoints.RING_RADIUS` to get the trigger distance, and
## strictly less than `LEAVE_PAD`. See "WHY THE TRIGGER IS BIGGER THAN THE PAINT".
const APPROACH_PAD: float = 3.0

## Metres beyond the ring at which the latch RE-ARMS. Strictly greater than
## `APPROACH_PAD`, which is what makes the pair a dead band rather than a
## boundary to flicker across.
const LEAVE_PAD: float = 7.0

## The two `assets/translations/ui.csv` KEYS the discovery card shows. They are
## handed to `landmark_toast.announce()` RAW, never through `tr()`: that function
## puts them straight on a `Label`, and in this project the translation key IS the
## English source string, so `Control`'s own auto-translation does the work and
## re-does it live on a locale switch (CLAUDE.md Localization RULE 1, and
## `landmark_toast`'s docstring at its `announce`).
const FOUND_TITLE: String = "Waypoint found"
const FOUND_BODY: String = "Your crew can travel here now."

# ============================================================================
# THE TRAVEL PANEL — strings, layout and palette (bead .4)
# ============================================================================

## The fare, READ off the one file that bills it rather than restated here, so a
## retuned price changes the line the panel prints and the coins it checks in one
## edit. A parse-time reference in one direction only: `player_controller.gd`
## reaches this node through the `"waypoint_hub"` group and preloads nothing.
const PLAYER_SCRIPT: GDScript = preload("res://scripts/player_controller.gd")

## THE NAME OF EACH CIRCLE, by the `id` `TerrainWaypoints.waypoint_sites()` gives
## it. English IS the translation key (CLAUDE.md, Localization RULE 1), so these
## go onto a `Button.text` RAW and `Control`'s auto-translation does the rest —
## and re-does it live when the language changes under an open panel.
##
## THE TABLE LIVES HERE AND NOT IN `terrain_waypoints.gd` because a name is the
## only thing about a waypoint that is HUD: that family says where the circles
## are and what they are called on the wire (`id`), this file is the one surface
## that ever spells one out for a player. Two of the five city rows borrow a name
## the landmark table already ships ("Hungarian Parliament", "Great Market Hall")
## rather than inventing a synonym for the same building.
##
## THE ROAD ROWS ARE NOT IN IT: there are `road_slots()` of them, their number is
## arithmetic over two constants, and naming them one by one would be a second
## place to edit the day `WAYPOINT_SPACING` moves. They compose out of
## `ROAD_NAME` instead — see `site_name()`.
const SITE_NAMES: Dictionary = {
	"hq": "HQ gate",
	"approach": "HQ approach",
	"spawn": "The spawn",
	"gate": "Budapest gate",
	"pest": "Pest embankment",
	"parliament": "Hungarian Parliament",
	"market": "Great Market Hall",
	"heroes": "Heroes' Square",
}

## The composed lines, every one of them run through `tr()` at the format string
## (Localization RULE 2) and measured in German by `locale_selfcheck`.
##
## `ROAD_NAME` takes the slot's AUTHORED target X — `slot * WAYPOINT_SPACING` —
## and not the station the circle actually snapped to: the label is a name ("the
## one at 450 m"), the distance column beside it is the measurement, and a name
## that shifted by a few metres between runs would be a worse name for it.
const ROAD_NAME: String = "Road, %d m"
## The right-hand column. It still goes through `tr()` at the format string like
## every other composed line, and it deliberately has NO `ui.csv` ROW: German
## spells it the same, and `locale_selfcheck._check_translations` fails a row
## whose two columns match — its comment says such a key belongs out of the table,
## where a miss already falls back to the English text. `waypoint_panel_selfcheck`
## check (d) names it as the one exemption from its German sweep.
const DISTANCE_LINE: String = "%d m"
## The right-hand column of the row you are standing on, in place of a distance
## of zero — which would read as a place to travel to that happens to be close.
const HERE_LINE: String = "You are here"
## The fare line, and it is `player_controller`'s OWN refusal string: the card a
## too-poor traveller gets says exactly this, so the panel and the refusal cannot
## drift into quoting two different prices.
const PRICE_LINE: String = "Travel costs %d coins."
## Shown when the crew has found this circle and no other — the state every run
## starts in, and the one that has to teach the mechanic rather than look broken.
const EMPTY_LINE: String = "No other waypoint found yet."
const CLOSE_HINT: String = "Press Esc or tap outside to close"

## The card's CONTENT width, in layout units. Fixed rather than content-sized so
## a long German name cannot widen the panel off a 400-unit phone screen.
##
## IT IS THE CONTENT AND NOT THE CARD, and the difference is the whole reason
## this number is 336 (review, 2026-09-12): `HudTheme.card()` puts
## `HudTheme.CARD_PADDING` (12) of content margin on all four sides, so the card
## DRAWS at 336 + 24 = 360 and leaves 20 units of gutter either side of a 400.
## `waypoint_panel_selfcheck` check (f) measures the drawn rect at 1280x720 and
## 400x800 rather than trusting this comment — it is what caught the first
## version, which added a `MarginContainer` of its own on top of the theme's and
## drew 384 wide inside a 400-unit screen.
const CARD_WIDTH: float = 336.0
const TITLE_FONT_SIZE: int = 26
const ROW_FONT_SIZE: int = 16
## A row's minimum height, in layout units. Named rather than left to the
## Button's own text metrics, because on a phone this list is the only way to use
## the feature and a row has to be a thumb target.
##
## 36 AND NOT 44, AND THE CEILING IS THE ONE THAT MOVED IT (review, 2026-09-12).
## Eleven rows is the whole world's supply and they are all on this card at once:
## at 44 the card measured 711 units tall, which does not fit a 720-tall screen
## with a gutter — `waypoint_panel_selfcheck` check (f) caught it at both sizes.
## 36 brings the worst case to ~620. It is not a small target either: the touch
## build magnifies the layout by `TouchControls.TOUCH_CONTENT_SCALE` (1.8), so
## this is 65 device pixels on the screen that needs it.
## `ponytail:` the ceiling is the row COUNT — a twelfth circle puts the card back
## over a 720-tall screen, and check (f) is what will say so. The upgrade then is
## a `ScrollContainer` round `_rows_box`, not a smaller row.
const ROW_HEIGHT: float = 36.0
const LINE_FONT_SIZE: int = 15
const HINT_FONT_SIZE: int = 13
## Pixels of the row reserved for the right-hand column, and therefore NOT
## available to the name. `locale_selfcheck` budgets both halves against it.
const DISTANCE_WIDTH: float = 110.0
## Usable width a row's NAME has: the card's content, less the theme Button's own
## content padding, less the column above.
const NAME_WIDTH: float = CARD_WIDTH - 2.0 * HudTheme.CARD_PADDING - DISTANCE_WIDTH

## The card's chrome, off `HudTheme` and with no hex of its own —
## `hero_hud_selfcheck` greps for a second copy of the six palette values.
const COLOR_TITLE: Color = HudTheme.BONE
const COLOR_TEXT: Color = HudTheme.BONE
const COLOR_HINT: Color = HudTheme.UNIT_KHAKI
## The distance column: BONE on a row you can take, the disabled Button's own
## khaki on one you cannot, so the two halves of a greyed row grey together.
const COLOR_DISTANCE: Color = HudTheme.BONE
const COLOR_DISTANCE_OFF: Color = HudTheme.UNIT_KHAKI
## The 1 px rule under the heading — `city_map_panel`'s and `tower_lift_menu`'s
## one `ColorRect`, still not worth a `HudTheme` builder at three callers.
const RULE_PX: float = 1.0

## The circle this approach belongs to, as an index into
## `TerrainWaypoints.waypoint_sites()`, or -1 when re-armed. `landmark_toast`'s
## `_city_active` exactly — including why the FIRST arrival is latched rather than
## the nearest one winning every tick.
var _standing_on: int = -1

## Seconds accumulated toward the next tick.
var _tick_timer: float = 0.0

# --- The panel (bead .4) ----------------------------------------------------
var _panel_open: bool = false
## Whether the CURRENT tree pause is ours to release. "We hold A claim", not "we
## hold THE pause" — see `pause_hub.gd`'s header.
var _paused_by_us: bool = false
## Whether the list was closed by the HERO'S STATE rather than by the hero, and so
## is owed back when that state clears. Set only in `_tick`, cleared by every
## deliberate open or close (`set_panel_open`) — which is what keeps Esc, a
## backdrop tap and a press from being undone one tick later.
var _closed_by_state: bool = false

## Child nodes, built in `_ready` rather than from a `.tscn`, `city_map_panel`'s
## shape: this node is one script line in `main.tscn` and has to stay that way.
var _centre: CenterContainer = null
var _card: PanelContainer = null
var _rows_box: VBoxContainer = null
var _empty_label: Label = null
var _price_label: Label = null
var _hint_label: Label = null
## One row per MASK BIT, built once and never rebuilt — `visible` is what says
## whether the crew has found that circle. A rebuild per refresh would throw away
## the button under the finger that is pressing it, and at 5 Hz.
var _rows: Array[Button] = []
var _row_distances: Array[Label] = []


func _ready() -> void:
	# Must keep running under its own pause, like every other always-available HUD
	# piece — `_apply_pause()` is re-asserted from `_process` and could not be.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# This Control draws nothing itself and must never eat a click: the MP panel,
	# the touch buttons and the start overlay share this CanvasLayer, and a Control
	# over them that swallowed input would be invisible and maddening. The panel's
	# own backdrop is STOP, but only while it is visible.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# FULL RECT, and it is the panel that needs it: until bead .4 this node drew
	# nothing and its own zero-sized rect cost nothing, but the backdrop below
	# anchors to it and a `CenterContainer` inside a 0x0 parent centres the card in
	# the top-left corner. Harmless with MOUSE_FILTER_IGNORE above — a full-screen
	# Control that takes no input is exactly what every other HUD root here is.
	# ...AND THE OFFSETS WITH THE ANCHORS: `main.tscn` gives this node no layout at
	# all, so anchors alone would leave a 0x0 rect stretched over nothing and the
	# card would still be drawn in the corner.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# So the travel panel — and `PlayerController.travel_to_waypoint()` — can ask
	# where the hero is standing without a hard reference; group discovery, like
	# every other cross-system hookup here.
	add_to_group("waypoint_hub")
	_build_ui()


func standing_on() -> int:
	"""
	The waypoint circle the hero is currently on, or -1 when they are on none.

	@return: an index into `TerrainWaypoints.waypoint_sites()`.

	PUBLIC AND KEPT BY NAME: bead .4's travel panel opens on this and closes when
	it goes back to -1, which is the epic's "travel only while standing on a found
	circle" (owner ruling 2026-09-12) with no key to reserve and no opener to add.
	It is the LATCH, so it carries the dead band with it — the panel inherits the
	hysteresis for free instead of flickering on the trigger boundary.

	IT IS A POSITION AND NOT A PERMISSION. This answers "which circle is under the
	hero", NOT "may they travel from it": a circle found by nobody still latches
	here, because the latch is what raises the card in the first place. `.3`'s
	`travel_to_waypoint()` and `.4`'s panel must AND this against the player's own
	`waypoint_mask` — the epic's rule is "standing on a FOUND circle", and the
	found half lives on the player where the room writes it.
	"""
	return _standing_on


func arrived_at(index: int) -> void:
	"""
	Latch the hero onto circle `index` WITHOUT an enter edge.

	@param index: the circle they were just put down on, or -1 to re-arm.

	THE ONE CALLER IS `PlayerController.travel_to_waypoint()` (bead
	godot-test1-sc6.3), at the very end of the hop, and what it buys is the
	absence of a second event. Travel puts the body down inside the target ring,
	so the next `_scan()` would see a fresh arrival and fire the enter edge —
	which would pop the find card for a circle that was found long ago (it cannot
	be travelled to otherwise) and, from `.4`, re-open the travel panel the hero
	just used. Latching it here makes the landing a CONTINUATION of standing on
	that circle rather than a new arrival, which is what it is.

	NO BIT IS SET AND NO CARD IS RAISED: this is the position, not the discovery
	(see `standing_on()`), and travel can only reach a circle already found.

	IT CAN BE UNDONE 200 ms LATER, and that is honest rather than a bug: the
	landing spot is `PlayerController._place_near()`'s, which probes outward
	through `JOIN_RING_RADII` (3, 5, 8, 12 m) for a body-sized gap and takes the
	first ring that has one. The first ring almost always does — a circle's ground
	is clear by construction — but a blocked one can push the landing past
	`RING_RADIUS + LEAVE_PAD` (9.6 m), and the next tick's re-arm then measures
	the real distance and drops the latch. The hero is simply standing a few steps
	off the circle at that point, which is what the re-arm is for; they walk back
	on and the ordinary enter edge latches it again.
	"""
	_standing_on = index


func _process(delta: float) -> void:
	# Re-assert the pause every frame while the panel is up, for `mp_ui`'s reason:
	# the claim is DECLINED in a room and over Game Over, so a state change under
	# an open panel must not strand the world in the wrong one.
	_apply_pause(_panel_open)
	_tick_timer += delta
	if _tick_timer < TICK_INTERVAL:
		return
	_tick_timer = 0.0
	_tick()


func _tick() -> void:
	"""
	One pass: the enter edge, then every loaded beam.

	THE BEAM PASS RUNS WHATEVER HAPPENED ABOVE, including when there is no player
	and no terrain — that is what makes a scene with neither (a self-check, a
	standalone terrain scene) show eleven dark circles rather than whatever the
	last frame left, and it is the degrade CLAUDE.md's group discovery asks for.

	THE PANEL FOLLOWS THE LATCH AND NOT THE OTHER WAY ROUND (bead .4). Opening is
	the ENTER EDGE's business, down inside `_scan()`; closing is one line here,
	because every way the latch can let go — walking off, the player going away,
	the terrain going away, the table shrinking under a re-seed — has to close it,
	and listing them at each site is how one gets missed.
	"""
	# Cast, don't assume: a bare Node somebody added to "player" must be ignored,
	# not error on `global_position` (`landmark_toast._scan`'s first line).
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var mask: int = 0
	if player == null:
		# No local player: re-arm, so the next one to appear gets a fresh approach.
		_standing_on = -1
	else:
		# THE SCAN RUNS FIRST AND THE MASK IS READ AFTER IT, which is one line of
		# ordering and 200 ms of polish: a find made by THIS tick's enter edge must
		# light its own beam on the tick that popped its card, not on the next one.
		_scan(player)
		if "waypoint_mask" in player:
			mask = int(player.waypoint_mask)
	_paint_beams(mask)
	# THE CLOSE EDGE, AND IT IS EVERY WAY THE LIST CAN STOP BEING ALLOWED — not
	# only walking off. `_open_panel_for()` refuses to OPEN over a respawn, a bite
	# or Game Over; without the same question asked here, a state that flips UNDER
	# an open list leaves it up. That is reachable and it is ugly: in a room this
	# panel takes no pause, so the world keeps running under it — a hero grabbed
	# while reading the list goes to Game Over with the card still drawn, and this
	# node now sits above `GameOver` in `main.tscn`, so it would cover Play Again.
	if _standing_on < 0:
		# Walked off. The list is simply gone, and nothing is owed.
		set_panel_open(false)
	elif _hero_unavailable(player):
		# ...BUT REMEMBER IT, because two of those three states CLEAR again and a
		# one-way close is its own dead end (review round 2). A soft respawn lasts
		# `RESPAWN_GRACE_DURATION` and leaves the hero standing on the same circle:
		# without this the list is gone until they step off and back on, which is
		# exactly the trap `_on_row_pressed()` refuses to leave behind for a refused
		# hop.
		#
		# READ BEFORE `set_panel_open()` AND WRITTEN AFTER IT: that function wipes
		# the memory (a deliberate close must never be undone), and the grace lasts
		# many ticks — only the first of them finds the panel open, so a memory
		# recomputed from `_panel_open` alone would be wiped by the second tick.
		var owed: bool = _closed_by_state or _panel_open
		set_panel_open(false)
		_closed_by_state = owed
	elif _panel_open:
		# Distances, affordability and a teammate's fresh find, on the tick the
		# rest of this feature already runs at.
		_refresh_rows()
	elif _closed_by_state:
		# The state cleared and the hero never left the circle: give it back. Cleared
		# FIRST so a refusal inside `_open_panel_for` is one attempt and not a retry
		# every 200 ms.
		_closed_by_state = false
		_open_panel_for(_standing_on, player)


func _hero_unavailable(player: Node) -> bool:
	"""
	Whether the body is in a state where a travel list may not be on screen.

	THE THREE ARE `PlayerController.travel_to_waypoint()`'s OWN first refusal
	(`is_respawning or is_caught or is_game_over`), read here so the panel and the
	primitive cannot disagree about who may travel. Each is a different damage:
	a respawn is moving the body this list would move, a bite freeze is PAUSABLE
	and solo this panel's pause would stop its own timer running out, and over Game
	Over the only thing that may be on screen is Play Again.

	Every read is gated by `flag in player` before `player.get(flag)`: `get()`
	answers null for a property that is not there and `bool(null)` is a hard error,
	so a scene whose "player" is a stand-in degrades instead of throwing.
	"""
	if player == null:
		return true
	for flag: String in ["is_respawning", "is_caught", "is_game_over"]:
		if flag in player and bool(player.get(flag)):
			return true
	return false


func _scan(player: Node3D) -> void:
	"""
	The enter edge: re-arm first, then latch the nearest circle in range, and pay a
	brand-new one its find.

	`landmark_toast._scan_city()`'s shape term for term — re-arm first so walking
	out can never block the next arrival, nearest-in-range wins, the FIRST arrival
	latches. The two departures are that the table comes from
	`TerrainWaypoints.waypoint_sites()` (there are no marker nodes to walk: a
	circle exists whether or not its chunk is loaded, exactly as a
	`BudapestPlan.SLOTS` row does) and that every circle shares one radius.
	"""
	var terrain := get_tree().get_first_node_in_group("terrain") as Node3D
	# The sites are STATIC ON `TerrainWaypoints` and called directly rather than
	# through a forwarder on the terrain — a HUD node is not a terrain family, so
	# CLAUDE.md's one-direction rule between families does not bind it. What the
	# guard is for is the NODE: the table reads `tower_site()`, the road station
	# cache and `is_river_at` back off it, so a "terrain" that is not an
	# `EndlessTerrain` must read as "no waypoints here", never as an error.
	if terrain == null or not terrain.has_method("tower_site"):
		_standing_on = -1
		return
	var sites: Array[Dictionary] = TerrainWaypoints.waypoint_sites(terrain)
	var origin: Vector3 = player.global_position

	# RE-ARM FIRST. The bounds test beside it is not paranoia: `.3` relocates the
	# world and a future wave may retune `WAYPOINT_SPACING`, either of which can
	# shorten the table under a latch taken against the old one.
	if _standing_on >= 0:
		if _standing_on >= sites.size():
			_standing_on = -1
		elif _xz_distance(origin, sites[_standing_on]["pos"] as Vector3) \
				> TerrainWaypoints.RING_RADIUS + LEAVE_PAD:
			_standing_on = -1

	var nearest: int = -1
	var nearest_distance: float = INF
	for i in sites.size():
		var distance: float = _xz_distance(origin, sites[i]["pos"] as Vector3)
		if distance >= TerrainWaypoints.RING_RADIUS + APPROACH_PAD:
			continue
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = i

	# ONE APPROACH AT A TIME. Two circles can never overlap in this world (the
	# nearest pair is hundreds of metres apart), so this guard is not load-bearing
	# the way `landmark_toast`'s is — it is the same rule kept for the same reason
	# a latch exists at all: the enter EDGE is the event, not the presence.
	if _standing_on >= 0 or nearest < 0:
		return
	_standing_on = nearest
	_arrive(nearest, player)
	# AND THE PANEL, AFTER THE FIND AND NOT BEFORE IT: `_arrive()` is what sets a
	# brand-new circle's bit, and the rule below is "open onto a circle whose bit
	# is set" — so a first visit activates and then opens in the one tick, which is
	# the card and the list arriving together.
	_open_panel_for(nearest, player)


func _arrive(index: int, player: Node3D) -> void:
	"""
	The hero stepped onto circle `index`. Set the bit, and if it was new, pay the
	find: the card, the cue and the room.

	THE ORDER IS THE ROOM'S. `activate_waypoint()` is what decides whether this was
	a discovery at all — it refuses a bit already set, whether this peer set it by
	walking or the room set it over the wire — so everything below hangs off its
	answer and a teammate's circle is silent (owner ruling, see the banner).

	THE PUBLISH IS LAST AND UNCONDITIONAL-ON-NEW, never on being in a room: the
	manager is what knows whether there is a room, and asking here would be a
	second copy of that question.
	"""
	if not player.has_method("activate_waypoint"):
		return
	if not player.call("activate_waypoint", index):
		return

	# The card. Two CSV keys, raw — see FOUND_TITLE.
	var toast := get_tree().get_first_node_in_group("landmark_toast")
	if toast != null and toast.has_method("announce"):
		toast.call("announce", FOUND_TITLE, FOUND_BODY)

	# The cue — bead .5's own, no longer the borrowed `play_level_up`: three rising
	# taps of the coin buffer, a major triad against the level-up's bare fifth (see
	# `SoundManager.WAYPOINT_FOUND_PITCHES`). The project's standard null-safe
	# group + has_method shape, so a scene with no SoundManager resolves silently.
	var sound := get_tree().get_first_node_in_group("sound_manager")
	if sound != null and sound.has_method("play_waypoint_found"):
		sound.call("play_waypoint_found")

	# And the room. A no-op offline and off an unfinished mesh alike — see
	# `MpManager.publish_waypoint_found()`, which owns both.
	var mp := get_tree().get_first_node_in_group("mp")
	if mp != null and mp.has_method("publish_waypoint_found"):
		mp.call("publish_waypoint_found", index)


func _paint_beams(mask: int) -> void:
	"""
	Every loaded circle's beam: lit exactly when its bit is set.

	IDEMPOTENT AND UNCONDITIONAL, which is the point — see "ONE WRITER FOR EVERY
	BEAM" in the banner. Assigning `visible` to the value it already holds costs
	nothing in Godot (the setter early-outs), so there is no "has it changed"
	bookkeeping here and nothing to go stale.

	A marker with no beam, or one whose index meta is missing, is SKIPPED rather
	than fatal: this tick runs in every scene, including ones where somebody has
	put a bare Node3D in the group.
	"""
	for node in get_tree().get_nodes_in_group(TerrainWaypoints.WAYPOINT_GROUP):
		var marker := node as Node3D
		if marker == null:
			continue
		var beam := marker.get_node_or_null(
				NodePath(TerrainWaypoints.WAYPOINT_BEAM_NAME)) as MeshInstance3D
		if beam == null:
			continue
		var index: int = int(marker.get_meta("index", -1))
		if index < 0 or index >= TerrainWaypoints.WAYPOINT_COUNT:
			continue
		beam.visible = mask & (1 << index) != 0


func _xz_distance(a: Vector3, b: Vector3) -> float:
	"""Flat XZ distance — `landmark_toast._xz_distance`, and see THE FLAT RULE."""
	return Vector2(a.x - b.x, a.z - b.z).length()


# ============================================================================
# THE TRAVEL PANEL — OPEN AND CLOSE (bead .4)
# ============================================================================

func is_panel_open() -> bool:
	return _panel_open


func _open_panel_for(index: int, player: Node3D) -> void:
	"""
	The enter edge's other half: show the list, unless one of four states says no.

	@param index: the circle just latched, as a `waypoint_sites()` index.
	@param player: the local hero — already cast by `_scan()`.

	THE BIT IS THE PERMISSION. `standing_on()` is a POSITION and not a permission
	(its docstring), so the panel asks the player's OWN `waypoint_mask` whether
	this circle has been found. In the shipped game a first visit has just set it
	one call up; a mask that is still clear here means the "player" in the group
	cannot find circles at all, and a list of places to travel between would be a
	lie drawn over it.

	THE OTHER REFUSALS are ones every panel in this project carries. Three of them
	are `_hero_unavailable()` — the primitive's own first refusal, shared so the
	panel and `travel_to_waypoint()` cannot disagree about who may travel, and
	re-asked every tick because a state that flips under an open list must close
	it. The fourth is a pending landmark quiz, which owns the digits and its own
	pause (`landmark_toast`); it is asked only here because a quiz cannot start
	under this panel — it is raised by walking into a landmark, and this one is
	modal over the whole screen while it is up.
	"""
	if _panel_open:
		return
	if not ("waypoint_mask" in player) or int(player.waypoint_mask) & (1 << index) == 0:
		return
	if _hero_unavailable(player):
		return
	var toast := get_tree().get_first_node_in_group("landmark_toast")
	if toast != null and toast.has_method("is_quiz_pending") \
			and bool(toast.call("is_quiz_pending")):
		return
	set_panel_open(true)


func set_panel_open(open: bool) -> void:
	"""Show or hide the list. The ONE path in and out, so the pause claim cannot
	be taken on one route and left behind on another."""
	# ANY DELIBERATE OPEN OR CLOSE CANCELS THE DEBT. Esc, a backdrop tap and a row
	# press all come through here, and none of them may be undone by `_tick`
	# re-opening what the player just dismissed. `_tick` re-arms it after its own
	# call, which is the one close that IS owed back.
	_closed_by_state = false
	if open == _panel_open:
		return
	_panel_open = open
	if open:
		_refresh_rows()
	if _card != null:
		_card.visible = open
	# The backdrop goes with the card: hidden it takes no clicks, shown it is what
	# a tap-to-close lands on.
	if _centre != null:
		_centre.visible = open
	_apply_pause(open)


func _on_backdrop_input(event: InputEvent) -> void:
	"""A tap anywhere outside the card closes the list. The card itself is
	MOUSE_FILTER_STOP, so a tap ON it never reaches here."""
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_centre.accept_event()
		set_panel_open(false)


func _unhandled_input(event: InputEvent) -> void:
	# Esc closes, and ONLY while we are open — otherwise this eats the `ui_cancel`
	# `player_controller._input()` uses to release the mouse. `skill_tree_ui`'s
	# guard, for `skill_tree_ui`'s reason. There is no other key here: the circle
	# is the opener (see the banner).
	if event != null and _panel_open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		set_panel_open(false)


func _exit_tree() -> void:
	# Never leave the world frozen behind a node that is going away.
	_apply_pause(false)


func _apply_pause(open: bool) -> void:
	"""
	Take or give back the pause for the panel's current state, or decline it.

	`PauseHub.take()` / `PauseHub.release()`, never `get_tree().paused` — the one
	rule `pause_selfcheck` check 3 scans every script in this directory for. The
	POLICY stays here with the feature, exactly as the hub's header says it must,
	and it is `city_map_panel`'s and `landmark_toast`'s:

	  * IN A ROOM this freezes NOTHING. `get_tree().paused` is local and the
	    simulation is not, so a peer reading the travel list while three teammates
	    run from a hunter would either desync itself or ask them to stand still.
	  * OVER GAME OVER it freezes nothing either: `GameOverUI` is PAUSABLE, so a
	    pause there kills its Play Again button.
	"""
	if not open and not _paused_by_us:
		return  # The overwhelmingly common case: closed panel, nothing to undo.
	var tree := get_tree()
	if tree == null:
		return
	var want: bool = open and not _in_room() and not _game_over()
	if want and not _paused_by_us:
		PauseHub.take(self)
		_paused_by_us = true
	elif not want and _paused_by_us:
		_paused_by_us = false
		PauseHub.release(self)


func _in_room() -> bool:
	"""Is this peer engaged with the lobby at all? `is_busy()`, not `is_online()`:
	a join in flight is already a session somebody else's frames belong to."""
	var tree := get_tree()
	if tree == null:
		return false
	var mp: Node = tree.get_first_node_in_group("mp")
	return mp != null and mp.has_method("is_busy") and bool(mp.is_busy())


func _game_over() -> bool:
	# `"x" in node`, not `node.get("x")`: `get()` answers null for a missing
	# property and `bool(null)` is a hard error, so this is what lets a scene whose
	# player is a stand-in degrade instead of throwing.
	var tree := get_tree()
	if tree == null:
		return false
	var player: Node = tree.get_first_node_in_group("player")
	return player != null and "is_game_over" in player and bool(player.is_game_over)


# ============================================================================
# THE TRAVEL PANEL — CONTENT
# ============================================================================

static func site_name(id: String) -> String:
	"""
	What a circle is called on the list, ready to draw.

	@param id: the row's `id` from `TerrainWaypoints.waypoint_sites()`.
	@return: a plain name straight out of `SITE_NAMES` (a CSV key, which `Control`
	         translates for free) or a composed road label already through `tr()`.

	STATIC AND PUBLIC so `waypoint_panel_selfcheck` and `locale_selfcheck` can ask
	the shipped function what a row says instead of rebuilding the mapping — a
	second copy of it is exactly what would pass while the panel named the wrong
	places.
	"""
	if SITE_NAMES.has(id):
		return String(SITE_NAMES[id])
	if id.begins_with("road_"):
		var slot: int = int(id.substr(5))
		# `TranslationServer.translate()` and not `tr()`: this is static, and `tr()`
		# is a `Node` method. Same table, same answer — `Control.tr()` is a thin
		# wrapper over it — and it keeps the one mapping askable from a self-check.
		return TranslationServer.translate(ROAD_NAME) \
			% int(float(slot) * TerrainWaypoints.WAYPOINT_SPACING)
	# An id nobody named: show it rather than an empty button. Unreachable while
	# `SITE_NAMES` covers the table, which `waypoint_panel_selfcheck` check (b)
	# asserts against the real sites.
	return id


func _refresh_rows() -> void:
	"""
	Rewrite every row from the live world: which circles are found, how far each
	one is, and whether this hero can afford the fare.

	ONE ROW PER MASK BIT, BUILT ONCE (see `_rows`): this only ever writes `text`,
	`visible` and `disabled`, so a teammate's find arriving mid-tick does not
	rebuild the button under the player's finger. A row past `sites.size()` — a
	table that shrank under a re-seed — is hidden rather than left showing the
	last run's place.
	"""
	if _rows.is_empty():
		return
	var tree := get_tree()
	var player: Node = null if tree == null else tree.get_first_node_in_group("player")
	var terrain: Node3D = null
	if tree != null:
		terrain = tree.get_first_node_in_group("terrain") as Node3D
	var sites: Array[Dictionary] = []
	if terrain != null and terrain.has_method("tower_site"):
		sites = TerrainWaypoints.waypoint_sites(terrain)
	var mask: int = 0
	if player != null and "waypoint_mask" in player:
		mask = int(player.waypoint_mask)
	var coins: int = 0
	if player != null and "own_coins" in player:
		coins = int(player.own_coins)
	var origin := Vector3.ZERO
	if player is Node3D:
		origin = (player as Node3D).global_position
	# The fare is checked ONCE and not per row: it is the same for every hop.
	var affordable: bool = coins >= PLAYER_SCRIPT.TELEPORT_COIN_COST

	var elsewhere: int = 0
	for i in range(_rows.size()):
		var found: bool = i < sites.size() and mask & (1 << i) != 0
		_rows[i].visible = found
		if not found:
			continue
		var here: bool = i == _standing_on
		if not here:
			elsewhere += 1
		_rows[i].text = site_name(String(sites[i]["id"]))
		if here:
			_row_distances[i].text = HERE_LINE
		else:
			_row_distances[i].text = tr(DISTANCE_LINE) \
				% int(roundf(_xz_distance(origin, sites[i]["pos"] as Vector3)))
		# THE TWO REASONS A ROW IS DEAD, and they are deliberately one state: the
		# circle under your feet is not somewhere to go, and a hop you cannot pay
		# for is not one to offer. The theme greys a disabled Button's own label;
		# the distance column is a separate Label, so it is greyed here to match.
		_rows[i].disabled = here or not affordable
		_row_distances[i].add_theme_color_override("font_color",
			COLOR_DISTANCE_OFF if _rows[i].disabled else COLOR_DISTANCE)

	if _empty_label != null:
		_empty_label.visible = elsewhere == 0
	if _price_label != null:
		_price_label.text = tr(PRICE_LINE) % PLAYER_SCRIPT.TELEPORT_COIN_COST


func _on_row_pressed(index: int) -> void:
	"""
	One press, one hop.

	THE PANEL CLOSES FIRST, and that ordering is load-bearing rather than tidy:
	solo this node holds the pause, and `travel_to_waypoint()` awaits a physics
	frame in the middle of relocating the world. Handing the claim back before the
	hop starts means the world it lands in is running, with no window in which a
	frozen tree is halfway through a rebuild.

	...AND IT COMES BACK IF NOTHING HAPPENED. `travel_to_waypoint()` has refusals
	this list cannot see — a room that has not placed this body yet is the real
	one — and every one of them is SILENT but the coin case. Closing on a press
	that did nothing would leave a hero standing on a circle with no list and no
	explanation, and no way to get it back but walking off and back on, because
	the open is an edge. So the answer is awaited and a refused hop re-opens.

	`await player.call(...)` and not a bare call: `travel_to_waypoint()` is a
	coroutine, so a bare call answers a `GDScriptFunctionState` — an object, which
	is truthy, which would read as "it worked" for every refusal after the first
	physics wait. Awaiting the call yields the function's own `bool`.

	Group + `has_method`, so a scene whose "player" cannot travel simply closes.
	"""
	set_panel_open(false)
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("travel_to_waypoint"):
		return
	var moved: Variant = await player.call("travel_to_waypoint", index)
	# Only re-open onto the circle we are still standing on: the hop may have been
	# refused a whole second ago as far as the 5 Hz tick is concerned, and the hero
	# may have walked off in the meantime. Through `_open_panel_for()` rather than
	# `set_panel_open(true)`, so the mask and the four state refusals are re-asked.
	var body := player as Node3D
	if moved is bool and not bool(moved) and _standing_on >= 0 and body != null:
		_open_panel_for(_standing_on, body)


# ============================================================================
# THE TRAVEL PANEL — CONSTRUCTION
# ============================================================================

func _build_ui() -> void:
	# THE HUD SKIN, on THIS ROOT and nowhere else: the card's INK ground, its
	# STEEL frame and its hard shadow all arrive with it, which is why this panel
	# owns no `StyleBoxFlat` and no palette hex of its own.
	theme = HudTheme.theme()

	# A CenterContainer so the card sizes to its own content and stays centred at
	# any resolution — `city_map_panel`'s and `start_overlay`'s shape. HIDDEN while
	# the list is, and STOP while it is up: that is the backdrop, and a tap on it
	# closes. A hidden Control receives no input, so with the list down every click
	# still reaches the world beneath it.
	_centre = CenterContainer.new()
	_centre.name = "Centre"
	_centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	# ...AND THE COST OF A FULL-RECT BACKDROP, NAMED because it is a choice: while
	# the list is up nothing under it takes a tap, the touch joystick included. In
	# a room — where this panel deliberately takes no pause — that is a hero who
	# cannot move for exactly one tap, and the hint under the card says which tap.
	# It is `city_map_panel`'s and `skill_tree_ui`'s backdrop unchanged, and every
	# panel in `main.tscn`'s HUD after `TouchControls` already covers it the same
	# way; "tap outside to close" has no cheaper shape.
	_centre.mouse_filter = Control.MOUSE_FILTER_STOP
	_centre.visible = false
	_centre.gui_input.connect(_on_backdrop_input)
	add_child(_centre)

	_card = PanelContainer.new()
	_card.name = "Card"
	# STOP: while the list is up it swallows clicks, so a click meant to dismiss it
	# does not fire the desktop-web click-to-capture through it.
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.visible = false
	_centre.add_child(_card)

	# NO `MarginContainer` OF ITS OWN: `HudTheme.card()` already carries
	# `HudTheme.CARD_PADDING` of content margin on all four sides, and a second one
	# inside it was 36 units of width and 36 of height this card cannot spare —
	# see `CARD_WIDTH`. The width is set HERE, on the content, so the drawn card is
	# `CARD_WIDTH` plus the theme's margin and nothing else.
	var column := VBoxContainer.new()
	column.name = "Column"
	column.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	_card.add_child(column)

	# RULE 1: a plain literal on a Label, translated by the engine for free.
	var title := Label.new()
	title.name = "Title"
	title.text = "Waypoints"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", HudTheme.heading_font())
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	column.add_child(title)
	column.add_child(_rule())

	_rows_box = VBoxContainer.new()
	_rows_box.name = "Rows"
	column.add_child(_rows_box)
	for i in range(TerrainWaypoints.WAYPOINT_COUNT):
		_add_row(i)

	# The teaching line, shown when this circle is the only one the crew has found.
	# Its own Label rather than a row, so it cannot be mistaken for a place to press.
	_empty_label = Label.new()
	_empty_label.name = "Empty"
	_empty_label.text = EMPTY_LINE
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	_empty_label.add_theme_font_size_override("font_size", LINE_FONT_SIZE)
	_empty_label.add_theme_color_override("font_color", COLOR_TEXT)
	_empty_label.visible = false
	column.add_child(_empty_label)

	_price_label = Label.new()
	_price_label.name = "Price"
	_price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_price_label.add_theme_font_size_override("font_size", LINE_FONT_SIZE)
	_price_label.add_theme_color_override("font_color", COLOR_TEXT)
	column.add_child(_price_label)

	# RULE 1 again: a literal, set once. Nothing composes into it — there is no key
	# to name, which is the whole point of this panel's opener being the circle.
	_hint_label = Label.new()
	_hint_label.name = "Hint"
	_hint_label.text = CLOSE_HINT
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	_hint_label.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	_hint_label.add_theme_color_override("font_color", COLOR_HINT)
	column.add_child(_hint_label)


func _add_row(index: int) -> void:
	"""
	One row: a full-width Button carrying the name, with the distance drawn
	right-aligned inside it.

	THE NAME IS THE BUTTON'S OWN `text` and the distance is a CHILD LABEL of it,
	rather than two labels in an HBox, and that keeps the whole row ONE tap target
	— the thing that matters most on a phone, where the circle is the only way
	into this list and a row is the only way to use it. The name being `text` is
	also what makes the row size itself and what puts it through `Control`'s
	auto-translation (Localization RULE 1: the English name IS the CSV key). The
	distance Label is MOUSE_FILTER_IGNORE, so a press that lands on it still
	reaches the button under it.

	FOCUS_NONE, and `skill_tree_ui._build_ui` carries the whole reason: a
	`BaseButton` KEEPS focus after a click, and `ui_accept` — which fires a focused
	button — is SPACE, which is also `jump`. One tap here would otherwise travel
	again on the next jump, at `TELEPORT_COIN_COST` a time.
	"""
	var row := Button.new()
	row.name = "Row%d" % index
	row.focus_mode = Control.FOCUS_NONE
	row.visible = false
	# LEFT, and clipped: a German name that outgrew `NAME_WIDTH` must eat its own
	# tail rather than run under the distance column. `locale_selfcheck` is what
	# stops it getting that far.
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.clip_text = true
	row.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	row.custom_minimum_size = Vector2(CARD_WIDTH, ROW_HEIGHT)
	row.pressed.connect(_on_row_pressed.bind(index))
	_rows_box.add_child(row)

	# The distance, RIGHT, in the button's own rect, inset by the theme Button's
	# content padding so it lines up with the name's left edge rather than sitting
	# on the frame.
	var distance_label := Label.new()
	distance_label.name = "Distance"
	distance_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	distance_label.offset_right = -float(HudTheme.CARD_PADDING)
	distance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	distance_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	distance_label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	distance_label.add_theme_color_override("font_color", COLOR_DISTANCE)
	row.add_child(distance_label)

	_rows.append(row)
	_row_distances.append(distance_label)


func _rule() -> ColorRect:
	"""The 1 px STEEL rule the spec puts under a section heading."""
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = HudTheme.STEEL
	rule.custom_minimum_size = Vector2(0.0, RULE_PX)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule
