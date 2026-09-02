extends SceneTree
## ============================================================================
## CITY MAP SELF-CHECK — run headless, prints "SELFCHECK OK", exits 0
## ============================================================================
##
##     godot --headless --path . --import      # once, so the CSV table resolves
##     godot --headless --path . --script res://scripts/city_map_selfcheck.gd
##
## Guards `scripts/city_map_panel.gd` (bead `godot-test1-8gw.11`) — the Budapest
## map panel opened with B. Explicit `if`s rather than `assert`s, for the reason
## `mp_selfcheck.gd` gives: asserts are stripped from release builds and this
## file's value is that it still works against one a year from now.
##
## WHAT IT GUARDS, and why each is worth a check:
##
##  1. **THE KEY IS FREE.** The panel opens on a RAW keycode outside the input
##     map, which means nothing in the engine will ever tell you it collided — a
##     second owner of `B` would just make both features fire on one press.
##     Checked against BOTH real sources: `project.godot`'s input map, and every
##     other raw-keycode panel's own constant, read from its script. No list of
##     taken keys is written down here, so a future panel is covered the day its
##     constant lands.
##
##  2. **THE PROJECTION.** North-up: world +X (east) is screen right, +Z (south)
##     is screen down. A sign error mirrors the city, which looks entirely
##     plausible and is useless to navigate by — `minimap_selfcheck`'s lesson.
##     Asserted as an EFFECT (the Parliament really is east of Buda Castle on the
##     map, Gellért really is south of Margaret Island), never as a read-back of
##     the formula, which a mirrored formula would satisfy too.
##
##  3. **THE PLAN IS BAKED ONCE.** The whole performance story of this panel is
##     that the ~30k-predicate river sweep is paid on the first open and never
##     again. A rebuild-per-open looks IDENTICAL and costs a hitch on every press
##     of B, so nothing but a check can see it. The bake's CONTENT is measured
##     too — river, deck, hill — with plain land as the negative control, because
##     an all-land image would satisfy "a texture exists".
##
##  4. **THE MASK LIGHTS THE ICONS.** The panel's entire job. Driven through the
##     real `explored_mask` on a real player, with the empty mask as the negative
##     control, and with the LIT SET compared slot by slot — a count alone passes
##     for a map that lights the wrong 18 places.
##
##  5. **THE PAUSE POLICY.** Solo it freezes the world through `PauseHub`; IN A
##     ROOM it must not (the pause is local, the simulation is not — the
##     `landmark_toast` precedent), and over Game Over it must not (`GameOverUI`
##     is PAUSABLE and a pause there kills its Play Again button). Both refusals
##     are the kind that are written once and quietly stop working, so both get a
##     positive control beside them.
##
##  6. **THE TEAMMATE LAYER**, with the same negative control the minimap's has:
##     solo there is no room, `peer_markers()` answers null, and NOTHING may be
##     drawn.
##
##  7. **THE COMPOSED LINES.** The progress line must read its threshold off
##     `player_controller.BUDAPEST_WIN_LANDMARKS` rather than restating 18, and
##     both it and the close hint must resolve in German (`tr()` returns its own
##     key on a miss, so an unimported row renders in English, silently).

const CityMapPanel: GDScript = preload("res://scripts/city_map_panel.gd")
const BudapestPlan := preload("res://scripts/budapest_plan.gd")
const PlayerScript: GDScript = preload("res://scripts/player_controller.gd")

## The other raw-keycode owners, each read from its own script. `[keycodes, what
## it is]` — a single `Key` is wrapped so one loop covers both shapes.
const HelpOverlay := preload("res://scripts/help_overlay.gd")
const MinimapHud := preload("res://scripts/minimap_hud.gd")
const PauseController := preload("res://scripts/pause_controller.gd")
const PerfOverlay := preload("res://scripts/perf_overlay.gd")
const MotionDebug := preload("res://scripts/motion_debug.gd")
const MobileInput := preload("res://scripts/mobile_input.gd")
const TouchControls := preload("res://scripts/touch_controls.gd")
const MobileSettingsPanel := preload("res://scripts/mobile_settings_panel.gd")
const SkillTreeUi := preload("res://scripts/skill_tree_ui.gd")
const LandmarkToast := preload("res://scripts/landmark_toast.gd")

