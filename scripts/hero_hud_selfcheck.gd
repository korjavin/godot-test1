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
##   7. **VOICE ON THE ROW** (bead godot-test1-xtr.8): the mic badge and the
##      speaking ring, driven through a stub voice node in every mic state and
##      with a speaking hero — plus the two things nothing else can see, that the
##      row with NO voice node is byte-identical to the one bead .7 shipped, and
##      that the numbers and the green this widget mirrors are the real ones.
##      **7b executes the REAL `voice_chat.gd` ladders** with `_is_web` forced on
##      and a `StubMp` in the manager's place, because check 7 only ever meets
##      them off-web, where both return on their first line — so the priority
##      order and the self/remote key split would otherwise be untested code.
##
##      IT MOVED SIDEWAYS AND NOT DOWN, which is worth knowing before you "fix" it:
##      `PerfOverlay` is a Label whose real height is its TEXT's minimum size (316
##      px, not the 276 its offsets declare), so pushing its top down 48 px pushes
##      its bottom into the centre-left minimap — which `minimap_selfcheck`'s own
##      left-edge-column check catches. Moving it right of the row clears both.

const HUD_SCRIPT := preload("res://scripts/hero_hud.gd")
const PLAYER_SCRIPT := preload("res://scripts/player_controller.gd")
## The camera overlay's mirrored copy of `STATE_CAPTIVE` — check 6 binds it. A
## SCRIPT dependency for one constant, not a node reference.
const VOICE_SCRIPT := preload("res://scripts/voice_chat.gd")
## Check 7 binds the speaking green: one colour for a talking teammate, on his
## name tag and on his tile. A SCRIPT dependency for one constant, as above.
const AVATAR_SCRIPT := preload("res://scripts/remote_avatar.gd")
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


## The voice module's stand-in, carrying only the three seams the row reads. Like
## `StubPlayer` this is deliberately not the real `voice_chat.gd`: that file
## answers NOTHING off the web by design (which check 7 asserts against the real
## script), so a live one could never be driven into a transmitting state here.
class StubVoice extends Node:
	var badge: int = 0
	var deafened: bool = false
	var speaking: Array[String] = []

	func mic_badge() -> int:
		return badge

	func is_deafened() -> bool:
		return deafened

	func is_hero_speaking(hero: String) -> bool:
		return speaking.has(hero)


## The MP manager's stand-in, carrying the three methods `voice_chat` asks a room
## about. It exists so check 7b can drive the REAL `voice_chat.gd` — with
## `_is_web` forced on, which is the only way anything headless reaches past that
## file's first line and into the two ladders this bead added.
class StubMp extends Node:
	var online: bool = true
	var me: String = "aaaaaaaa"
	var holders: Dictionary = {}

	func is_online() -> bool:
		return online

	func my_id() -> String:
		return me

	func hero_holder(hero: String) -> String:
		return str(holders.get(hero, ""))


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
	_check_the_video_tile_lookup()
	_check_voice_on_the_row()
	_check_the_voice_seams_in_a_room()


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


