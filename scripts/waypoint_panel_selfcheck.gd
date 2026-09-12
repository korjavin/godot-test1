extends SceneTree
## waypoint_panel_selfcheck — the TRAVEL PANEL (epic `godot-test1-sc6`, bead .4):
## the list that opens when a hero stands on a found circle, names the places the
## crew can travel to, and hands one press to
## `PlayerController.travel_to_waypoint()`.
##
##     godot --headless --path . --import      # once, so the CSV table resolves
##     godot --headless --path . --script res://scripts/waypoint_panel_selfcheck.gd
##
## WHAT IT ASSERTS, and why each is worth a check:
##
##  a. THE EDGES ARE THE WHOLE INTERACTION. There is no key and no opener button
##     (owner ruling, 2026-09-12: Diablo's rule), so the panel's entire
##     open/close contract is four edges and every one of them is invisible from
##     the code that raises it. Driven through the SHIPPED hub tick with a real
##     body moved by hand: closed off a circle, closed on a circle whose bit is
##     CLEAR (the negative control, without which "it opens" is equally true of a
##     panel that opens anywhere), open after the enter edge onto a found one,
##     and closed again after the leave edge.
##
##  b. THE ROWS ARE THE FOUND SET, SLOT BY SLOT — a count alone passes for a list
##     that names the wrong places, which is `city_map_selfcheck` check 4's
##     lesson one panel along. Every name is compared to the shipped
##     `site_name()` AND asserted not to be the raw `id` (an id nobody added to
##     `SITE_NAMES` would otherwise ship as "road_2" in both languages), the row
##     you are standing on is listed and DISABLED, the distance beside each other
##     row is the real XZ distance, and the two coin states are driven both ways:
##     a hero short of the fare has every row dead, a hero who can pay does not.
##
##  c. THE PAUSE POLICY. Solo it freezes the world through `PauseHub`; in a room
##     it must not (the pause is local, the simulation is not — the
##     `landmark_toast` / `city_map_panel` precedent), and over Game Over it must
##     not (`GameOverUI` is PAUSABLE and a pause there kills Play Again). Both
##     refusals are the kind that are written once and quietly stop working, so
##     both get a positive control beside them.
##
##  d. GERMAN. `tr()` answers its own key on a miss, so an unimported or mistyped
##     row renders in English inside a German game with nothing in the log. Asked
##     of every composed line AND every name a row can carry.
##
##  e. ONE PRESS REACHES TRAVEL WITH THAT ROW'S INDEX. A stub player records the
##     call; what the shipped travel then does is `waypoint_travel_selfcheck`'s
##     business and is deliberately not re-asserted here.
##
##  f. THE CARD FITS. Measured on a real layout at 1280x720 and at 400x800 with
##     every row shown carrying the WIDEST German name in the table — the phone
##     is the size that matters, because the circle is the only way into this
##     list and there is no opener to fall back on.
##
## DRIVEN AGAINST THE LIVE `main.tscn` for checks a, b, c and e —
## `waypoint_travel_selfcheck`'s prelude and its reason: the sites come from
## `TerrainWaypoints.waypoint_sites()` off the run's own terrain, so this check
## cannot pass against coordinates it invented. Checks d and f need no world and
## run first, before the scene exists to interfere with them.
##
## THE ONE PRIVATE REACHED INTO IS `WaypointHub._tick()`, for
## `waypoint_travel_selfcheck`'s reason: the enter edge is throttled to 5 Hz off
## `_process`, and sleeping a fifth of a second per move would make this a timing
## test. Calling the tick directly runs the SHIPPED scan with the throttle taken
## out. The panel's own state is read through `is_panel_open()` and the row
## buttons; nothing writes it but the shipped edges.

const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")
const WaypointHub := preload("res://scripts/waypoint_hub.gd")
const PlayerScript: GDScript = preload("res://scripts/player_controller.gd")