const PLAYER_SCENE: String = "res://scenes/player.tscn"

## One 8-bit tone. The bake is `FORMAT_RGBA8`, so a colour read back is quantized
## and `Color.is_equal_approx` would reject the very constant that was written.
const TONE_STEP: float = 1.0 / 255.0

var _failures: Array[String] = []


## A stand-in multiplayer manager. The panel reaches the real one through the
## "mp" group and two `has_method()` guards, so this is the whole interface — the
## same trick `minimap_selfcheck` drives its teammate layer with.
class StubMp extends Node:
	var busy: bool = false
	var markers: Variant = null

	func is_busy() -> bool:
		return busy

	func peer_markers() -> Variant:
		return markers


func _initialize() -> void:
	# ONE FRAME FIRST: `_initialize()` runs before the main loop, and a node added
	# to `root` before it answers null to `get_tree()` — the lesson
	# `pause_selfcheck` and `minimap_selfcheck` both record at length.
	await process_frame

	_check_key_is_free()
	_check_projection()
	await _check_bake_once()
	await _check_mask_lights_icons()
	await _check_pause_policy()
	await _check_teammates()
	await _check_lines()

	if _failures.is_empty():
		print("SELFCHECK OK")
		quit(0)
	else:
		for line: String in _failures:
			printerr("FAIL: " + line)
		printerr("SELFCHECK FAILED (%d)" % _failures.size())
		quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


# ============================================================================
# 1. THE KEY IS FREE
# ============================================================================

func _check_key_is_free() -> void:
	var key: int = int(CityMapPanel.TOGGLE_KEY)
	if key == 0:
		_fail("the panel's TOGGLE_KEY is 0 — it can never be pressed")
		return

	# --- Against the input map ---------------------------------------------
	# A gameplay action is REBINDABLE and a panel key is not, so a collision here
	# is unfixable from inside the game: both fire, forever.
	for action: StringName in InputMap.get_actions():
		for event: InputEvent in InputMap.action_get_events(action):
			if not (event is InputEventKey):
				continue
			var as_key := event as InputEventKey
			if int(as_key.keycode) == key or int(as_key.physical_keycode) == key:
				_fail("TOGGLE_KEY %s is also bound to the input action \"%s\""
					% [OS.get_keycode_string(key), action])

	# --- Against every other raw-keycode panel ------------------------------
	var owners: Array = [
		[[MinimapHud.TOGGLE_KEYCODE], "minimap_hud.TOGGLE_KEYCODE"],
		[MinimapHud.ZOOM_IN_KEYCODES, "minimap_hud.ZOOM_IN_KEYCODES"],
		[MinimapHud.ZOOM_OUT_KEYCODES, "minimap_hud.ZOOM_OUT_KEYCODES"],
		[[PauseController.PAUSE_KEY], "pause_controller.PAUSE_KEY"],
		[[SkillTreeUi.TOGGLE_KEY], "skill_tree_ui.TOGGLE_KEY"],
		[HelpOverlay.HELP_KEYCODES, "help_overlay.HELP_KEYCODES"],
		[LandmarkToast.ANSWER_KEYCODES, "landmark_toast.ANSWER_KEYCODES"],
		[PlayerScript.HERO_KEYCODES, "player_controller.HERO_KEYCODES"],
		[[PerfOverlay.TOGGLE_KEYCODE], "perf_overlay.TOGGLE_KEYCODE"],
		[[MotionDebug.TOGGLE_KEYCODE], "motion_debug.TOGGLE_KEYCODE"],
		[[MobileInput.FORCE_ENABLE_KEYCODE], "mobile_input.FORCE_ENABLE_KEYCODE"],
		[[TouchControls.FORCE_SHOW_KEYCODE], "touch_controls.FORCE_SHOW_KEYCODE"],
		[[MobileSettingsPanel.FORCE_SHOW_KEYCODE], "mobile_settings_panel.FORCE_SHOW_KEYCODE"],
	]
	var seen: int = 0
	for entry: Array in owners:
		for taken in entry[0]:
			seen += 1
			if int(taken) == key:
				_fail("TOGGLE_KEY %s is already %s"
					% [OS.get_keycode_string(key), entry[1]])
	# POSITIVE CONTROL on the loop itself: if every constant above resolved to an
	# empty array the comparison would pass in silence.
	if seen < owners.size():
		_fail("only %d raw keycodes were read from %d owners — the scan is hollow"
			% [seen, owners.size()])


