extends SceneTree
## Headless self-check: **THE PORTRAIT ROW SAYS WHO YOU HAVE LEFT.**
##
##   godot --headless --path . --script res://scripts/hero_hud_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints what failed and exits 1 — the shape
## every check in this project uses. Bead godot-test1-7p0.
##
## ============================================================================
## WHY THIS EXISTS
## ============================================================================
##
## The HUD itself is cosmetic, but two things it depends on rot silently:
##
##   * **The asset-path contract.** `res://assets/portraits/<hero>.png` is a
##     filename convention, and a convention is exactly what a renamed hero or a
##     new `CHARACTERS` row breaks with no error anywhere — the tile just quietly
##     drops to a placeholder and nobody notices for a month.
##   * **The four-state mapping.** ACTIVE / FREE / HELD / CAPTIVE come out of three
##     independent reads off the player, and the ordering between them is load
##     bearing: captivity has to OUTRANK "this is you", because the grab lands a
##     beat before the auto-switch and for that frame the honest tile is the cell.
##
## Both are checked against the REAL `PlayerController.CHARACTERS` and the REAL
## `HeroHUD` script — the check iterates the roster, never a list of its own, so a
## fifth hero is covered the day his row lands.
##
## ============================================================================
## WHAT IT GUARDS, check by check
## ============================================================================
##
##   1. **EVERY HERO HAS ART AND AN IDENTITY.** One `HERO_COLORS` row and one
##      loadable `Texture2D` at the single asset path, per `CHARACTERS` entry.
##   2. **A MISSING PORTRAIT IS A PLACEHOLDER, NOT AN ERROR** — and it is looked
##      for exactly once, because a `load()` per frame is the landmine here.
##   3. **THE FOUR STATES**, including captive-outranks-active and the room's
##      "a teammate has him" reading as HELD rather than as free.
##   4. **THE STANDALONE DEGRADE**: no player in the group -> an empty row.
##   5. **THE ROW FITS ITS CONTROL AND CLEARS ITS NEIGHBOURS** in `main.tscn` —
##      four tiles need 210 px, and no other top-left-anchored HUD widget may sit
##      in the band. The neighbours are ENUMERATED OUT OF THE SCENE (every
##      `parent="HUD"` block at `anchors_preset = 0`) rather than named here, so
##      the row is measured against whatever the HUD actually carries — which is
##      what kept this check alive when the hearts widget it used to name was
##      deleted, and what will catch the next widget dropped into that corner.
##
##      IT MOVED SIDEWAYS AND NOT DOWN, which is worth knowing before you "fix" it:
##      `PerfOverlay` is a Label whose real height is its TEXT's minimum size (316
##      px, not the 276 its offsets declare), so pushing its top down 48 px pushes
##      its bottom into the centre-left minimap — which `minimap_selfcheck`'s own
##      left-edge-column check catches. Moving it right of the row clears both.

const HUD_SCRIPT := preload("res://scripts/hero_hud.gd")
const PLAYER_SCRIPT := preload("res://scripts/player_controller.gd")
const MAIN_SCENE_PATH := "res://scenes/main.tscn"

var _failures: Array[String] = []


## A player stand-in carrying only the three members the HUD reads. Deliberately
## NOT a real `player_controller`: this check is about the mapping, and a stub is
## the only way to drive states (a whole room's worth of held heroes, say) that a
## live player cannot be put into headlessly.
class StubPlayer extends Node:
	var current_character_index: int = 0
	var captive: Array[String] = []
	## null = "no restriction" is not a thing here; the HUD only ever gets an Array.
	var available: Array = []

	func is_hero_captive(hero: String) -> bool:
		return captive.has(hero)

	func reachable_character_indices() -> Array:
		return available


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	Sentinel.isolate_user_state()
	_run()
	if _failures.is_empty():
		Sentinel.finish(self)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)
	Sentinel.done("check")


func _run() -> void:
	_check_every_hero_has_art_and_an_identity()
	_check_a_missing_portrait_is_a_placeholder()
	_check_the_four_states()
	_check_the_standalone_degrade()
	_check_the_row_fits_and_clears_its_neighbours()


func _hero_names() -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Variant in PLAYER_SCRIPT.CHARACTERS:
		out.append(String((entry as Dictionary)["name"]))
	return out


func _check_every_hero_has_art_and_an_identity() -> void:
	"""1. Every playable hero has a colour row and a real texture at the one path."""
	var colors: Dictionary = HUD_SCRIPT.HERO_COLORS
	for hero: String in _hero_names():
		_check(colors.has(hero),
			"hero '%s' has no HERO_COLORS row — his placeholder would be grey" % hero)
		var path := "res://assets/portraits/%s.png" % hero
		if not ResourceLoader.exists(path):
			_fail("no portrait at %s — the filename convention has drifted" % path)
			continue
		var tex := load(path) as Texture2D
		_check(tex != null, "%s did not load as a Texture2D" % path)
		if tex != null:
			# A HUD tile is 48 px; anything under that is upscaled mush, and the
			# owner's art is 256x256, so this is a floor and not the exact size.
			_check(tex.get_width() >= int(HUD_SCRIPT.TILE_SIZE)
					and tex.get_height() >= int(HUD_SCRIPT.TILE_SIZE),
				"%s is %dx%d, smaller than one %d px tile"
					% [path, tex.get_width(), tex.get_height(),
						int(HUD_SCRIPT.TILE_SIZE)])
	Sentinel.done("every_hero_has_art_and_an_identity")