## Metres of slack allowed between the distance a row prints and the one measured
## off the site table. The row rounds to the metre, so one is the whole budget.
const DISTANCE_SLACK: float = 1.0

## The one budgeted string in this file's German sweep that is legitimately
## IDENTICAL in both languages: a distance is "%d m" in German too. Named here so
## the sweep stays strict about every other row rather than being loosened for
## all of them — `help_selfcheck`'s key-legend exemption, and its reason.
const GERMAN_EXEMPT: Array = [WaypointHub.DISTANCE_LINE]

var _failures: Array[String] = []


func _initialize() -> void:
	Sentinel.isolate_user_state()
	# ONE FRAME FIRST: `_initialize()` runs before the main loop, and a node added
	# to `root` before it answers null to `get_tree()`.
	await process_frame

	# The two world-free checks first, while there is no `main.tscn` in the tree
	# whose hub, player and terrain could reach into the probe stages below.
	_check_german()
	await _check_layout()

	await _boot()
	await _check_edges()
	await _check_rows()
	await _check_pause_policy()
	# LAST: it displaces the real player with a recording stub and never puts it
	# back, so nothing after it would have a hero to stand anywhere.
	await _check_press_travels()

	if _failures.is_empty():
		Sentinel.finish(self)
	else:
		for line: String in _failures:
			printerr("FAIL: " + line)
		printerr("SELFCHECK FAILED (%d)" % _failures.size())
		quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


func _boot() -> void:
	"""main.tscn running with the start overlay dismissed —
	`waypoint_travel_selfcheck._boot()`, verbatim."""
	root.add_child(load("res://scenes/main.tscn").instantiate())
	await process_frame
	var overlay: Node = root.get_node_or_null("Main/HUD/StartOverlay")
	if overlay != null and overlay.has_method("_dismiss"):
		overlay._dismiss()
	await process_frame


func _world() -> Array:
	"""`[player, terrain, hub, sites]`, or an empty array when the scene is not
	whole. Re-fetched per check by GROUP, the project's discovery convention."""
	var player: Node = get_first_node_in_group("player")
	var terrain: Node = get_first_node_in_group("terrain")
	var hub: Node = get_first_node_in_group("waypoint_hub")
	if player == null or terrain == null or hub == null:
		return []
	var sites: Array[Dictionary] = TerrainWaypoints.waypoint_sites(terrain)
	if sites.size() < 3:
		return []
	return [player, terrain, hub, sites]


func _stand_on(player: Node, hub: Node, sites: Array, index: int) -> void:
	"""Put the body on circle `index` and run the shipped scan once — which also
	FINDS it the first time, through `_arrive()` -> `activate_waypoint()`, so every
	bit under test was set by the discovery path a player really walks."""
	var pos: Vector3 = sites[index]["pos"]
	player.global_position = Vector3(pos.x, 1.0, pos.z)
	hub._tick()


func _walk_away(player: Node, hub: Node) -> void:
	"""Put the body where no circle is, and tick. Far enough that no site in any
	run is within `RING_RADIUS + LEAVE_PAD` of it."""
	player.global_position = Vector3(0.0, 1.0, -9000.0)
	hub._tick()


# ============================================================================
# a. THE EDGES
# ============================================================================