# ============================================================================
# 2. THE PROJECTION — north up, and the whole city on the map
# ============================================================================

func _check_projection() -> void:
	var side: float = float(CityMapPanel.MAP_PIXELS)

	# The rect's own corners must land on the texture's corners, or the plan is
	# drawn at a scale nothing else on the panel agrees with.
	var north_west: Vector2 = CityMapPanel.map_point(
		BudapestPlan.BUDAPEST_MIN.x, BudapestPlan.BUDAPEST_MIN.y)
	var south_east: Vector2 = CityMapPanel.map_point(
		BudapestPlan.BUDAPEST_MAX.x, BudapestPlan.BUDAPEST_MAX.y)
	if not north_west.is_equal_approx(Vector2.ZERO):
		_fail("the city's north-west corner maps to %s, not the map's origin" % north_west)
	if not south_east.is_equal_approx(Vector2(side, side)):
		_fail("the city's south-east corner maps to %s, not (%.0f, %.0f)"
			% [south_east, side, side])

	# --- Orientation, measured as an EFFECT on real slots -------------------
	# The Parliament is on the Pest (east) bank and Buda Castle on the Buda (west)
	# one; Margaret Island is upstream (north) of Gellért Hill's Citadella. A
	# mirrored map satisfies neither.
	var parliament: Vector2 = _slot_point("parliament")
	var castle: Vector2 = _slot_point("buda_castle")
	var island: Vector2 = _slot_point("margaret_island")
	var citadella: Vector2 = _slot_point("citadella")
	if parliament.x <= castle.x:
		_fail("the Parliament (east bank) is not right of Buda Castle (west bank) "
			+ "— the map is mirrored east/west")
	if island.y >= citadella.y:
		_fail("Margaret Island (upstream, north) is not above the Citadella "
			+ "(downstream, south) — the map is mirrored north/south")

	# --- Every slot is ON the map -------------------------------------------
	# An icon is drawn ICON_SIZE wide, so its ink — not just its anchor — has to
	# fit, or a place on the city's edge is a half-square clipped by the frame.
	var half: float = CityMapPanel.ICON_SIZE * 0.5
	for i in range(BudapestPlan.SLOTS.size()):
		var slot: Dictionary = BudapestPlan.SLOTS[i]
		var pos: Vector3 = slot["pos"]
		var point: Vector2 = CityMapPanel.map_point(pos.x, pos.z)
		if point.x - half < 0.0 or point.x + half > side \
				or point.y - half < 0.0 or point.y + half > side:
			_fail("slot %d (%s) draws its icon at %s, off a %.0f px map"
				% [i, slot["id"], point, side])

	# The gate is on the city's WEST edge — the one landmark of the plan whose map
	# position is knowable without reading a slot.
	var gate: Vector2 = CityMapPanel.map_point(BudapestPlan.GATE.x, BudapestPlan.GATE.z)
	if absf(gate.x) > 0.001:
		_fail("the gate maps to x=%.2f, but it is authored on the city's west edge" % gate.x)


func _slot_point(id: String) -> Vector2:
	for slot: Dictionary in BudapestPlan.SLOTS:
		if String(slot["id"]) == id:
			var pos: Vector3 = slot["pos"]
			return CityMapPanel.map_point(pos.x, pos.z)
	_fail("no slot with id \"%s\" — the plan was renamed under this check" % id)
	return Vector2.ZERO


# ============================================================================
# 3. THE PLAN IS BAKED ONCE, AND IT IS THE PLAN
# ============================================================================

