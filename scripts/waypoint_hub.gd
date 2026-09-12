extends Control
## ============================================================================
## THE WAYPOINT HUB — the enter edge that finds a circle, and the only hand that
## lights a beam
## ============================================================================
## Epic `godot-test1-sc6`, bead .2. `.1` put eleven indigo rings in the world with
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
## Built as ONE NODE with ONE SCRIPT LINE in `scenes/main.tscn` and no layout at
## all — this Control draws nothing, it is a tick with a group lookup. The
## `landmark_toast.gd` idiom minus the card, because the card it would have built
## already exists and is `announce()`'s.

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

## The circle this approach belongs to, as an index into
## `TerrainWaypoints.waypoint_sites()`, or -1 when re-armed. `landmark_toast`'s
## `_city_active` exactly — including why the FIRST arrival is latched rather than
## the nearest one winning every tick.
var _standing_on: int = -1

## Seconds accumulated toward the next tick.
var _tick_timer: float = 0.0


func _ready() -> void:
	# This Control draws nothing and must never eat a click: the MP panel, the
	# touch buttons and the start overlay share this CanvasLayer, and a Control
	# over them that swallowed input would be invisible and maddening.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# So bead .4's travel panel can ask where the hero is standing without a hard
	# reference — group discovery, like every other cross-system hookup here.
	add_to_group("waypoint_hub")


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


func _process(delta: float) -> void:
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

	# The cue. `play_level_up` is a BORROWED sound and it is marked as such: bead
	# .5 brings `play_waypoint_found` (three rising taps off the coin) and this
	# line becomes that one. The project's standard null-safe group + has_method
	# shape, so a scene with no SoundManager resolves silently.
	var sound := get_tree().get_first_node_in_group("sound_manager")
	if sound != null and sound.has_method("play_level_up"):
		sound.call("play_level_up")

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