func _check_edges() -> void:
	var world: Array = _world()
	if world.is_empty():
		_fail("no world for the edge check")
		Sentinel.done("edges")
		return
	var player: Node = world[0]
	var hub: Node = world[2]
	var sites: Array = world[3]

	# --- Off any circle: closed ---------------------------------------------
	_walk_away(player, hub)
	if hub.is_panel_open():
		_fail("the travel list is open with the hero standing on nothing")

	# --- THE NEGATIVE CONTROL: a circle whose bit is CLEAR -------------------
	# The only way to stand on an unfound circle in the shipped game is to be a
	# body that cannot find one, so that is what this puts in the group: a Node3D
	# carrying `waypoint_mask` and no `activate_waypoint`, which latches the hub
	# (a latch is a POSITION, not a permission) and sets no bit. Without this the
	# open below is equally true of a panel that opens on any circle at all.
	var real_player: Node = player
	real_player.remove_from_group("player")
	var blank := BlankHero.new()
	blank.add_to_group("player")
	root.add_child(blank)
	await process_frame
	var pos: Vector3 = sites[1]["pos"]
	blank.global_position = Vector3(pos.x, 1.0, pos.z)
	hub._tick()
	if hub.standing_on() != 1:
		_fail("the hub did not latch the blank hero onto circle 1 — the negative "
			+ "control below is not standing on anything")
	if hub.is_panel_open():
		_fail("the travel list opened on a circle the crew has not found — "
			+ "`standing_on()` is a position, not a permission")
	blank.free()
	real_player.add_to_group("player")
	await process_frame

	# --- The enter edge onto a FOUND one: open ------------------------------
	_walk_away(real_player, hub)
	_stand_on(real_player, hub, sites, 1)
	if hub.standing_on() != 1:
		_fail("the hub did not latch circle 1 under the real hero")
	if not hub.is_panel_open():
		_fail("the travel list did not open on the enter edge onto a found circle "
			+ "— it is the only way in, so this is the whole feature")

	# --- The leave edge: closed again ---------------------------------------
	_walk_away(real_player, hub)
	if hub.is_panel_open():
		_fail("the travel list stayed open after the hero walked off the circle")
	if paused or PauseHub.holder_count() != 0:
		_fail("walking off the circle left the world frozen (paused=%s, holders=%d)"
			% [paused, PauseHub.holder_count()])
	Sentinel.done("edges")


# ============================================================================
# b. THE ROWS ARE THE FOUND SET
# ============================================================================