func _check_a_missing_portrait_is_a_placeholder() -> void:
	"""2. An unknown hero falls back to the placeholder, and is looked up once."""
	var hud: Control = HUD_SCRIPT.new()
	_check(hud._portrait("no_such_hero") == null,
		"a hero with no art must resolve to null (the placeholder), not an error")
	# The cache must remember the MISS too — otherwise every repaint hits the
	# filesystem for a hero who will never have a file.
	_check(hud._portraits.has("no_such_hero"),
		"a missing portrait is not cached, so load() would be retried every repaint")
	# And a real one resolves to a texture through the same path.
	var first := _hero_names()[0]
	_check(hud._portrait(first) is Texture2D,
		"'%s' did not resolve to a texture through _portrait()" % first)
	hud.free()
	Sentinel.done("a_missing_portrait_is_a_placeholder")


func _check_the_four_states() -> void:
	"""3. ACTIVE / FREE / HELD / CAPTIVE, and the ordering between them."""
	var heroes := _hero_names()
	if heroes.size() < 3:
		_fail("this check needs at least three heroes to tell HELD from CAPTIVE")
		Sentinel.done("the_four_states")
		return
	var hud: Control = HUD_SCRIPT.new()
	var stub := StubPlayer.new()
	hud.player = stub

	# Solo, nobody captive: tile 0 is ACTIVE and the rest are FREE.
	stub.current_character_index = 0
	stub.available = _all_indices(heroes.size())
	var states: PackedInt32Array = hud._read_states(heroes)
	_check(states[0] == HUD_SCRIPT.STATE_ACTIVE,
		"the current character's tile is not ACTIVE")
	for i: int in range(1, heroes.size()):
		_check(states[i] == HUD_SCRIPT.STATE_FREE,
			"tile %d should be FREE with nobody captive and no room" % i)

	# In a room: the lobby handed us only hero 0, so 1..n read HELD, not FREE.
	stub.available = [0]
	states = hud._read_states(heroes)
	_check(states[1] == HUD_SCRIPT.STATE_HELD,
		"a hero another peer is wearing must read HELD, not FREE")

	# Captivity: hero 1 in a cell reads CAPTIVE even though HELD would also be
	# true of him (he is not in `available` either) — bars beat the plain veil.
	stub.available = _all_indices(heroes.size())
	stub.captive = [heroes[1]]
	states = hud._read_states(heroes)
	_check(states[1] == HUD_SCRIPT.STATE_CAPTIVE,
		"a hero in a cell must read CAPTIVE")

	# THE ORDERING. The grab lands before the auto-switch, so for one frame the
	# ACTIVE hero is also the captive one — and the tile must say cell.
	stub.captive = [heroes[0]]
	stub.current_character_index = 0
	states = hud._read_states(heroes)
	_check(states[0] == HUD_SCRIPT.STATE_CAPTIVE,
		"captivity must outrank ACTIVE — the grabbed hero cannot read as 'this is you'")

	# A player that answers none of the optional methods degrades to all-FREE
	# rather than erroring (the has_method guards).
	var bare := Node.new()
	hud.player = bare
	states = hud._read_states(heroes)
	_check(states.size() == heroes.size(),
		"a player with no roster methods must still produce one state per hero")
	for s: int in states:
		_check(s == HUD_SCRIPT.STATE_FREE,
			"a player with no roster methods must degrade to FREE, not to a cell")
	bare.free()
	stub.free()
	hud.free()
	Sentinel.done("the_four_states")


func _all_indices(n: int) -> Array:
	var out: Array = []
	for i: int in n:
		out.append(i)
	return out


func _check_the_standalone_degrade() -> void:
	"""4. No player anywhere -> an empty row, drawn as nothing."""
	var hud: Control = HUD_SCRIPT.new()
	hud.player = null            # nothing in group "player" resolves to exactly this
	var heroes: PackedStringArray = hud._read_roster()
	_check(heroes.is_empty(),
		"with no player the row must be empty, not four idle tiles")
	_check(hud._read_states(heroes).is_empty(),
		"an empty roster must carry no states")
	# A player that went away mid-run is the same case, via is_instance_valid.
	var gone := Node.new()
	hud.player = gone
	gone.free()
	_check(hud._read_roster().is_empty(),
		"a freed player must not leave a stale row painted")
	hud.free()
	Sentinel.done("the_standalone_degrade")


