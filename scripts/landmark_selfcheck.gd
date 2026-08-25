extends SceneTree
## Headless self-check for the geo-educational landmarks.
##
##   godot --headless --path . --script res://scripts/landmark_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints what failed and exits 1 — the
## same shape as fauna_selfcheck.gd and minimap_selfcheck.gd, and it exists for
## the same reason those do: it guards the four things about this feature that
## fail SILENTLY, with no error anywhere and nothing to see until a player
## happens to walk into the broken case.
##
##   1. THE DECLARED RADIUS IS A TRUE BOUND ON THE STONE. Every builder in the
##      LANDMARKS registry is called for real, over many seeds, and every box it
##      emits is measured against the radius the registry declares for it. That
##      radius is what the placement test, the coin ring, the crocodile-exclusion
##      footprint and LANDMARK_EDGE_MARGIN are all sized from — so a builder that
##      overflows it puts half an Eiffel Tower across a chunk seam, and nothing
##      anywhere errors. It is also the only check that calls the builders at all,
##      which is what makes `builder` being a method-name STRING (the price of a
##      const registry) safe: a typo'd or renamed method fails here rather than in
##      one chunk in fifty, on somebody's machine.
##   2. THE CONSTANT CHAIN HOLDS. Three inequalities that a future retune breaks
##      silently: every registry radius <= LANDMARK_RADIUS (or the placement test
##      stops bounding the shape it admits), LANDMARK_EDGE_MARGIN > LANDMARK_RADIUS
##      (or a landmark straddles a seam), and the boss-exclusion arithmetic
##      LANDMARK_ROAD_CLEARANCE > LANDMARK_RADIUS + hypot(BOSS_FORWARD_OFFSET,
##      BOSS_LATERAL_MAX) — which is what makes "a boss can never stand inside a
##      landmark" true BY CONSTRUCTION, with zero edits to spawn_bosses_in_chunk.
##      Nothing else in the game asserts any of the three.
##   3. EVERY REGISTRY FACT IS ACTUALLY TRANSLATED. The educational payload is the
##      whole point of the feature, and adding a ninth landmark while forgetting
##      its two CSV rows is invisible to locale_selfcheck.gd — that file validates
##      the rows that EXIST, and a missing row is by design a silent fall-through
##      to readable English. Here the registry is the source of truth, so a
##      forgotten row is a failure. Deliberately NOT asserted for `name`: four of
##      the eight names are the same word in German and therefore correctly have
##      NO CSV ROW AT ALL (locale_selfcheck.gd fails a de column identical to en).
##   4. THE TOAST FIRES ONCE PER APPROACH AND RE-ARMS ON LEAVING. Driven against
##      the real landmark_toast.gd with stub player and marker nodes, because
##      every way this breaks — a card that never shows, one that re-pops every
##      quarter second, one showing the wrong landmark's fact, one that never
##      re-arms — looks like ordinary behaviour from inside the script.
##
## HOUSE RULE, followed throughout: every check is an EFFECT measurement with a
## negative control, never a getter read-back. Check 1 measures emitted geometry
## rather than reading the returned radius (a builder returning `entry.radius`
## verbatim would pass a read-back while emitting anything at all). Check 4's
## step 1 requires the card HIDDEN before any of the "it shows" steps mean
## anything, and its step 4 sits the player in the DEAD BAND — outside the
## approach radius but inside the leave radius — because that is the only place
## APPROACH_PAD and LEAVE_PAD being equal is observable.
##
## MUTATION-TESTED (all four caught, re-run these if you touch this file):
##   (a) LANDMARKS[0].radius 7.6 -> 4.0  ->  FAIL: Stonehenge (seed 22): emits
##       stone out to 6.35 m, past its declared radius 4.00 — it would straddle a
##       chunk seam.  And 7.6 -> 12.0 -> FAIL: builder returned radius 7.60 but
##       the registry declares 12.00, plus check 2's "above LANDMARK_RADIUS 9.50".
##   (b) landmark_toast.LEAVE_PAD 14.0 -> 6.0 (== APPROACH_PAD, no dead band)
##       ->  FAIL: the card re-showed after a dead-band excursion.
##   (c) the "A 330 m iron tower in Paris…" row deleted from ui.csv (+ --import)
##       ->  FAIL: fact for Eiffel Tower is not translated in de.
##   (d) LANDMARK_ROAD_CLEARANCE 22.0 -> 18.0
##       ->  FAIL: LANDMARK_ROAD_CLEARANCE (18.00) must exceed LANDMARK_RADIUS
##       (9.50) + boss reach (8.94) = 18.44.
##
## Don't grow this into a suite.