func _check_rows() -> void:
	var world: Array = _world()
	if world.is_empty():
		_fail("no world for the row check")
		Sentinel.done("rows")
		return
	var player: Node = world[0]
	var hub: Node = world[2]
	var sites: Array = world[3]

	# --- Every id in the shipped table has a name ---------------------------
	# Checked over the WHOLE table rather than the rows that happen to be lit, so
	# a city row nobody named fails here and not in a playtest.
	for site: Dictionary in sites:
		var id: String = String(site["id"])
		var name: String = WaypointHub.site_name(id)
		if name.is_empty() or name == id:
			_fail("waypoint \"%s\" has no name on the travel list — it would ship as "
				% id + "its own wire id, in both languages")

	# --- ONE circle found: the list says so rather than looking broken -------
	player.own_coins = 100
	player.coins_collected = 100
	_walk_away(player, hub)
	_stand_on(player, hub, sites, 1)
	if not hub.is_panel_open():
		_fail("the list did not open for the row check")
		Sentinel.done("rows")
		return
	if _shown_rows(hub) != [1]:
		_fail("one circle found and the list shows rows %s" % str(_shown_rows(hub)))
	if not hub._empty_label.visible:
		_fail("the only circle found is the one underfoot and the list does not say "
			+ "so — an empty card reads as broken, not as a mechanic to learn")

	# --- Three found, standing on the middle one ----------------------------
	_stand_on(player, hub, sites, 0)
	_stand_on(player, hub, sites, 2)
	_stand_on(player, hub, sites, 1)
	var shown: Array = _shown_rows(hub)
	if shown != [0, 1, 2]:
		_fail("the found set {0,1,2} draws rows %s — the list names the wrong places"
			% str(shown))
	if hub._empty_label.visible:
		_fail("two other circles are found and the list still says there are none")

	# --- Names, distances, and the row underfoot ----------------------------
	var origin: Vector3 = (player as Node3D).global_position
	for i: int in shown:
		var want: String = WaypointHub.site_name(String(sites[i]["id"]))
		if hub._rows[i].text != want:
			_fail("row %d reads \"%s\"; the site table calls it \"%s\""
				% [i, hub._rows[i].text, want])
		if i == 1:
			if not hub._rows[i].disabled:
				_fail("the row for the circle underfoot is pressable — it is where "
					+ "you are, not somewhere to go")
			if hub._row_distances[i].text != WaypointHub.HERE_LINE:
				_fail("the row underfoot reads \"%s\" instead of \"%s\""
					% [hub._row_distances[i].text, WaypointHub.HERE_LINE])
			continue
		if hub._rows[i].disabled:
			_fail("row %d is dead for a hero with 100 coins and a found target" % i)
		var want_metres: float = Vector2(
			origin.x - (sites[i]["pos"] as Vector3).x,
			origin.z - (sites[i]["pos"] as Vector3).z).length()
		var printed: String = hub._row_distances[i].text
		var got: float = float(printed.split(" ")[0])
		if absf(got - want_metres) > DISTANCE_SLACK + 1.0:
			_fail("row %d prints \"%s\" for a circle %.1f m away"
				% [i, printed, want_metres])

	# --- THE FARE, both ways -------------------------------------------------
	# The panel's own reading of `TELEPORT_COIN_COST`, driven either side of it: a
	# hero one coin short has nothing to press, and one who can exactly pay does.
	player.own_coins = PlayerScript.TELEPORT_COIN_COST - 1
	hub._refresh_rows()
	for i: int in shown:
		if not hub._rows[i].disabled:
			_fail("row %d is pressable for a hero who cannot pay the %d-coin fare"
				% [i, PlayerScript.TELEPORT_COIN_COST])
	if not hub._price_label.text.contains(str(PlayerScript.TELEPORT_COIN_COST)):
		_fail("the price line \"%s\" does not carry the %d-coin fare"
			% [hub._price_label.text, PlayerScript.TELEPORT_COIN_COST])
	player.own_coins = PlayerScript.TELEPORT_COIN_COST
	hub._refresh_rows()
	if hub._rows[0].disabled or hub._rows[2].disabled:
		_fail("a hero with exactly the fare cannot press anything — the panel and "
			+ "`travel_to_waypoint()` disagree about the price")

	_walk_away(player, hub)
	Sentinel.done("rows")


func _shown_rows(hub: Node) -> Array:
	"""Which mask bits the panel is drawing a row for, in order."""
	var out: Array = []
	for i in range(hub._rows.size()):
		if (hub._rows[i] as Button).visible:
			out.append(i)
	return out


# ============================================================================
# c. THE PAUSE POLICY
# ============================================================================