func _check_the_video_tile_lookup() -> void:
	"""
	6. The three seams the camera overlay reads (bead godot-test1-xtr.6):
	`hero_names()` is the row this widget is really drawing, `tile_rect()` is where
	a tile is, and `tile_state()` is what that tile is saying.

	The overlay is a DOM <video> positioned at that rect, so a `tile_rect` that
	drifted from `_draw`'s arithmetic puts a teammate's face beside their portrait
	instead of on it — and no self-check can see that in a browser. TWO HALVES,
	because neither sees the other: the geometry below is `tile_rect` measured
	against the row's own pitch (self-consistency — a +1 px offset applied to BOTH
	`_draw` and `tile_rect` is not a bug, it is a moved row), and the TEXT read is
	what binds them, asserting `_draw` steps by `_tile_rect_local` rather than
	arithmetic of its own. Plus: an off-roster name answers an EMPTY rect rather
	than tile zero (which would park a picture over Windman for every hero nobody
	holds), a CAPTIVE tile reports itself so the overlay can leave its cell bars
	alone, and `voice_chat`'s mirrored copy of that constant is the real one.
	"""
	var hud: Control = HUD_SCRIPT.new()
	var stub := StubPlayer.new()
	hud.player = stub
	# The row is measured OUT of the tree, where `tile_rect` answers its own local
	# arithmetic: this check is about that arithmetic agreeing with `_draw`'s, and
	# the screen transform above it is Godot's, not ours, to get right.
	# Nothing is drawn until `_process` has read the roster, so the empty answer is
	# the standalone degrade AND the state the overlay meets on its first poll.
	_check(hud.hero_names().is_empty(),
		"hero_names() answered %s before the row read a roster" % [hud.hero_names()])
	_check(hud.tile_rect(_hero_names()[0]) == Rect2(),
		"tile_rect() offered a rect for a row that is drawing nothing")

	hud._process(0.0)
	var names: PackedStringArray = hud.hero_names()
	_check(names == _hero_names(),
		"hero_names() is %s, but the roster is %s" % [names, _hero_names()])

	# The pitch between two tiles is what `_draw` steps by, and `tile_rect` is the
	# one description both now read.
	var pitch: float = float(HUD_SCRIPT.TILE_SIZE) + float(HUD_SCRIPT.TILE_GAP)
	var previous := Rect2()
	for i: int in names.size():
		var rect: Rect2 = hud.tile_rect(names[i])
		_check(rect.size.x == float(HUD_SCRIPT.TILE_SIZE)
				and rect.size.y == float(HUD_SCRIPT.TILE_SIZE),
			"tile_rect(%s) is %s, not one TILE_SIZE square" % [names[i], rect])
		if i > 0:
			_check(is_equal_approx(rect.position.x - previous.position.x, pitch),
				"tile %d starts %.1f px after tile %d, not the row's %.1f pitch"
					% [i, rect.position.x - previous.position.x, i - 1, pitch])
			_check(rect.position.y == previous.position.y,
				"tile %d is not on the same line as tile %d" % [i, i - 1])
		previous = rect

	_check(hud.tile_rect("no_such_hero") == Rect2(),
		"tile_rect() answered a real rect for a hero that is not on the row")

	# CAPTIVITY IS THE ONE STATE DRAWN AS A SHAPE — bars ACROSS the whole tile —
	# so the overlay has to be able to ask, and skips those tiles entirely.
	stub.captive = [names[1]]
	hud._process(0.0)
	_check(hud.tile_state(names[1]) == HUD_SCRIPT.STATE_CAPTIVE,
		"tile_state(%s) is %d, not STATE_CAPTIVE" % [names[1], hud.tile_state(names[1])])
	_check(hud.tile_state(names[0]) != HUD_SCRIPT.STATE_CAPTIVE,
		"tile_state() called a free hero captive")
	_check(hud.tile_state("no_such_hero") == HUD_SCRIPT.STATE_FREE,
		"tile_state() answered a real state for a hero that is not on the row")
	_check(VOICE_SCRIPT.HERO_HUD_STATE_CAPTIVE == HUD_SCRIPT.STATE_CAPTIVE,
		"voice_chat mirrors STATE_CAPTIVE as %d, but it is %d — the overlay would "
			% [VOICE_SCRIPT.HERO_HUD_STATE_CAPTIVE, HUD_SCRIPT.STATE_CAPTIVE]
		+ "cover the cell bars")
	hud.free()
	stub.free()

	# THE TEXT HALF, and it is the only thing that binds the two. Everything above
	# measures `tile_rect` against itself, so a +1 px offset in BOTH it and `_draw`
	# passes — correctly, that is a moved row — and one in `tile_rect` alone passes
	# too, which is the bug. `_draw` reading the shared `_tile_rect_local` is what
	# makes them one description.
	var source := FileAccess.get_file_as_string("res://scripts/hero_hud.gd")
	if source.is_empty():
		_fail("could not read hero_hud.gd — check 6's binding would pass vacuously")
		Sentinel.done("the_video_tile_lookup")
		return
	var draw_body := source.substr(source.find("func _draw() -> void:"))
	var next_func := draw_body.find("\nfunc ")
	if next_func > 0:
		draw_body = draw_body.substr(0, next_func)
	_check(draw_body.contains("_tile_rect_local("),
		"_draw() no longer steps by _tile_rect_local() — it and tile_rect() are two "
		+ "descriptions of the row again, and check 6 cannot see them disagree")
	Sentinel.done("the_video_tile_lookup")