const TERRAIN_SCRIPT: String = "res://scripts/endless_terrain.gd"
const TOAST_SCRIPT: String = "res://scripts/landmark_toast.gd"

## Seeds per builder for check 1. The shapes are random-driven (stone jitter,
## per-tier yaw, leg splay), so one seed proves nothing — 25 is enough that a
## builder overflowing on an unlucky draw cannot pass by luck, and 8 builders ×
## 25 seeds still runs in well under a second because nothing enters the tree.
const SEEDS_PER_BUILDER: int = 25

## Float slack on the radius comparison. The measurement is a sum of products of
## floats; a builder whose worst corner lands exactly on its declared radius is
## correct, not a failure.
const RADIUS_EPSILON: float = 0.001

## The unit cube's 8 corners. create_box builds each instance transform as
## Basis(UP, yaw) * Basis(RIGHT, tilt), scaled_local by the box dimensions, over
## the shared 1×1×1 BoxMesh — so transforming these ±0.5 corners by that basis
## gives the box's real rotated extent, tilt included. That is why check 1
## measures corners rather than a half-diagonal formula: it needs no assumption
## about which axes a builder rotated.
const UNIT_CORNERS: Array[Vector3] = [
	Vector3(-0.5, -0.5, -0.5), Vector3(-0.5, -0.5, 0.5),
	Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, 0.5, 0.5),
	Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5),
	Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5),
]

var _failures: Array[String] = []


func _initialize() -> void:
	# _initialize() cannot await, and check 4 has to let the toast's _ready() run
	# before it can touch the labels that _ready() builds — so the whole run is a
	# coroutine and the tree keeps processing until it calls quit().
	_run()