func _check_pause_policy() -> void:
	var world: Array = _world()
	if world.is_empty():
		_fail("no world for the pause check")
		Sentinel.done("pause_policy")
		return
	var player: Node = world[0]
	var hub: Node = world[2]
	var sites: Array = world[3]

	_walk_away(player, hub)
	var base: int = PauseHub.holder_count()
	if paused:
		_fail("the pause check started with the world already frozen")

	# --- Solo: the positive control -----------------------------------------
	_stand_on(player, hub, sites, 1)
	if not hub.is_panel_open():
		_fail("the list did not open for the pause check")
	if not paused or PauseHub.holder_count() != base + 1:
		_fail("the list opened solo and the world kept running (paused=%s, holders=%d)"
			% [paused, PauseHub.holder_count()])
	_walk_away(player, hub)
	if paused or PauseHub.holder_count() != base:
		_fail("the list closed and the world is still frozen (paused=%s, holders=%d)"
			% [paused, PauseHub.holder_count()])

	# --- In a room: opens, freezes nothing -----------------------------------
	# `main.tscn` carries its own solo manager FIRST in the "mp" group and
	# `get_first_node_in_group` answers the first, so displace it —
	# `waypoint_travel_selfcheck._check_room_gate()`'s line.
	var real_mp: Array = []
	for old: Node in get_nodes_in_group("mp"):
		old.remove_from_group("mp")
		real_mp.append(old)
	var mp := StubMp.new()
	mp.busy = true
	mp.add_to_group("mp")
	root.add_child(mp)
	await process_frame
	_stand_on(player, hub, sites, 1)
	if not hub.is_panel_open():
		_fail("the list refused to open in a room — it is a list, not a pause")
	if paused or PauseHub.holder_count() != base:
		_fail("the list froze the world inside a room — the pause is local and the "
			+ "simulation is not")
	# ...and leaving the room with it up must hand the pause OVER, which is what
	# the per-frame re-assert in `_process` is for.
	mp.busy = false
	await process_frame
	if not paused or PauseHub.holder_count() != base + 1:
		_fail("the room ended under an open travel list and the world never stopped")
	_walk_away(player, hub)
	mp.free()
	for old: Node in real_mp:
		old.add_to_group("mp")
	await process_frame

	# --- Over game over: opens nothing and freezes nothing -------------------
	player.is_game_over = true
	_stand_on(player, hub, sites, 1)
	if hub.is_panel_open():
		_fail("the travel list opened over Game Over — the only thing that may be "
			+ "on screen there is Play Again")
	if paused or PauseHub.holder_count() != base:
		_fail("the travel list froze the world over Game Over — Play Again is "
			+ "PAUSABLE and would stop answering")
	player.is_game_over = false
	_walk_away(player, hub)
	Sentinel.done("pause_policy")


# ============================================================================
# d. GERMAN
# ============================================================================

func _check_german() -> void:
	var previous: String = TranslationServer.get_locale()
	TranslationServer.set_locale("de")
	var keys: Array = [
		"Waypoints", WaypointHub.EMPTY_LINE, WaypointHub.CLOSE_HINT,
		WaypointHub.PRICE_LINE, WaypointHub.HERE_LINE, WaypointHub.ROAD_NAME,
		WaypointHub.DISTANCE_LINE,
	]
	# ...and every NAME a row can carry, read off the shipped table so a city row
	# added tomorrow is covered the day it lands.
	for id: String in WaypointHub.SITE_NAMES.keys():
		keys.append(String(WaypointHub.SITE_NAMES[id]))
	for key: String in keys:
		if GERMAN_EXEMPT.has(key):
			continue
		if TranslationServer.translate(key) == key:
			_fail("\"%s\" has no German row in ui.csv — the travel list would draw "
				% key.c_escape() + "it in English inside a German game, silently")
	TranslationServer.set_locale(previous)
	Sentinel.done("german")


# ============================================================================
# e. ONE PRESS REACHES TRAVEL
# ============================================================================

func _check_press_travels() -> void:
	var world: Array = _world()
	if world.is_empty():
		_fail("no world for the press check")
		Sentinel.done("press_travels")
		return
	var player: Node = world[0]
	var hub: Node = world[2]
	var sites: Array = world[3]

	# Find three circles with the real hero, so the panel has rows...
	player.own_coins = 100
	_walk_away(player, hub)
	_stand_on(player, hub, sites, 0)
	_stand_on(player, hub, sites, 2)
	_stand_on(player, hub, sites, 1)
	if not hub.is_panel_open():
		_fail("the list did not open for the press check")
		Sentinel.done("press_travels")
		return

	# ...then swap in a stub that RECORDS the call instead of taking it. What the
	# shipped travel does with the index is `waypoint_travel_selfcheck`'s subject;
	# what this file owns is that the index reaching it is the row's own.
	player.remove_from_group("player")
	var stub := RecordingHero.new()
	stub.add_to_group("player")
	root.add_child(stub)
	await process_frame

	hub._on_row_pressed(2)
	if stub.travelled_to != 2:
		_fail("pressing row 2 asked to travel to %d" % stub.travelled_to)
	if hub.is_panel_open():
		_fail("the travel list stayed open after a row was pressed")
	if paused or PauseHub.holder_count() != 0:
		_fail("a row press left the world frozen — the claim must be handed back "
			+ "BEFORE the hop awaits its physics frame (paused=%s, holders=%d)"
			% [paused, PauseHub.holder_count()])
	Sentinel.done("press_travels")