func _check_voice_on_the_row() -> void:
	"""
	7. THE MIC BADGE AND THE SPEAKING RING (bead godot-test1-xtr.8).

	The row draws entirely off the `_process` snapshot, so `_mic_badge`,
	`_deafened`, `_speaking` and `_pulse` ARE what the player sees — driving them
	through a stub voice node is the only headless read of this feature there can
	be, and the TEXT half at the foot binds `_draw` to them the way check 6 binds
	it to `_tile_rect_local`.

	The load-bearing assertion is the DEGRADE: with no voice node the four
	snapshot fields must be exactly what they were before this bead, or every
	desktop and headless run has grown a HUD element nobody asked for. Its
	mutation control is the same row with a stub attached, which must differ.
	"""
	var heroes := _hero_names()
	if heroes.size() < 3:
		_fail("this check needs at least three heroes to tell one ring from another")
		Sentinel.done("voice_on_the_row")
		return

	# --- The mirrored numbers are the real ones ---------------------------------
	for pair: Array in [
		["MIC_BADGE_NONE", VOICE_SCRIPT.MIC_BADGE_NONE, HUD_SCRIPT.MIC_BADGE_NONE],
		["MIC_BADGE_OFF", VOICE_SCRIPT.MIC_BADGE_OFF, HUD_SCRIPT.MIC_BADGE_OFF],
		["MIC_BADGE_TX", VOICE_SCRIPT.MIC_BADGE_TX, HUD_SCRIPT.MIC_BADGE_TX],
		["MIC_BADGE_MUTED", VOICE_SCRIPT.MIC_BADGE_MUTED, HUD_SCRIPT.MIC_BADGE_MUTED],
		["MIC_BADGE_DENIED", VOICE_SCRIPT.MIC_BADGE_DENIED, HUD_SCRIPT.MIC_BADGE_DENIED],
	]:
		_check(int(pair[1]) == int(pair[2]),
			"hero_hud mirrors %s as %d, but voice_chat says %d — the badge would "
				% [pair[0], int(pair[2]), int(pair[1])]
			+ "draw the wrong state")
	_check(HUD_SCRIPT.COLOR_SPEAKING == AVATAR_SCRIPT.LABEL_SPEAKING_COLOR,
		"the row's speaking green is %s but the name tag's is %s — one language, "
			% [HUD_SCRIPT.COLOR_SPEAKING, AVATAR_SCRIPT.LABEL_SPEAKING_COLOR]
		+ "one colour")

	# --- The real voice module answers NOTHING off the web ----------------------
	# This is what makes every degrade below true of the SHIPPED file and not only
	# of the stub: headless is not web, so both seams must refuse.
	var real_voice: Node = VOICE_SCRIPT.new()
	_check(int(real_voice.mic_badge()) == HUD_SCRIPT.MIC_BADGE_NONE,
		"voice_chat.mic_badge() is %d off the web — it must be NONE"
			% int(real_voice.mic_badge()))
	_check(not real_voice.is_hero_speaking(heroes[0]),
		"voice_chat.is_hero_speaking() answered true off the web")
	_check(not real_voice.is_hero_speaking(""),
		"voice_chat.is_hero_speaking('') answered true")
	real_voice.free()

	# --- THE DEGRADE: no voice node -> bead .7's row, unchanged -----------------
	var hud: Control = HUD_SCRIPT.new()
	var stub := StubPlayer.new()
	hud.player = stub
	stub.available = _all_indices(heroes.size())
	hud._process(0.0)
	_check(hud._mic_badge == HUD_SCRIPT.MIC_BADGE_NONE and hud._speaking == 0
			and hud._pulse == 0 and not hud._deafened,
		"with no voice node the row carries badge=%d speaking=%d pulse=%d deaf=%s"
			% [hud._mic_badge, hud._speaking, hud._pulse, hud._deafened]
		+ " — every desktop run would draw a voice element")

	# --- Every mic state, and the badge colours stay separable ------------------
	var voice := StubVoice.new()
	hud.voice = voice
	var seen: Array[Color] = []
	for badge: int in [HUD_SCRIPT.MIC_BADGE_OFF, HUD_SCRIPT.MIC_BADGE_TX,
			HUD_SCRIPT.MIC_BADGE_MUTED, HUD_SCRIPT.MIC_BADGE_DENIED]:
		voice.badge = badge
		hud._process(0.0)
		_check(hud._mic_badge == badge,
			"the row read mic badge %d when the voice node said %d"
				% [hud._mic_badge, badge])
		var color: Color = hud.mic_badge_color(badge)
		_check(not seen.has(color),
			"mic badge %d draws in %s, a colour another state already uses"
				% [badge, color])
		seen.append(color)
	_check(hud.mic_badge_color(HUD_SCRIPT.MIC_BADGE_TX) == HUD_SCRIPT.COLOR_SPEAKING,
		"a transmitting mic is not drawn in the speaking green — 'my mic is open' "
		+ "and 'somebody is talking' must read as one thing")

	# --- Deafen is a SECOND axis, and it needs voice to be live -----------------
	voice.badge = HUD_SCRIPT.MIC_BADGE_TX
	voice.deafened = true
	hud._process(0.0)
	_check(hud._deafened,
		"deafened was not read while the mic badge was live")
	voice.badge = HUD_SCRIPT.MIC_BADGE_NONE
	hud._process(0.0)
	_check(not hud._deafened,
		"a headphone-slash was drawn on a row with no voice at all")

	# --- THE SPEAKING RING, per tile -------------------------------------------
	voice.badge = HUD_SCRIPT.MIC_BADGE_OFF
	voice.deafened = false
	voice.speaking = [heroes[1]]
	hud._process(0.0)
	_check(hud._speaking == (1 << 1),
		"one speaking hero lit mask %d, not just tile 1" % hud._speaking)
	_check(hud._pulse >= 0 and hud._pulse < HUD_SCRIPT.RING_PULSE_STEPS,
		"the ring pulse is %d, outside 0..%d"
			% [hud._pulse, HUD_SCRIPT.RING_PULSE_STEPS - 1])

	voice.speaking = [heroes[0], heroes[2]]
	hud._process(0.0)
	_check(hud._speaking == (1 | (1 << 2)),
		"two speaking heroes lit mask %d, not tiles 0 and 2" % hud._speaking)

	# THE MUTATION CONTROL, and it is the one that matters: a voice node still
	# claiming somebody is speaking, but no voice on this row (NONE), must light
	# nothing — otherwise a solo run would grow rings the moment a stale voice
	# node was left in the tree.
	voice.badge = HUD_SCRIPT.MIC_BADGE_NONE
	hud._process(0.0)
	_check(hud._speaking == 0 and hud._pulse == 0,
		"a speaking claim outside a room lit mask %d — the ring must be gated on "
			% hud._speaking
		+ "there being voice at all")

	# --- WHERE THE BADGE IS DRAWN, which `_draw` cannot be asked headless --------
	# `badge_on_tile` / `deafen_on_tile` ARE `_draw`'s two decisions, and without
	# them a badge drawn in the NONE state or a headphone-slash drawn on every
	# tile would be invisible to this file: a control outside the tree has no
	# canvas item, so the painting itself can never run here.
	voice.badge = HUD_SCRIPT.MIC_BADGE_TX
	voice.deafened = true
	stub.current_character_index = 1
	hud._process(0.0)
	_check(hud.badge_on_tile(1) == HUD_SCRIPT.MIC_BADGE_TX,
		"the badge is not on the tile of the hero being driven (got %d on tile 1)"
			% hud.badge_on_tile(1))
	for other: int in [0, 2]:
		_check(hud.badge_on_tile(other) == HUD_SCRIPT.MIC_BADGE_NONE,
			"a second mic badge appeared on tile %d — one badge on the row" % other)
		_check(not hud.deafen_on_tile(other),
			"a headphone-slash appeared on tile %d, away from the mic badge" % other)
	_check(hud.deafen_on_tile(1),
		"the headphone-slash is not on the badge's own tile while deafened")
	voice.deafened = false
	hud._process(0.0)
	_check(not hud.deafen_on_tile(1),
		"a headphone-slash is drawn while the player is not deafened")
	voice.badge = HUD_SCRIPT.MIC_BADGE_NONE
	hud._process(0.0)
	_check(hud.badge_on_tile(1) == HUD_SCRIPT.MIC_BADGE_NONE,
		"a mic badge is drawn on a row with no voice at all — every desktop run "
		+ "would carry one")

	# THE BENCHED HERO, and it is the reason the badge rides the DRIVEN tile and
	# not the ACTIVE one. A captured hero stays the body you are in (the prison
	# role never switches character), captivity OUTRANKS active, so the row has no
	# ACTIVE tile at all — which is exactly when somebody is on the microphone.
	voice.badge = HUD_SCRIPT.MIC_BADGE_TX
	stub.captive = [heroes[1]]
	hud._process(0.0)
	_check(hud.tile_state(heroes[1]) == HUD_SCRIPT.STATE_CAPTIVE,
		"this sub-check needs tile 1 captive to mean anything")
	for s: int in hud._states:
		_check(s != HUD_SCRIPT.STATE_ACTIVE,
			"a captive driven hero must leave NO active tile, or this proves nothing")
	_check(hud.badge_on_tile(1) == HUD_SCRIPT.MIC_BADGE_TX,
		"the mic badge vanished while the driven hero was in a cell — that is the "
		+ "one moment a benched player is certainly talking")
	stub.captive = []

	# A voice node that predates either seam degrades, it does not error.
	hud.voice = Node.new()
	hud._process(0.0)
	_check(hud._mic_badge == HUD_SCRIPT.MIC_BADGE_NONE and hud._speaking == 0,
		"a voice node with neither method must read as no voice, not as %d/%d"
			% [hud._mic_badge, hud._speaking])
	hud.voice.free()
	voice.free()
	stub.free()
	hud.free()

	# --- THE TEXT HALF: `_draw` really reads the snapshot -----------------------
	var source := FileAccess.get_file_as_string("res://scripts/hero_hud.gd")
	if source.is_empty():
		_fail("could not read hero_hud.gd — check 7's binding would pass vacuously")
		Sentinel.done("voice_on_the_row")
		return
	var draw_body := source.substr(source.find("func _draw() -> void:"))
	var next_func := draw_body.find("\nfunc ")
	if next_func > 0:
		draw_body = draw_body.substr(0, next_func)
	# It must ASK the two decisions rather than re-deriving them: everything above
	# drives `badge_on_tile` / `deafen_on_tile`, and a `_draw` that painted a badge
	# off `_mic_badge` and `_badge_index` directly would be a third description of
	# a rule this file can otherwise only measure in one place.
	for seam: String in ["badge_on_tile(", "deafen_on_tile(", "_speaking"]:
		_check(draw_body.contains(seam),
			"_draw() no longer reads `%s` — everything check 7 measures would be "
				% seam + "a decision nothing draws")
	Sentinel.done("voice_on_the_row")