func _check_bake_once() -> void:
	var panel: Control = await _make_panel()

	if panel._base_texture != null:
		_fail("the plan was baked before the panel was ever opened — the first "
			+ "open is what pays for it, not every boot")

	panel.set_panel_open(true)
	await process_frame
	var first: Texture2D = panel._base_texture
	if first == null:
		_fail("opening the panel baked no texture at all")
		panel.queue_free()
		return
	if first.get_width() != CityMapPanel.MAP_PIXELS \
			or first.get_height() != CityMapPanel.MAP_PIXELS:
		_fail("the baked plan is %dx%d, not %d square"
			% [first.get_width(), first.get_height(), CityMapPanel.MAP_PIXELS])

	# THE CHECK THIS SECTION EXISTS FOR: close, reopen, and it must be the SAME
	# texture object. A rebuild looks identical and costs the sweep every press.
	panel.set_panel_open(false)
	await process_frame
	panel.set_panel_open(true)
	await process_frame
	if panel._base_texture != first:
		_fail("re-opening the panel re-baked the plan — the sweep is paid on "
			+ "every press of B instead of once")

	# --- The bake is really the plan ---------------------------------------
	var image: Image = first.get_image()
	if image == null:
		_fail("the baked texture has no image to measure")
		panel.queue_free()
		return
	# Mid-river, well away from every deck and the island: the Danube's own
	# polyline node at z = 0.
	_expect_pixel(image, Vector2(BudapestPlan.DANUBE[2].x, BudapestPlan.DANUBE[2].y),
		CityMapPanel.COLOR_WATER, "mid-Danube")
	# The middle of Castle Hill's lid, and the middle of the Chain Bridge's deck.
	var castle_rect: Rect2 = BudapestPlan.PLATEAUS[0]["rect"]
	_expect_pixel(image, castle_rect.get_center(), CityMapPanel.COLOR_HILL, "Castle Hill")
	var chain: Rect2 = BudapestPlan.DRY_RECTS[int(BudapestPlan.BRIDGES[1]["dry"])]
	_expect_pixel(image, chain.get_center(), CityMapPanel.COLOR_DECK, "the Chain Bridge deck")
	# NEGATIVE CONTROL: an all-water or all-deck image would pass every line
	# above. Deep in Pest, far from the river, the hills and the grid's lines.
	_expect_pixel(image, Vector2(3231.0, 899.0), CityMapPanel.COLOR_LAND, "open Pest")

	panel.queue_free()
	await process_frame


func _expect_pixel(image: Image, world: Vector2, want: Color, what: String) -> void:
	var point: Vector2 = CityMapPanel.map_point(world.x, world.y)
	var px: int = clampi(int(point.x), 0, image.get_width() - 1)
	var py: int = clampi(int(point.y), 0, image.get_height() - 1)
	var got: Color = image.get_pixel(px, py)
	# Per-channel, to one 8-bit step: the image is FORMAT_RGBA8, so every colour
	# comes back quantized and `Color.is_equal_approx` (1e-6) rejects its own input.
	if absf(got.r - want.r) > TONE_STEP or absf(got.g - want.g) > TONE_STEP \
			or absf(got.b - want.b) > TONE_STEP:
		_fail("%s bakes as %s at pixel (%d, %d), expected %s" % [what, got, px, py, want])


# ============================================================================
# 4. THE MASK LIGHTS THE ICONS
# ============================================================================