func _run() -> void:
	var terrain_script: GDScript = load(TERRAIN_SCRIPT)
	# get_script_constant_map() is how a `const` is read from outside: constants
	# are not properties, so `terrain.get("LANDMARK_RADIUS")` answers null and a
	# check written that way would pass vacuously against nothing at all.
	var consts: Dictionary = terrain_script.get_script_constant_map()
	var registry: Array = consts.get("LANDMARKS", [])

	if registry.is_empty():
		_fail("endless_terrain.gd has no LANDMARKS registry")
	else:
		_check_radii(terrain_script, registry)
		_check_constants(consts, registry)
		_check_facts(registry)
		await _check_toast(registry)

	if _failures.is_empty():
		print("landmarks: %d builders × %d seeds measured, toast once-per-approach OK"
				% [registry.size(), SEEDS_PER_BUILDER])
		print("SELFCHECK OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


# ============================================================================
# CHECK 1 — the declared radius bounds the stone the builder actually emits
# ============================================================================

func _check_radii(terrain_script: GDScript, registry: Array) -> void:
	"""
	Call every builder for real and measure what it emitted.

	The terrain node is DETACHED (never added to the tree) on purpose: _ready()
	rolls a run seed, builds fog, materials and the first chunks, none of which a
	builder needs — a builder touches only create_box, _spawn_artifact_accent and
	the shared ember material. Keeping it out of the tree keeps this check to the
	geometry it is about.
	"""
	var terrain := Node3D.new()
	terrain.set_script(terrain_script)

	# The widest emitted extent per builder, kept so the report can print the real
	# numbers (a check that only says "ok" tells the next reader nothing about how
	# much headroom a radius has).
	for entry_variant: Variant in registry:
		var entry: Dictionary = entry_variant
		var declared: float = float(entry["radius"])
		var place: String = String(entry["name"])
		var builder: String = String(entry["builder"])

		if not terrain.has_method(builder):
			_fail("%s: no such builder method %s — the registry's method-name String is stale"
					% [place, builder])
			continue

		var worst_overall := 0.0
		var seed_index := 0
		while seed_index < SEEDS_PER_BUILDER:
			var block_batch: Array = []
			var block_body := StaticBody3D.new()
			var chunk := MeshInstance3D.new()
			var rng := RandomNumberGenerator.new()
			# Distinct per (builder, seed) so no two rows measure the same shape.
			rng.seed = hash(Vector3i(seed_index, builder.hash(), 0))

			var footprint: Variant = terrain.call(builder, Vector3.ZERO, rng, chunk, block_batch, block_body)

			if not (footprint is Dictionary) or not (footprint as Dictionary).has("radius") \
					or not (footprint as Dictionary).has("top"):
				_fail("%s: builder did not return { radius, top }" % place)
				block_body.free()
				chunk.free()
				break

			if block_batch.is_empty():
				_fail("%s (seed %d): builder emitted no geometry at all" % [place, seed_index])

			# The returned radius must agree with the registry's, or the footprint
			# the crocodile exclusion and the coin ring use is not the one the
			# placement test cleared.
			var returned: float = float((footprint as Dictionary)["radius"])
			if absf(returned - declared) > RADIUS_EPSILON:
				_fail("%s (seed %d): builder returned radius %.2f but the registry declares %.2f"
						% [place, seed_index, returned, declared])

			var worst := _worst_horizontal_extent(block_batch)
			worst_overall = maxf(worst_overall, worst)
			if worst > declared + RADIUS_EPSILON:
				_fail("%s (seed %d): emits stone out to %.2f m, past its declared radius %.2f — it would straddle a chunk seam"
						% [place, seed_index, worst, declared])

			block_body.free()
			chunk.free()
			seed_index += 1

		# The negative control for this row: a radius that bounds the stone with
		# metres to spare is not "safe", it is UNMEASURED — the placement test, the
		# reward ring and the footprint would all be sized for a shape that isn't
		# there, reserving ground and repelling crocodiles for nothing. Half the
		# declared radius unused means the number was guessed, not measured.
		if worst_overall > 0.0 and worst_overall < declared * 0.5:
			_fail("%s emits stone out to %.2f m but declares radius %.2f — not a true bound, just a large one"
					% [place, worst_overall, declared])

	terrain.free()


func _worst_horizontal_extent(block_batch: Array) -> float:
	"""
	The furthest any emitted box reaches from the landmark's centre, measured in
	the XZ plane (the only plane a chunk seam exists in). Height is irrelevant: a
	tower is allowed to be 18 m tall inside a 6.2 m radius.
	"""
	var worst := 0.0
	for item_variant: Variant in block_batch:
		var item: Dictionary = item_variant
		var t: Transform3D = item["transform"]
		for corner: Vector3 in UNIT_CORNERS:
			var p: Vector3 = t.origin + t.basis * corner
			worst = maxf(worst, Vector2(p.x, p.z).length())
	return worst


# ============================================================================
# CHECK 2 — the constant chain
# ============================================================================

func _check_constants(consts: Dictionary, registry: Array) -> void:
	"""
	Three inequalities. Each one is currently true by a comfortable margin, which
	is exactly why nothing would notice if a retune made one false.
	"""
	var radius: float = float(consts["LANDMARK_RADIUS"])
	var edge_margin: float = float(consts["LANDMARK_EDGE_MARGIN"])
	var road_clearance: float = float(consts["LANDMARK_ROAD_CLEARANCE"])
	var boss_forward: float = float(consts["BOSS_FORWARD_OFFSET"])
	var boss_lateral: float = float(consts["BOSS_LATERAL_MAX"])

	# (i) LANDMARK_RADIUS is handed to _biome_spot_ok as "the widest this could
	# be", before the shape's real radius is known. A registry entry above it
	# means the placement test cleared less ground than the builder fills.
	for entry_variant: Variant in registry:
		var entry: Dictionary = entry_variant
		if float(entry["radius"]) > radius + RADIUS_EPSILON:
			_fail("%s declares radius %.2f, above LANDMARK_RADIUS %.2f — the placement test no longer bounds it"
					% [String(entry["name"]), float(entry["radius"]), radius])

	# (ii) A whole landmark has to fit inside its own chunk, or it straddles a
	# seam and the neighbouring chunk knows nothing about it.
	if edge_margin <= radius:
		_fail("LANDMARK_EDGE_MARGIN (%.2f) must exceed LANDMARK_RADIUS (%.2f)"
				% [edge_margin, radius])

	# (iii) BOSS EXCLUSION BY CONSTRUCTION. The road-clearance test measures the
	# distance to road STATION CENTRES, and a boss does not stand on its station
	# centre: _boss_at offsets it BOSS_FORWARD_OFFSET along the tangent AND up to
	# BOSS_LATERAL_MAX across it, so BOTH legs belong in the bound (the lateral
	# leg alone understates it, the same trap the camp banner records). With this
	# inequality true, spawn_bosses_in_chunk needs no edit and never can be given
	# one — the exclusion is arithmetic, not code.
	var boss_reach := sqrt(boss_forward * boss_forward + boss_lateral * boss_lateral)
	if road_clearance <= radius + boss_reach:
		_fail("LANDMARK_ROAD_CLEARANCE (%.2f) must exceed LANDMARK_RADIUS (%.2f) + boss reach (%.2f) = %.2f — a boss could stand inside a landmark"
				% [road_clearance, radius, boss_reach, radius + boss_reach])


# ============================================================================
# CHECK 3 — every registry fact really is translated
# ============================================================================

func _check_facts(registry: Array) -> void:
	"""
	Set the locale to de and require every fact to come back as something other
	than itself. The keys ARE the English source strings, so an untranslated fact
	returns unchanged — readable, and therefore invisible to everything except
	this line.
	"""
	var restore: String = TranslationServer.get_locale()
	TranslationServer.set_locale("de")

	for entry_variant: Variant in registry:
		var entry: Dictionary = entry_variant
		var fact: String = String(entry["fact"])
		if tr(fact) == fact:
			_fail("fact for %s is not translated in de — its ui.csv row is missing (the educational payload is the feature)"
					% String(entry["name"]))

	# The negative control that keeps the assertion above honest: this string is
	# in no table, so it MUST come back unchanged. If it does not, the locale did
	# not take (a missing imported table makes tr() an identity function, which
	# would turn the loop above into a check that always fails, and a broken
	# TranslationServer would be reported as eight missing CSV rows).
	var absent := "landmark_selfcheck: no such key, deliberately"
	if tr(absent) != absent:
		_fail("tr() altered a key that is in no table — the check above cannot be trusted")

	TranslationServer.set_locale(restore)


# ============================================================================
# CHECK 4 — the toast fires once per approach and re-arms on leaving
# ============================================================================

## The stub player. The toast reads exactly one thing off the "player" group
## node — global_position — so that is all this is; nothing else about the real
## player is relevant, and a full player scene would drag in the whole HUD.
class StubPlayer extends Node3D:
	pass


func _check_toast(registry: Array) -> void:
	var toast_script: GDScript = load(TOAST_SCRIPT)
	var approach_pad: float = float(toast_script.get_script_constant_map()["APPROACH_PAD"])
	var leave_pad: float = float(toast_script.get_script_constant_map()["LEAVE_PAD"])

	var player := StubPlayer.new()
	player.add_to_group("player")
	root.add_child(player)

	# TWO markers, and that is the negative control for the TEXT assertion: with
	# one marker, a card that always showed registry entry 0 would pass. The
	# player is parked by the SECOND one, so the card has to have read the marker
	# it was actually near.
	var decoy := _make_marker(registry[0], Vector3(400.0, 0.0, 0.0))
	var marker := _make_marker(registry[registry.size() - 1], Vector3.ZERO)
	root.add_child(decoy)
	root.add_child(marker)

	var entry: Dictionary = registry[registry.size() - 1]
	var radius: float = float(entry["radius"])

	var toast := Control.new()
	toast.set_script(toast_script)
	root.add_child(toast)
	# One frame, so the toast's _ready() runs and builds the two labels this check
	# reads. Nothing added from _initialize() has had _ready() called yet — the
	# same trap minimap_selfcheck.gd documents.
	await process_frame
	# The scan is driven BY HAND from here on, so the sequence is exact instead of
	# depending on how many 0.25 s ticks a headless frame happens to cover.
	toast.set_process(false)

	# --- Step 1: far away → nothing on screen. NEGATIVE CONTROL: without it, a
	# toast stuck permanently visible would pass every "it shows" step below.
	player.global_position = Vector3(0.0, 0.0, radius + leave_pad + 50.0)
	toast.call("_scan")
	if toast.visible:
		_fail("toast: the card is visible with the player %.0f m from every landmark"
				% (radius + leave_pad + 50.0))

	# --- Step 2: inside the approach radius → the card shows THIS landmark.
	player.global_position = Vector3(0.0, 0.0, radius + approach_pad - 1.0)
	toast.call("_scan")
	if not toast.visible:
		_fail("toast: the card did not show inside the approach radius")
	var shown_name: String = toast.get("name_label").text
	var shown_fact: String = toast.get("fact_label").text
	if shown_name != String(entry["name"]) or shown_fact != String(entry["fact"]):
		_fail("toast: showed \"%s\" / \"%s\", expected \"%s\" / \"%s\" — it read the wrong marker"
				% [shown_name, shown_fact, String(entry["name"]), String(entry["fact"])])

	# --- Step 3: still inside → must NOT re-show. Clearing the labels first is
	# what makes that measurable: _show() is the only thing that writes them, so
	# labels still empty after the tick means it did not run. Asserting
	# `visible` here would prove nothing — the card is legitimately still up.
	_clear_labels(toast)
	toast.call("_scan")
	if not _labels_clear(toast):
		_fail("toast: the card re-showed while the player stood still inside the approach radius — the once-per-approach latch is gone")

	# --- Step 4: THE DEAD BAND. Outside the approach radius but inside the leave
	# radius, then back in. Nothing may re-show: the approach has not ended.
	# This is the only step where APPROACH_PAD == LEAVE_PAD is observable, and
	# without it a toast with no hysteresis flickers its card on and off for a
	# player standing on the trigger boundary.
	player.global_position = Vector3(0.0, 0.0, radius + (approach_pad + leave_pad) * 0.5)
	toast.call("_scan")
	player.global_position = Vector3(0.0, 0.0, radius + approach_pad - 1.0)
	toast.call("_scan")
	if not _labels_clear(toast):
		_fail("toast: the card re-showed after a dead-band excursion — APPROACH_PAD and LEAVE_PAD are no longer a dead band")

	# --- Step 5: genuinely left, then came back → the card shows again. This is
	# the re-arm half, and it is deliberately the same landmark: re-approaching
	# one you have already seen shows the card again, on purpose (the card IS the
	# reward for the detour).
	player.global_position = Vector3(0.0, 0.0, radius + leave_pad + 5.0)
	toast.call("_scan")
	player.global_position = Vector3(0.0, 0.0, radius + approach_pad - 1.0)
	toast.call("_scan")
	if _labels_clear(toast):
		_fail("toast: the card did not re-show after the player left and came back — it never re-arms")

	toast.queue_free()
	marker.queue_free()
	decoy.queue_free()
	player.queue_free()


func _make_marker(entry: Dictionary, at: Vector3) -> Node3D:
	"""
	A stand-in for the bare Node3D spawn_landmark_in_chunk parents to the chunk:
	group "landmark" plus the same three metas, which are the whole contract
	between the world generator and the toast.
	"""
	var marker := Node3D.new()
	marker.add_to_group("landmark")
	marker.position = at
	marker.set_meta("name_key", entry["name"])
	marker.set_meta("fact_key", entry["fact"])
	marker.set_meta("radius", entry["radius"])
	return marker


func _clear_labels(toast: Control) -> void:
	toast.get("name_label").text = ""
	toast.get("fact_label").text = ""


func _labels_clear(toast: Control) -> bool:
	return toast.get("name_label").text.is_empty() and toast.get("fact_label").text.is_empty()