func _check_the_voice_seams_in_a_room() -> void:
	"""
	7b. THE TWO LADDERS INSIDE `voice_chat.gd`, executed rather than stubbed.

	Check 7 drives the ROW through a stub, and touches the real module only
	off-web — where both seams short-circuit on their first line. So not one line
	of `mic_badge()`'s priority order or `is_hero_speaking()`'s holder resolution
	would run anywhere in this suite, and `voice_selfcheck`'s `PUBLIC_CALLS` rows
	only prove they never reach the bridge, never what they answer.

	Both are pure over instance state plus the manager, so forcing `_is_web` on
	and hanging a `StubMp` off `_mp` runs them exactly as a browser would — and
	`mic_badge()` reads the CACHED `_reported_mic` rather than `mic_denied()`
	precisely so no bridge is involved even here (see its docstring: its caller is
	a `_process`).
	"""
	var heroes := _hero_names()
	var voice: Node = VOICE_SCRIPT.new()
	var mp := StubMp.new()
	voice._is_web = true
	voice._mp = mp
	mp.holders = {heroes[0]: mp.me, heroes[1]: "bbbbbbbb"}

	# --- mic_badge(): the priority order, top down --------------------------
	_check(int(voice.mic_badge()) == HUD_SCRIPT.MIC_BADGE_OFF,
		"a live room with the mic idle reads %d, not OFF" % int(voice.mic_badge()))
	voice._tx = true
	_check(int(voice.mic_badge()) == HUD_SCRIPT.MIC_BADGE_TX,
		"a transmitting mic reads %d, not TX" % int(voice.mic_badge()))
	# MUTE WINS OVER THE MODE — the browser transmits on `tx && !muted`, and this
	# is that rule read back out. Both flags set at once is the whole assertion.
	voice._mic_muted = true
	_check(int(voice.mic_badge()) == HUD_SCRIPT.MIC_BADGE_MUTED,
		"a muted mic that is also transmitting reads %d — mute must win"
			% int(voice.mic_badge()))
	# And a DENIED microphone outranks both: it can never transmit at all.
	voice._reported_mic = VOICE_SCRIPT.MIC_DENIED
	_check(int(voice.mic_badge()) == HUD_SCRIPT.MIC_BADGE_DENIED,
		"a denied mic reads %d, not DENIED" % int(voice.mic_badge()))
	voice._reported_mic = VOICE_SCRIPT.MIC_IDLE
	voice._mic_muted = false
	# OUT OF THE ROOM IS NOTHING, even on the web with the mic wide open.
	mp.online = false
	_check(int(voice.mic_badge()) == HUD_SCRIPT.MIC_BADGE_NONE,
		"a transmitting mic outside a room reads %d — there is no room to badge"
			% int(voice.mic_badge()))
	mp.online = true

	# --- is_hero_speaking(): the self / remote split ------------------------
	# The browser reports our own microphone under `me` and every peer under its
	# lobby id (`S.peers` is remote-only), so the two halves take DIFFERENT keys —
	# which is why only a levels string that carries one and not the other can
	# tell a correct mapping from one that asks for our lobby id.
	voice.apply_levels("%s:80" % VOICE_SCRIPT.SELF_LEVEL_KEY)
	_check(voice.is_hero_speaking(heroes[0]),
		"our own hero's ring did not light off the `%s` level key"
			% VOICE_SCRIPT.SELF_LEVEL_KEY)
	_check(not voice.is_hero_speaking(heroes[1]),
		"a teammate's hero lit off OUR microphone level")
	voice._speaking_until.clear()
	voice.apply_levels("bbbbbbbb:80")
	_check(voice.is_hero_speaking(heroes[1]),
		"a speaking peer's hero did not light off that peer's lobby id")
	_check(not voice.is_hero_speaking(heroes[0]),
		"our own hero lit off a TEAMMATE's level")
	# A hero nobody holds, and a room nobody is in.
	_check(not voice.is_hero_speaking(heroes[2]),
		"a hero nobody holds lit a speaking ring")
	_check(not voice.is_hero_speaking(""),
		"the empty hero name lit a speaking ring")
	mp.online = false
	_check(not voice.is_hero_speaking(heroes[1]),
		"a ring lit outside a room")
	mp.online = true
	# A manager that predates `hero_holder` degrades rather than erroring.
	var bare := Node.new()
	voice._mp = bare
	_check(not voice.is_hero_speaking(heroes[1]),
		"a manager with no hero_holder() must read as nobody speaking")
	_check(int(voice.mic_badge()) == HUD_SCRIPT.MIC_BADGE_NONE,
		"a manager with no is_online() must read as no room")
	bare.free()
	voice._mp = null
	mp.free()
	voice.free()
	Sentinel.done("the_voice_seams_in_a_room")


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