# ============================================================================
# f. THE CARD FITS
# ============================================================================

func _check_layout() -> void:
	"""
	The card, laid out for real at a desktop size and a phone one, with every row
	shown and carrying the WIDEST German name the table can produce.

	MEASURED RATHER THAN READ OFF `CARD_WIDTH`: the card is a PanelContainer round
	a MarginContainer round a VBox, and any of the three can grow past the minimum
	this file thinks it set. The phone width is the one that matters — the circle
	is the only way into this list, so a card that does not fit is a feature with
	no way to use it.
	"""
	var previous: String = TranslationServer.get_locale()
	TranslationServer.set_locale("de")
	for stage_size: Vector2 in [Vector2(1280.0, 720.0), Vector2(400.0, 800.0)]:
		var stage := Control.new()
		stage.size = stage_size
		root.add_child(stage)
		var hub := Control.new()
		hub.set_script(WaypointHub)
		hub.set_anchors_preset(Control.PRESET_FULL_RECT)
		stage.add_child(hub)
		# The tick would close the panel again the moment it ran (there is no
		# terrain here, so nothing latches) — this stage is about LAYOUT, and the
		# edges are check (a)'s on a real world.
		hub.set_process(false)
		await process_frame
		hub.set_panel_open(true)
		_fill_worst_case(hub)
		# Two frames for the containers to settle the layout their anchors describe.
		await process_frame
		await process_frame
		var card: Control = hub._card
		var rect: Rect2 = card.get_global_rect()
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			_fail("at %s the travel card measured an empty rect — every test below "
				% stage_size + "would pass against anything")
		if rect.size.x > stage_size.x or rect.size.y > stage_size.y:
			_fail("at %s the travel card is %s — it does not fit the screen, and "
				% [stage_size, rect.size] + "the circle is the only way into it")
		hub.set_panel_open(false)
		stage.queue_free()
		await process_frame
	TranslationServer.set_locale(previous)
	if paused or PauseHub.holder_count() != 0:
		_fail("the layout probe left the world frozen (paused=%s, holders=%d)"
			% [paused, PauseHub.holder_count()])
	Sentinel.done("layout")


func _fill_worst_case(hub: Control) -> void:
	"""Show every row, each carrying the longest name in the table and the longer
	of the two right-hand columns — the widest card this panel can ever draw."""
	var widest := ""
	for id: String in WaypointHub.SITE_NAMES.keys():
		var name: String = TranslationServer.translate(String(WaypointHub.SITE_NAMES[id]))
		if name.length() > widest.length():
			widest = name
	for i in range(hub._rows.size()):
		(hub._rows[i] as Button).visible = true
		(hub._rows[i] as Button).text = widest
		(hub._row_distances[i] as Label).text = TranslationServer.translate(
			WaypointHub.HERE_LINE)
	(hub._empty_label as Label).visible = true


# ============================================================================
# FIXTURES
# ============================================================================

## A body that can be STOOD on a circle and cannot FIND one: it carries the mask
## the panel reads and none of the methods the hub's `_arrive()` needs, so the
## latch happens and the bit never gets set. Check (a)'s negative control.
class BlankHero extends Node3D:
	var waypoint_mask: int = 0


## A body that records the travel it was asked for instead of taking it.
class RecordingHero extends Node3D:
	var travelled_to: int = -1

	func travel_to_waypoint(index: int) -> bool:
		travelled_to = index
		return true


## The room, as far as the panel's pause policy can see it: one `is_busy()`.
class StubMp extends Node:
	var busy: bool = false

	func is_busy() -> bool:
		return busy