func _check_mask_lights_icons() -> void:
	var player: Node = await _make_player()
	var panel: Control = await _make_panel()
	panel.set_panel_open(true)
	await process_frame

	# NEGATIVE CONTROL FIRST: an empty mask must light nothing. Without it "18 lit"
	# is equally true of a panel that lights every icon it draws.
	panel._refresh()
	if _lit_slots(panel).size() != 0:
		_fail("a fresh run lights %d icons — nothing has been explored yet"
			% _lit_slots(panel).size())
	if panel._icon_points.size() != BudapestPlan.SLOTS.size():
		_fail("the panel drew %d icons for %d slots"
			% [panel._icon_points.size(), BudapestPlan.SLOTS.size()])

	# A real, scattered set — first, last and three in between, so an off-by-one in
	# the bit shift cannot hide at either end.
	var explored: Array = [0, 3, 9, 17, BudapestPlan.SLOTS.size() - 1]
	for index: int in explored:
		player.explore_landmark(index)
	panel._refresh()
	var lit: Array = _lit_slots(panel)
	if lit != explored:
		_fail("the mask %s lights slots %s — the map names the wrong places"
			% [str(explored), str(lit)])

	panel.queue_free()
	player.queue_free()
	await process_frame


func _lit_slots(panel: Control) -> Array:
	"""Which slot indices the panel painted in the explored colour, in order."""
	var lit: Array = []
	for i in range(panel._icon_colors.size()):
		if (panel._icon_colors[i] as Color).is_equal_approx(CityMapPanel.COLOR_FOUND):
			lit.append(i)
	return lit


# ============================================================================
# 5. THE PAUSE POLICY — solo yes, in a room no, over game over no
# ============================================================================

func _check_pause_policy() -> void:
	var player: Node = await _make_player()
	var panel: Control = await _make_panel()
	# The hub counts holders by identity and this is the only one in the fixture,
	# so `holder_count()` IS "does the map hold a claim" here. Asserted empty first,
	# or every line below would be measuring somebody else's pause.
	if PauseHub.holder_count() != 0 or paused:
		_fail("check 5 started with %d pause holders (paused=%s) — an earlier check "
			% [PauseHub.holder_count(), paused] + "left the world frozen")

	# --- Solo: the positive control -----------------------------------------
	panel.set_panel_open(true)
	await process_frame
	if not paused or PauseHub.holder_count() != 1:
		_fail("the map opened solo and the world kept running (paused=%s, holders=%d)"
			% [paused, PauseHub.holder_count()])
	panel.set_panel_open(false)
	await process_frame
	if paused or PauseHub.holder_count() != 0:
		_fail("the map closed and the world is still frozen (paused=%s, holders=%d)"
			% [paused, PauseHub.holder_count()])

	# --- In a room: opens, freezes nothing -----------------------------------
	var mp := StubMp.new()
	mp.busy = true
	mp.add_to_group("mp")
	root.add_child(mp)
	await process_frame
	panel.set_panel_open(true)
	await process_frame
	if not panel.is_panel_open():
		_fail("the map refused to open in a room — it is a map, not a pause")
	if paused or PauseHub.holder_count() != 0:
		_fail("the map froze the world inside a room — the pause is local and the "
			+ "simulation is not")
	# ...and leaving the room while it is up must hand the pause back over, which
	# is what the per-frame re-assert in `_process` is for.
	mp.busy = false
	await process_frame
	if not paused or PauseHub.holder_count() != 1:
		_fail("the room ended under an open map and the world never stopped again")
	panel.set_panel_open(false)
	await process_frame
	mp.queue_free()

	# --- Over game over: opens, freezes nothing ------------------------------
	player.is_game_over = true
	panel.set_panel_open(true)
	await process_frame
	if paused or PauseHub.holder_count() != 0:
		_fail("the map froze the world over Game Over — Play Again is PAUSABLE and "
			+ "would stop answering")
	panel.set_panel_open(false)
	player.is_game_over = false

	# --- And a node that goes away releases what it held ---------------------
	panel.set_panel_open(true)
	await process_frame
	panel.queue_free()
	await process_frame
	await process_frame
	if paused or PauseHub.holder_count() != 0:
		_fail("the map was freed while open and left the tree paused forever "
			+ "(paused=%s, holders=%d)" % [paused, PauseHub.holder_count()])

	player.queue_free()
	await process_frame


# ============================================================================
# 6. TEAMMATES — and the negative control that solo has none
# ============================================================================