func _check_the_row_fits_and_clears_its_neighbours() -> void:
	"""
	5. The control in `main.tscn` is wide enough for the row, and the widgets above
	and below stay out of its band.

	Read out of the scene TEXT rather than by instancing `main.tscn`, which would
	build a world. The numbers are what a later layout edit silently breaks.
	"""
	var text := FileAccess.get_file_as_string(MAIN_SCENE_PATH)
	if text.is_empty():
		_fail("could not read %s" % MAIN_SCENE_PATH)
		Sentinel.done("the_row_fits_and_clears_its_neighbours")
		return
	var hero_rect: Variant = _node_rect(text, "HeroHUD")
	var perf_rect: Variant = _node_rect(text, "PerfOverlay")
	if hero_rect == null or perf_rect == null:
		_fail("HeroHUD / PerfOverlay not both found in %s" % MAIN_SCENE_PATH)
		Sentinel.done("the_row_fits_and_clears_its_neighbours")
		return

	var count: int = _hero_names().size()
	var needed: float = count * float(HUD_SCRIPT.TILE_SIZE) \
		+ (count - 1) * float(HUD_SCRIPT.TILE_GAP)
	_check((hero_rect as Rect2).size.x >= needed,
		"HeroHUD is %.0f px wide but %d tiles need %.0f"
			% [(hero_rect as Rect2).size.x, count, needed])
	_check((hero_rect as Rect2).size.y >= float(HUD_SCRIPT.TILE_SIZE),
		"HeroHUD is shorter than one tile")
	_check((hero_rect as Rect2).position.x >= 0.0
			and (hero_rect as Rect2).position.y >= 0.0,
		"the portrait row starts off the top/left edge of the screen")
	_check(not (hero_rect as Rect2).intersects(perf_rect as Rect2),
		"the portrait row overlaps the \\fo perf overlay — move the overlay clear of it "
		+ "(sideways: pushing it DOWN walks its text into the minimap)")
	# Every OTHER widget pinned to the same corner, read out of the scene rather
	# than listed here: the row's neighbours are whatever `main.tscn` ships.
	var neighbours := _hud_absolute_rects(text)
	for other_name: String in neighbours:
		if other_name == "HeroHUD":
			continue
		_check(not (hero_rect as Rect2).intersects(neighbours[other_name] as Rect2),
			"the portrait row overlaps %s (%s vs %s)"
				% [other_name, hero_rect, neighbours[other_name]])
	_check(neighbours.size() >= 2,
		"found only %d absolutely-positioned HUD widget(s) — the neighbour scan "
			% neighbours.size()
		+ "stopped seeing the scene, so this check would pass on anything")
	Sentinel.done("the_row_fits_and_clears_its_neighbours")


func _hud_absolute_rects(text: String) -> Dictionary:
	"""
	Every `parent="HUD"` node laid out in absolute offsets (`anchors_preset = 0`),
	as name -> Rect2. An anchored widget (the minimap, the ability dial) is skipped
	because its offsets are relative to an anchor and cannot be compared against
	the row's corner rect without instancing the scene.
	"""
	var out := {}
	# MATCH THE NODE HEADER, NOT ONE SHAPE OF IT. `type=` is optional (an instanced
	# child - TouchControls - has none) and `parent="HUD"` is not always the last
	# attribute (a node in a group carries `groups=[...]` after it). Pinning either
	# would silently skip those blocks, and this check exists precisely so the NEXT
	# widget dropped into that corner is covered without anybody editing it - a
	# widget that joins a group is the common shape in this HUD, so the narrow
	# pattern would have failed at the one job the check was rebuilt for.
	var re := RegEx.create_from_string('\\[node name="([^"]+)"[^\\]]*parent="HUD"[^\\]]*\\]')
	for m: RegExMatch in re.search_all(text):
		var node_name: String = m.get_string(1)
		var start: int = m.get_start()
		var end := text.find("\n[node ", start + 1)
		var block := text.substr(start, -1 if end < 0 else end - start)
		if not block.contains("anchors_preset = 0"):
			continue
		var rect: Variant = _node_rect(text, node_name)
		if rect != null:
			out[node_name] = rect
	return out


func _node_rect(text: String, node_name: String) -> Variant:
	"""The offset_* rect of one `[node name="..."]` block, or null if absent."""
	var start := text.find('[node name="%s"' % node_name)
	if start < 0:
		return null
	var end := text.find("\n[node ", start + 1)
	var block := text.substr(start, -1 if end < 0 else end - start)
	var vals := {}
	for key: String in ["offset_left", "offset_top", "offset_right", "offset_bottom"]:
		var re := RegEx.create_from_string("%s = (-?[0-9.]+)" % key)
		var m := re.search(block)
		if m == null:
			return null
		vals[key] = float(m.get_string(1))
	return Rect2(
		Vector2(vals["offset_left"], vals["offset_top"]),
		Vector2(vals["offset_right"] - vals["offset_left"],
			vals["offset_bottom"] - vals["offset_top"])
	)
