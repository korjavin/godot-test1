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
##   2. THE CONSTANT CHAIN HOLDS. Four inequalities that a future retune breaks
##      silently: every registry radius <= LANDMARK_RADIUS (or the placement test
##      stops bounding the shape it admits), LANDMARK_EDGE_MARGIN > LANDMARK_RADIUS
##      (or a landmark straddles a seam), the boss-exclusion arithmetic
##      LANDMARK_ROAD_CLEARANCE > LANDMARK_RADIUS + hypot(BOSS_FORWARD_OFFSET,
##      BOSS_LATERAL_MAX) — which is what makes "a boss can never stand inside a
##      landmark" true BY CONSTRUCTION, with zero edits to spawn_bosses_in_chunk —
##      and LANDMARK_RADIUS + LANDMARK_COIN_RING_PAD_MAX <= LANDMARK_EDGE_MARGIN,
##      which is the same seam rule for the REWARD COINS, which sit outside the
##      stone the third inequality bounds. Nothing else asserts any of the four.
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
##      re-arms — looks like ordinary behaviour from inside the script. Its step 6
##      covers the case ONE marker cannot: two landmarks whose trigger zones
##      overlap (reachable — see the step's comment), where a `nearest != _active`
##      selection rule raises a fresh card 4 times a second without the player ever
##      leaving either one.
##   5. THE TRIGGER DISTANCE IS DERIVED FROM THE MARKER'S RADIUS. Its own check,
##      because check 4 drives ONE marker at ONE radius and therefore passes in
##      full against a toast whose range tests are hardcoded metre counts —
##      verified by mutating a copy that way (all five of check 4's steps still
##      passed). The radius meta is the reason the toast is shaped as it is, so
##      losing it is a silent regression of the feature, not a detail. One probe
##      distance, two markers of different radius: in range for the wider, out of
##      range for the narrower. Same failure class, and same answer, as
##      minimap_selfcheck.gd's two-zoom crocodile probe.
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
## Two things are deliberately NOT asserted, both because the assertion could only
## ever fail a build that is not broken: that a declared radius is not much LARGER
## than the stone (over-declaring is safe for every rule the radius feeds — see the
## note at the end of check 1), and anything about a key that is absent from the
## CSV (absence IS the design for a name that is the same word in German).
##
## MUTATION-TESTED (all eight caught, re-run these if you touch this file):
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
##   (e) LANDMARK_COIN_RING_PAD_MAX 2.0 -> 4.0 (the artifacts' value, which is the
##       drift this exists to catch)  ->  FAIL: LANDMARK_RADIUS (9.50) +
##       LANDMARK_COIN_RING_PAD_MAX (4.00) = 13.50 exceeds LANDMARK_EDGE_MARGIN
##       (12.00) — a reward coin can land outside its own chunk.
##   (f) landmark_toast: both range tests changed to flat metre counts (15.0 / 23.0)
##       so the `radius` meta is ignored entirely  ->  FAIL: at 13.40 m from a
##       radius-5.40 landmark the card showed, expected it not to show. NOTE all of
##       check 4 passes under this mutation — that is why check 5 exists.
##   (g) landmark_toast's selection rule `_active == null and nearest != null`
##       reverted to `nearest != null and nearest != _active`  ->  FAIL: a card was
##       raised for a second landmark while the player was still inside the first.
##       (Steps 1-5 all pass under it: they drive one marker.)
##   (h) LEAVE_PAD 14.0 -> 6.0 also trips the direct inequality in step 4, which is
##       there because the probe alone decides that case on float32 rounding — see
##       the comment at that assertion.
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
		await _check_toast_radius_derived(registry)

	if _failures.is_empty():
		print("landmarks: %d builders × %d seeds measured, toast once-per-approach + radius-derived trigger OK"
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

		# DELIBERATELY NOT ASSERTED: "the radius is not much LARGER than the stone".
		# Over-declaring is safe for every rule the radius feeds — the seam bound,
		# the footprint and the reward ring all stay correct, the landmark merely
		# reserves a little ground it does not use. So a tightness test can only
		# ever fail a build that is not broken, and this one nearly did: Liberty's
		# widest box is the 4.6 m pedestal, whose rotated half-extent is
		# 2.3 * (|cos y| + |sin y|), i.e. 2.30 m at an axis-aligned yaw and 3.25 m
		# at 45 degrees, against a 2.70 m threshold — about a quarter of yaws are
		# under it, and it passed only because `worst_overall` is a max over
		# SEEDS_PER_BUILDER. Lower that constant, or nudge Liberty's declared 5.4
		# up, and a correct build starts failing at random.
		pass

	terrain.free()


func _worst_horizontal_extent(block_batch: Array) -> float:
	"""
	The furthest any emitted box reaches from the landmark's centre, measured in
	the XZ plane (the only plane a chunk seam exists in). Height is irrelevant: a
	tower is allowed to be 18 m tall inside a 6.2 m radius.

	The corners are transformed by the box's REAL Transform3D, so yaw and tilt are
	both accounted for exactly — no half-diagonal approximation to get wrong.

	ponytail: this measures `block_batch` (the batched stone), so the three
	`_spawn_artifact_accent` meshes — Giza's capstone, Liberty's torch, the Eiffel
	beacon — are NOT measured. All three sit well inside their landmark today
	(Liberty's torch, the furthest out, reaches 2.09 m against a declared 5.4), and
	an accent is a 0.5 m unlit glow box that nothing collides with, so the seam
	consequence of one hanging over an edge is cosmetic rather than the "half a
	bridge cut in two" this check exists for. The upgrade path, if a builder ever
	puts an accent on an outrigger: have `_spawn_artifact_accent` append to a
	parallel test-only array, or measure the accent MeshInstance3D children of the
	stub chunk here.
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
	Four inequalities. Each one is currently true by a comfortable margin, which
	is exactly why nothing would notice if a retune made one false.
	"""
	var radius: float = float(consts["LANDMARK_RADIUS"])
	var edge_margin: float = float(consts["LANDMARK_EDGE_MARGIN"])
	var road_clearance: float = float(consts["LANDMARK_ROAD_CLEARANCE"])
	var boss_forward: float = float(consts["BOSS_FORWARD_OFFSET"])
	var boss_lateral: float = float(consts["BOSS_LATERAL_MAX"])
	var coin_pad_max: float = float(consts["LANDMARK_COIN_RING_PAD_MAX"])

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

	# (iv) THE REWARD RING HAS TO FIT INSIDE THE CHUNK TOO, and (ii) alone does not
	# give that — (ii) bounds the STONE, while the coins sit OUTSIDE the stone by up
	# to LANDMARK_COIN_RING_PAD_MAX. The placement box puts a landmark centre at most
	# (chunk_size / 2 - edge_margin) from the chunk centre per axis, so a coin at
	# ring radius r stays in its own chunk exactly while r <= edge_margin. Break this
	# and a coin near an edge is settled by _settle_coin_y against the WRONG chunk's
	# obstacle list and freed when the WRONG chunk unloads — silent, and rare enough
	# (a landmark near an edge midpoint plus a large pad roll) that a playtest never
	# finds it. The artifacts' identical pad pair is safe only because their radius
	# is 7.0, not 9.5, so this is exactly the inequality copying that recipe lost.
	if radius + coin_pad_max > edge_margin + RADIUS_EPSILON:
		_fail("LANDMARK_RADIUS (%.2f) + LANDMARK_COIN_RING_PAD_MAX (%.2f) = %.2f exceeds LANDMARK_EDGE_MARGIN (%.2f) — a reward coin can land outside its own chunk"
				% [radius, coin_pad_max, radius + coin_pad_max, edge_margin])


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

	# THE CONTROL HAS TO BE A POSITIVE ONE, and the obvious negative one is worse
	# than useless here. The failure to rule out is "no table loaded at all", which
	# makes tr() the identity function — and under that failure an absent-key probe
	# comes back unchanged and PASSES, while all eight facts come back unchanged and
	# fail, i.e. a missing import is reported as eight missing CSV rows: precisely
	# the misdiagnosis a control is supposed to prevent. Only a string known to be
	# in the de table separates the two.
	const KNOWN_TRANSLATED := "PLAY SOLO"
	if tr(KNOWN_TRANSLATED) == KNOWN_TRANSLATED:
		_fail("the de table did not load (tr(\"%s\") came back unchanged) — re-run `godot --headless --path . --import`; the fact results above mean nothing until it does"
				% KNOWN_TRANSLATED)

	# Kept beside it: a key in no table must still come back unchanged, which is the
	# English-fallback rule the whole "keys are the source strings" design rests on
	# (and what lets the four same-in-German names have no CSV row at all).
	var absent := "landmark_selfcheck: no such key, deliberately"
	if tr(absent) != absent:
		_fail("tr() altered a key that is in no table — the English fallback is broken")

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
	#
	# THE INEQUALITY IS ASSERTED DIRECTLY, and the probe below is NOT trusted to
	# discover it. With LEAVE_PAD == APPROACH_PAD the band is empty, and the
	# midpoint probe lands exactly ON the leave boundary where both range tests are
	# strict — so whether this step catches that mutation is decided by float
	# rounding. It happens to today, because Vector2 is real_t=float32 and
	# Vector2(0, 14.6).length() = 14.60000038 just exceeds the float64 8.6 + 6.0;
	# add a ninth landmark with radius 9.4 (a value two entries already use) and
	# the sign flips to 15.39999961 vs 15.4, the probe reads as still-inside, and
	# the mutation passes silently. One comparison removes the whole question.
	if leave_pad <= approach_pad:
		_fail("LEAVE_PAD (%.2f) must be strictly greater than APPROACH_PAD (%.2f) — with no dead band a player on the trigger boundary flickers the card"
				% [leave_pad, approach_pad])
	# Probe strictly INSIDE the band rather than on its edge, now that the band is
	# known to be non-empty.
	player.global_position = Vector3(0.0, 0.0, radius + approach_pad + (leave_pad - approach_pad) * 0.5)
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

	# --- Step 6: TWO LANDMARKS IN RANGE AT ONCE must not ping-pong. Trigger zones
	# genuinely overlap — LANDMARK_EDGE_MARGIN lets a landmark sit 13 m from a
	# chunk edge, so two in adjacent chunks can be ~26 m apart while two 15.4 m
	# trigger radii reach 30.8 m — and a player wandering between them stays
	# inside BOTH the whole time, so neither one's dead band ever re-arms.
	#
	# The bug this catches (and which shipped in the first draft) is a selection
	# rule of `nearest != _active`: the dead band guards one marker's RANGE test,
	# it cannot guard a comparison BETWEEN two markers, so `nearest` flips on every
	# tick and a fresh card is raised 4 times a second, alternating. Every other
	# step in this check passes with that bug present, because they all use one
	# marker.
	var second := _make_marker(registry[0], Vector3(0.0, 0.0, -2.0))
	root.add_child(second)
	# Stand between them: inside both approach radii, nearer the second.
	player.global_position = Vector3(0.0, 0.0, -1.5)
	toast.call("_scan")
	_clear_labels(toast)
	# Drift back toward the first without leaving either — `nearest` changes, the
	# approach does not.
	player.global_position = Vector3(0.0, 0.0, -0.5)
	toast.call("_scan")
	if not _labels_clear(toast):
		_fail("toast: a card was raised for a second landmark while the player was still inside the first — two overlapping landmarks re-show a card every tick")
	second.queue_free()

	toast.queue_free()
	marker.queue_free()
	decoy.queue_free()
	player.queue_free()


# ============================================================================
# CHECK 5 — the trigger distance is DERIVED FROM THE MARKER'S RADIUS
# ============================================================================

func _check_toast_radius_derived(registry: Array) -> void:
	"""
	One probe distance, TWO markers of different radius: out of range for the small
	one, in range for the big one. A toast that ignores `radius` and triggers at a
	flat distance cannot satisfy both, whatever that flat distance is.

	WHY THIS EXISTS AS ITS OWN CHECK. Check 4 drives one marker at one radius, so
	every step of it passes against a toast whose range tests are hardcoded metre
	counts — verified by editing a copy of the real script to use flat 15.0 / 23.0
	bounds and ignore the meta entirely: all five steps still passed. And `radius`
	is the reason the toast is shaped this way at all ("a 9.4 m Giza and a 5.4 m
	Liberty both fire where they look like they should"), so losing it is a silent
	regression of the whole feature, not a detail.

	This is the same failure class minimap_selfcheck.gd documents — a layer that
	keeps its own hardcoded metre count draws perfectly at the default zoom — and
	the same answer: probe at a distance that means different things to two
	different scales, and require both answers.
	"""
	var toast_script: GDScript = load(TOAST_SCRIPT)
	var approach_pad: float = float(toast_script.get_script_constant_map()["APPROACH_PAD"])

	# Widest and narrowest entries in the registry, whatever they happen to be.
	var small: Dictionary = registry[0]
	var big: Dictionary = registry[0]
	for entry_variant: Variant in registry:
		var entry: Dictionary = entry_variant
		if float(entry["radius"]) < float(small["radius"]):
			small = entry
		if float(entry["radius"]) > float(big["radius"]):
			big = entry
	var r_small: float = float(small["radius"])
	var r_big: float = float(big["radius"])
	if r_big - r_small < 1.0:
		# Not a failure: with a registry of near-identical radii there is no probe
		# distance that separates them, and the check simply has nothing to say.
		print("landmark_selfcheck: radius spread %.2f m too small to probe; check 5 skipped" % (r_big - r_small))
		return

	# Strictly between the two trigger distances: past the small landmark's, short
	# of the big one's.
	var probe: float = (r_small + approach_pad + r_big + approach_pad) * 0.5

	for case: Array in [[small, false], [big, true]]:
		var entry: Dictionary = case[0]
		var expect_card: bool = case[1]

		var player := StubPlayer.new()
		player.add_to_group("player")
		root.add_child(player)
		var marker := _make_marker(entry, Vector3.ZERO)
		root.add_child(marker)

		var toast := Control.new()
		toast.set_script(toast_script)
		root.add_child(toast)
		await process_frame
		toast.set_process(false)

		player.global_position = Vector3(0.0, 0.0, probe)
		toast.call("_scan")
		var showed: bool = not _labels_clear(toast)
		if showed != expect_card:
			_fail("toast: at %.2f m from a radius-%.2f landmark the card %s, expected it %s — the trigger distance ignores the marker's radius meta"
					% [probe, float(entry["radius"]),
					   "showed" if showed else "did not show",
					   "to show" if expect_card else "not to show"])

		toast.queue_free()
		marker.queue_free()
		player.queue_free()
		# Freed nodes leave their groups on the NEXT frame, so without this the
		# second case runs with the first case's marker still answering
		# get_nodes_in_group("landmark") — which would make the pair meaningless.
		await process_frame


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