func _check_teammates() -> void:
	var panel: Control = await _make_panel()
	panel.set_panel_open(true)
	await process_frame

	# SOLO: `peer_markers()` answers null, and nothing may be drawn.
	panel._refresh()
	if panel._peer_points.size() != 0:
		_fail("solo, the map drew %d teammate dots" % panel._peer_points.size())

	var mp := StubMp.new()
	mp.markers = [
		{"id": "a", "pos": Vector3(2700.0, 0.0, -300.0), "color": Color(1, 0, 0, 1)},
		# Far outside the city: must be CLAMPED onto the map and dimmed, not drawn
		# off the picture or dropped.
		{"id": "b", "pos": Vector3(-4000.0, 0.0, 4000.0), "color": Color(0, 1, 0, 1)},
	]
	mp.add_to_group("mp")
	root.add_child(mp)
	await process_frame
	panel._refresh()
	if panel._peer_points.size() != 2:
		_fail("two teammates in the room drew %d dots" % panel._peer_points.size())
	else:
		var side: float = float(CityMapPanel.MAP_PIXELS)
		var far: Vector2 = panel._peer_points[1]
		if far.x < 0.0 or far.x > side or far.y < 0.0 or far.y > side:
			_fail("an off-map teammate drew at %s, outside the map" % far)
		if (panel._peer_colors[1] as Color).a >= 0.99:
			_fail("an off-map teammate is drawn at full alpha — a clamped dot must "
				+ "not read as one standing where it says it stands")
		if not (panel._peer_colors[0] as Color).is_equal_approx(Color(1, 0, 0, 1)):
			_fail("an on-map teammate lost its own peer colour")

	panel.set_panel_open(false)
	mp.queue_free()
	panel.queue_free()
	await process_frame


# ============================================================================
# 7. THE COMPOSED LINES
# ============================================================================

func _check_lines() -> void:
	var player: Node = await _make_player()
	var panel: Control = await _make_panel()
	panel.set_panel_open(true)
	await process_frame
	player.explore_landmark(0)
	player.explore_landmark(1)
	panel._refresh()

	var line: String = panel._progress_label.text
	# THE THRESHOLD IS READ, NOT RESTATED: the line must carry the player's own
	# design number, so a wave that changes 18 changes this line with it.
	for wanted: String in [
		str(2), str(BudapestPlan.SLOTS.size()), str(PlayerScript.BUDAPEST_WIN_LANDMARKS),
	]:
		if not line.contains(wanted):
			_fail("the progress line \"%s\" does not carry %s" % [line, wanted])
	if panel._hint_label.text.is_empty():
		_fail("the close hint is blank — nothing tells the player how to get out")
	if not panel._hint_label.text.contains(OS.get_keycode_string(CityMapPanel.TOGGLE_KEY)):
		_fail("the close hint \"%s\" does not name the key that closes it"
			% panel._hint_label.text)

	# --- German -------------------------------------------------------------
	# `tr()` answers its own key on a miss, so an unimported or mistyped row
	# renders in English inside a German game with nothing in the log.
	var previous: String = TranslationServer.get_locale()
	TranslationServer.set_locale("de")
	for key: String in [
		"MAP OF BUDAPEST", CityMapPanel.PROGRESS_LINE, CityMapPanel.CLOSE_HINT,
	]:
		if tr(key) == key:
			_fail("\"%s\" has no German row in ui.csv — it would render in English "
				% key.c_escape() + "inside a German game, silently")
	TranslationServer.set_locale(previous)

	panel.set_panel_open(false)
	panel.queue_free()
	player.queue_free()
	await process_frame


# ============================================================================
# FIXTURES
# ============================================================================

func _make_panel() -> Control:
	var panel: Control = Control.new()
	panel.set_script(CityMapPanel)
	root.add_child(panel)
	await process_frame
	return panel


func _make_player() -> Node:
	"""A real `player.tscn` in the tree, with whatever the staging frame did to it
	undone — `landmark_progress_selfcheck._make_player`'s rule and its reason."""
	var player: Node = (load(PLAYER_SCENE) as PackedScene).instantiate()
	root.add_child(player)
	await process_frame
	player.is_caught = false
	player.is_respawning = false
	player.is_game_over = false
	player.explored_mask = 0
	return player
