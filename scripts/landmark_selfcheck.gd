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
##      The quiz card's four literals ride along on the same rule, and for the
##      same reason: they are CSV keys. What that pins is the CSV side — the rows
##      cannot be deleted, and a German format string cannot lose its %d; see the
##      note at the check for the direction it does not yet cover.
##   4. THE TOAST FIRES ONCE PER APPROACH AND RE-ARMS ON LEAVING. Driven against
##      the real landmark_toast.gd with stub player and marker nodes, because
##      every way this breaks — a card that never shows, one that re-pops every
##      quarter second, one showing the wrong landmark's fact, one that never
##      re-arms — looks like ordinary behaviour from inside the script. Its step 6
##      covers the case ONE marker cannot: two landmarks whose trigger zones
##      overlap (reachable — see the step's comment), where a `nearest != _active`
##      selection rule raises a fresh card 4 times a second without the player ever
##      leaving either one. Every FIRST approach now asks a question before it
##      pays, so this check answers each one right (`_answer_correct`) and goes on
##      measuring exactly what it always measured: the card latch and the treasure.
##      Check 7 owns the question itself.
##   5. THE TRIGGER DISTANCE IS DERIVED FROM THE MARKER'S RADIUS. Its own check,
##      because check 4 drives ONE marker at ONE radius and therefore passes in
##      full against a toast whose range tests are hardcoded metre counts —
##      verified by mutating a copy that way (all five of check 4's steps still
##      passed). The radius meta is the reason the toast is shaped as it is, so
##      losing it is a silent regression of the feature, not a detail. One probe
##      distance, two markers of different radius: in range for the wider, out of
##      range for the narrower. Same failure class, and same answer, as
##      minimap_selfcheck.gd's two-zoom crocodile probe.
##   6. THE QUIZ OFFERS AN ANSWERABLE, IDENTICAL-FOR-EVERYONE CARD. Pure logic,
##      no toast and no scene: LandmarkBuilders.quiz_options() is swept over every
##      registry row × 6 run_seeds × 3 landmark ids. Every way this breaks returns
##      three perfectly plausible names — a picker that ignores run_seed (every
##      run the same card, and in a room fine, so nothing looks wrong), one that
##      ignores the id (every landmark the same wrong answers), one that always
##      puts the answer in the same slot (the quiz is free), one whose distractors
##      come from four continents (also free — see the "giveaway" note on
##      quiz_options), and one that is not deterministic at all (in a room, each
##      peer answers a different card). So the per-call assertions (three distinct
##      in-range indices with the correct one among them) are the cheap half; the
##      half that earns its keep is the SPREAD over the sweep. Also the only place
##      the five-word region vocabulary is enforced, because a missing region is
##      by design a silent fall-through to whole-table distractors.
##   7. THE QUIZ CARD IS ANSWERABLE, PAYS ONLY ON A RIGHT ANSWER, AND ASKS ONCE.
##      Check 6 proves the three names are a fair question; this one drives the
##      real toast through the whole state machine that shows them — ask, digit,
##      tap, timeout, re-visit — because none of it is visible from the picker and
##      all of it fails quietly. A card that revealed the fact beside the question
##      is a quiz that answers itself. One that paid the burst on arrival is the
##      old behaviour with three buttons drawn over it. One whose keys still fire
##      under ANOTHER overlay's pause hands the player a blind answer every time
##      they close the skill tree with the number row. One that re-asks on a
##      re-visit is a coin farm you pace back and forth over. Every step is
##      measured through the toast's own methods, with `_unhandled_input` fed a
##      real InputEventKey and the option Button's own `pressed` signal emitted, so
##      a tap and a digit are proved to be the same event rather than assumed to be.
##
##      STEPS (h)-(m) ARE THE PAUSE LIFECYCLE, added when the owner reversed the
##      card's "pauses nothing" design (see landmark_toast.gd's header). The card
##      now freezes the world while a question is up, and every way that goes wrong
##      is silent-to-catastrophic rather than merely wrong-looking: a pause never
##      given back is a dead run, a pause released that belonged to the skill tree
##      is a world running behind an open panel, and a digit that answers under
##      somebody else's pause is the blind answer the old guard existed to stop —
##      which is now the OPPOSITE bug from a digit that does NOT answer under the
##      card's own pause, since being frozen so you can answer is the whole point.
##      So both directions are driven, and the ownership flag that separates them
##      is read at every step. Step (m) is the one that costs a real frame: every
##      other step calls `_process` by hand and therefore passes against a toast
##      the ENGINE would never call while paused — the exact softlock — so (m)
##      hands the frame back and measures the quiz clock moving on its own.
##      Step (l) drives the multiplayer ruling: in a room the pause is skipped
##      outright, because `get_tree().paused` is local and crocodiles are
##      master-simulated, so a paused master would stall the world for everybody.
##      Step (n) covers the one overlap this project's first-taker-owns pause
##      discipline cannot survive unattended: a focus loss over our pause claims
##      nothing, so without the clock stopping too, a backgrounded tab would time
##      the question out and resume the world with nobody looking at it.
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
##   (i) landmark_toast._claim_treasure's `if _visited.has(id): return 0` removed
##       (the per-run latch re-arms with the card)  ->  FAIL: re-approaching the
##       same landmark in the same run paid 18 more coins.
##   (j) the `_visited.clear()` on a run_seed change removed (a new run keeps the
##       old visited set)  ->  FAIL: after run_seed changed to 1 the same landmark
##       paid 0 coins, outside 15..25 (× 6 seeds), plus the determinism row.
##   (k) run_seed dropped from the amount hash  ->  FAIL: one landmark paid the
##       same 22 coins across six different run_seeds. NOTE step 5d passes under
##       this one — a constant IS deterministic — which is why the six-seed sweep
##       exists beside it.
##   (l) the amount rolled off rng.randomize() instead of the hash  ->  FAIL: the
##       same landmark on the same run_seed paid 16 coins and then 18. NOTE the
##       six-seed sweep passes under THIS one, which is why 5d exists beside it —
##       the pair is deliberately two controls, not one.
##   (m) `_burst_remaining += amount` -> `= 1` (one fat pickup instead of the
##       staggered burst, i.e. the streak-killing bug the chest's design note is
##       about)  ->  FAIL: the first approach paid 1 coins, outside 15..25.
##   (n) `_burst_remaining += amount` -> `= amount` (a second landmark reached
##       mid-shower REPLACES the first one's remaining coins instead of joining
##       them)  ->  FAIL: two landmarks visited inside one burst window paid 26
##       coins in total, outside 2 × 15..25.
##   (o) the `_burst_remaining = 0` in _sync_run's run-change branch removed  ->
##       FAIL: 23 coins from the previous run were paid into a new one.
##   (p) _update_burst's `_sync_run()` call removed, leaving the run gate lazy on
##       the next CLAIM only  ->  same failure as (o), which is the point: the
##       gate has to be where coins are paid, not only where they are armed.
##   (q) the "Not quite!" row deleted from ui.csv (+ --import), the same shape as
##       (c)  ->  FAIL: quiz string Not quite! is not translated in de — its
##       ui.csv row is missing.
##   (r) LandmarkBuilders.quiz_options' `rng.seed = hash(...)` -> `rng.randomize()`
##       ->  FAIL: quiz_options is not deterministic — [33, 0, 37] then
##       [0, 16, 39]. (In a room that mutation gives every peer a different card.)
##   (s) run_seed dropped from the quiz hash  ->  FAIL: no landmark's options
##       changed across 6 run_seeds, plus "only 34 distinct distractor pairs over
##       48 landmarks × 6 seeds × 3 ids". NOTE every per-call assertion passes
##       under it — three plausible names is exactly what it still returns.
##   (t) landmark_id dropped from the quiz hash  ->  FAIL: no landmark's options
##       changed across 3 landmark ids.
##   (u) quiz_options' same-region preference removed (`if pool.size() < 2` ->
##       always fall back to the whole table)  ->  FAIL: Stonehenge (europe, 29
##       rows in region): 1 distractor(s) from another region — i.e. the giveaway
##       card the region field exists to prevent.
##   (v) that same fallback threshold off by one (`< 2` -> `< 1`, so a 2-row region
##       cannot fill its second slot)  ->  FAIL: Moai of Easter Island returned 2
##       options, expected 3. The oceania rows are what make this reachable.
##   (w) `options.insert(rng.randi_range(0, 2), kind)` -> `options.append(kind)`
##       (the answer always last)  ->  FAIL: the correct answer landed in slot [2]
##       on every one of the 48 × 6 × 3 draws.
##   (x) LANDMARKS[1].region "oceania" -> "polynesia" (a sixth continent word)
##       ->  FAIL: Moai of Easter Island: region "polynesia" is not one of
##       ["europe", "asia", "africa", "americas", "oceania"]. Deleting the field
##       outright reports the same row as `missing`.
##   (y) landmark_toast._scan marks `_visited` at the ANSWER instead of at the
##       arrival (the `_first_visit` call moved into `_answer`)  ->  FAIL: coming
##       back to a landmark asked about it a second time in the same run — check
##       7(e). Every other step passes: within one visit the two orders are
##       indistinguishable.
##   (z) landmark_toast._answer pays the burst whatever the slot (`correct` forced
##       true)  ->  FAIL: a wrong answer paid 21 coins — check 7(c). And the
##       mirror, `_start_quiz` arming the burst itself: FAIL: 18 coins were paid
##       before the question was answered — check 7(a).
##   (aa) landmark_toast._start_quiz leaves `fact_label.visible = true` (the fact
##       shown beside the question)  ->  FAIL: the fact is on screen beside the
##       question — it is the answer. Nothing else notices; the card looks fine.
##   (bb) the `if get_tree().paused: return` guard removed from
##       `_unhandled_input`  ->  FAIL: a digit answered the question while the
##       tree was paused. This one is worth its line: the guard is redundant
##       TODAY (the HUD layer is pausable, so the engine withholds the event) and
##       a reader deleting it would be right about the engine and wrong about the
##       next person who sets PROCESS_MODE_ALWAYS on that layer.
##   (cc) `_update_quiz` dropped from `_process` (the clock never runs)  ->  FAIL:
##       the question was still pending 13.0 s after it was asked — check 7(d).
##   (dd) the option Buttons' `pressed` signal left unconnected  ->  FAIL: tapping
##       the right option paid 0 coins — check 7(g). The digits still work, which
##       is the whole point of driving both.
##   (ee) landmark_toast._take_pause's `process_mode = PROCESS_MODE_ALWAYS` removed
##       (the node freezes with the world it just froze)  ->  FAIL: the question's
##       own clock did not move over four frames with the tree paused for it
##       (12.000 s -> 12.000 s) — QUIZ_TIMEOUT can never fire and the pause never
##       lifts. THE SOFTLOCK, and check 7(m) is the only step that sees it: every
##       other step drives `_process` by hand and passes under this mutation.
##   (ff) `_unhandled_input`'s guard reverted to the pre-ruling
##       `if get_tree().paused: return`  ->  FAIL: the digit did not answer under
##       the card's OWN pause — the world is frozen and the key that lifts it is
##       refused (7(i)), and a cascade behind it. Note 7(h) still passes: the
##       plain guard is right about somebody else's pause and wrong about ours.
##   (gg) the `if not _paused_by_us: return` dropped from `_release_pause`  ->
##       FAIL: resolving the card released a pause it never took — the skill tree,
##       the pause screen or the MP panel would come back to a running world
##       (7(h)). Everything else passes: the card's own lifecycle is unaffected.
##   (hh) the `is_busy()` room test dropped from `_take_pause`  ->  FAIL: the card
##       paused the tree while in a room — a paused master stalls the simulation
##       for every other peer (7(l)).
##   (ii) `_release_pause` dropped from `_cancel_quiz`  ->  FAIL: a new run
##       cancelled the question but kept its pause — a fresh run frozen with no
##       card on screen to explain it (7(k)).
##   (jj) `_release_pause` dropped from `_answer`  ->  FAIL: answering the question
##       left the tree paused — the game never starts again (7(i)), plus the
##       timeout twin (7(j)) and the whole of 7(h) behind it.
##   (kk) `_take_pause` dropped from `_start_quiz`  ->  FAIL: the question was
##       asked without pausing the tree (7(i)); (j), (k) and (m) each report that
##       they cannot measure their release, which is the point of stating the
##       precondition in every one of them.
##   (mm) the `if _unfocused: return` dropped from `_update_quiz`  ->  FAIL: the
##       question timed out while the app was unfocused — the world unpauses in a
##       backgrounded tab with nobody watching (7(n)). Dropping the FOCUS_IN arm
##       of `_notification` instead is the mirror: FAIL: the question never
##       resolved after the app regained focus — the clock was stopped, not held.
##   (ll) `_exit_tree` dropped from landmark_toast  ->  FAIL: the tree was already
##       paused when check 7 started. Check 5 frees its toast with a question still
##       pending, so the release on teardown is load-bearing for this file as well
##       as for a scene change; without the entry assertion the same mutation
##       reports "pressing the digit did not resolve the question" and four more.
##
## Don't grow this into a suite.

const TERRAIN_SCRIPT: String = "res://scripts/endless_terrain.gd"
const TOAST_SCRIPT: String = "res://scripts/landmark_toast.gd"
## The registry and the shape builders live here; the PLACEMENT POLICY constants
## check 2 reads still live on the terrain. Both scripts are loaded because the
## inequality chain spans the seam — an entry's own `radius` comes from this file,
## the LANDMARK_RADIUS that must bound it comes from the terrain.
const BUILDERS_SCRIPT: String = "res://scripts/landmark_builders.gd"

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

## Check 6's fixed vocabulary and sweep. The five words are hardcoded HERE rather
## than read off the registry on purpose: read from the data, the check would
## happily bless a row that invented a sixth continent. The seeds and ids are
## arbitrary but include 0, a negative and a large value, because the quiz hash
## feeds them into a Vector3i (int32 components) and a picker that only works for
## small positive numbers is a picker that breaks on a real run_seed.
const QUIZ_REGIONS: Array[String] = ["europe", "asia", "africa", "americas", "oceania"]
const QUIZ_SEEDS: Array[int] = [0, 1, 7, 1234567, -99, 2147483]
const QUIZ_IDS: Array[int] = [11, 4242, -7]

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
	var builders_script: GDScript = load(BUILDERS_SCRIPT)
	var registry: Array = builders_script.get_script_constant_map().get("LANDMARKS", [])

	if registry.is_empty():
		_fail("landmark_builders.gd has no LANDMARKS registry")
	else:
		_check_radii(terrain_script, builders_script, registry)
		_check_constants(consts, registry)
		_check_facts(registry)
		await _check_toast(registry)
		await _check_toast_radius_derived(registry)
		_check_quiz_options(builders_script, registry)
		await _check_quiz_toast(registry)

	if _failures.is_empty():
		print("landmarks: %d builders × %d seeds measured, toast once-per-approach + radius-derived trigger + first-visit treasure OK, quiz options over %d × %d seeds × %d ids OK, quiz card ask/answer/tap/timeout/re-visit OK"
				% [registry.size(), SEEDS_PER_BUILDER, registry.size(), QUIZ_SEEDS.size(), QUIZ_IDS.size()])
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

func _check_radii(terrain_script: GDScript, builders_script: GDScript, registry: Array) -> void:
	"""
	Call every builder for real and measure what it emitted.

	The terrain node is DETACHED (never added to the tree) on purpose: _ready()
	rolls a run seed, builds fog, materials and the first chunks, none of which a
	builder needs — a builder touches only create_box, _spawn_artifact_accent and
	the shared ember material. Keeping it out of the tree keeps this check to the
	geometry it is about. It is still a real terrain node, because that is exactly
	what the builders take as their first argument now that they are static.
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

		# has_method on the SCRIPT object, because the builders are static on
		# LandmarkBuilders rather than methods on the terrain node.
		if not builders_script.has_method(builder):
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

			var footprint: Variant = builders_script.call(builder, terrain, Vector3.ZERO, rng, chunk, block_batch, block_body)

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

		# REPORT THE MEASUREMENT, don't just pass on it. The whole point of measuring
		# emitted corners over many seeds is the number, and a check that prints only
		# "ok" leaves the next person adding a place with no idea whether a radius has
		# 3 m of headroom or 3 cm — which is exactly what they need to know before
		# nudging one. Printed rather than asserted for the reason the note below
		# gives: a tight fit is correct and a loose one is correct.
		print("landmark_selfcheck: %-24s declared %5.2f  measured %5.2f  headroom %5.2f"
				% [place, declared, worst_overall, declared - worst_overall])

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

	ponytail: this measures `block_batch` (the batched stone), so the five
	`_spawn_artifact_accent` meshes — Giza's capstone, Liberty's torch, the Eiffel
	beacon, Big Ben's Ayrton Light and the Great Wall's beacon fire — are NOT
	measured. All five sit well inside their landmark today (the last two are on
	the landmark's own axis, and Liberty's torch, the furthest out of any of them,
	reaches 2.09 m against a declared 5.4), and
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

	# The quiz card's four literals, held to the same rule as the facts: they ARE
	# the CSV keys (RULE 1), so a missing row shows an English prompt over a
	# German fact and nothing errors.
	#
	# WHAT THIS DOES AND DOES NOT CATCH. The list is the epic's fixed wording, not
	# a read of landmark_toast.gd — that file does not own these strings yet, and
	# the toast is a *scene-driven* Control whose labels are assigned in code, so
	# there is nothing to read. So it pins the CSV: delete a row (or drop the %d
	# from a German one) and this fails. It does NOT yet see a toast reworded away
	# from these keys — that direction closes when the toast lands the wording as
	# a const.
	# READ OFF THE TOAST, not re-typed here: landmark_toast.gd owns the four as
	# constants, so a renamed string fails as a missing CSV row (which it is)
	# instead of passing against a stale copy in this file. The same
	# get_script_constant_map() the checks above use for APPROACH_PAD.
	var toast_consts: Dictionary = load(TOAST_SCRIPT).get_script_constant_map()
	var quiz_strings: Array = [
		String(toast_consts["QUIZ_PROMPT"]),
		String(toast_consts["QUIZ_CORRECT"]),
		String(toast_consts["QUIZ_WRONG"]),
		String(toast_consts["QUIZ_TIMEOUT_VERDICT"]),
	]
	for quiz_string: String in quiz_strings:
		var german: String = tr(quiz_string)
		if german == quiz_string:
			_fail("quiz string %s is not translated in de — its ui.csv row is missing"
					% quiz_string.c_escape())
		# RULE 2 strings are `tr()`d as FORMAT strings, so a German row that lost
		# its placeholder is not a cosmetic bug: `%` would fail on it at runtime.
		elif quiz_string.contains("%d") and not german.contains("%d"):
			_fail("the de row for %s dropped its %%d placeholder — it is a format string"
					% quiz_string.c_escape())

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

## The stub player. The toast reads two things off the "player" group node —
## global_position, and (since the first-visit treasure) collect_coin() — so that
## is all this is; nothing else about the real player is relevant, and a full
## player scene would drag in the whole HUD.
##
## `coins_paid` counts PICKUPS, deliberately not value, because that is the whole
## mechanical point of the staggered burst: the streak multiplier steps every
## STREAK_COINS_PER_STEP *pickups*, so a burst that "worked" by calling
## collect_coin(20) once would light no streak at all. Counting calls here is
## what makes that measurable — summing `value` would pass either way.
class StubPlayer extends Node3D:
	var coins_paid: int = 0

	func collect_coin(_value: int = 1) -> void:
		coins_paid += 1


## The stub terrain. The toast reads exactly one thing off the "terrain" group
## node — `run_seed` — which IS the run identity: new_run() re-rolls it, and
## that is how the per-run treasure latch learns a new run has started without
## any signal to subscribe to.
class StubTerrain extends Node:
	var run_seed: int = 0


## The stub multiplayer manager, for check 7(l). The toast asks it exactly one
## question — `is_busy()` — which is the test build_version.gd makes, and for the
## same reason: a peer is "in a room" from the moment it starts connecting, not
## only once it is IN_ROOM.
class StubMp extends Node:
	func is_busy() -> bool:
		return true


func _check_toast(registry: Array) -> void:
	var toast_consts: Dictionary = load(TOAST_SCRIPT).get_script_constant_map()
	var toast_script: GDScript = load(TOAST_SCRIPT)
	var approach_pad: float = float(toast_consts["APPROACH_PAD"])
	var leave_pad: float = float(toast_consts["LEAVE_PAD"])
	var treasure_min: int = int(toast_consts["TREASURE_COINS_MIN"])
	var treasure_max: int = int(toast_consts["TREASURE_COINS_MAX"])

	var player := StubPlayer.new()
	player.add_to_group("player")
	root.add_child(player)

	# The run the treasure latch belongs to. Seed 0 would be indistinguishable
	# from "no terrain in the tree", which is exactly the state the toast falls
	# back to in a standalone scene — so start somewhere else.
	var terrain := StubTerrain.new()
	terrain.run_seed = 424242
	terrain.add_to_group("terrain")
	root.add_child(terrain)

	# TWO markers, and that is the negative control for the TEXT assertion: with
	# one marker, a card that always showed registry entry 0 would pass. The
	# player is parked by the SECOND one, so the card has to have read the marker
	# it was actually near.
	var decoy := _make_marker(registry, 0, Vector3(400.0, 0.0, 0.0))
	var marker := _make_marker(registry, registry.size() - 1, Vector3.ZERO)
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
	# TREASURE NEGATIVE CONTROL, and the one that matters most: a burst that fired
	# on the tick rather than on the approach would pay here, with the player
	# 60-odd metres from anything.
	toast.call("_update_burst", 100.0)
	if player.coins_paid != 0:
		_fail("treasure: %d coins were paid with the player %.0f m from every landmark"
				% [player.coins_paid, radius + leave_pad + 50.0])

	# --- Step 2: inside the approach radius → the card shows THIS landmark.
	player.global_position = Vector3(0.0, 0.0, radius + approach_pad - 1.0)
	toast.call("_scan")
	if not toast.visible:
		_fail("toast: the card did not show inside the approach radius")
	# THE FIRST APPROACH OF A RUN ASKS BEFORE IT ANNOUNCES, so the name, the fact
	# and the treasure all arrive through the answer. Check 7 measures the
	# question; from here this check is the same card-latch and treasure check it
	# always was, one call longer.
	_answer_correct(toast)
	var shown_name: String = toast.get("name_label").text
	var shown_fact: String = toast.get("fact_label").text
	if shown_name != String(entry["name"]) or shown_fact != String(entry["fact"]):
		_fail("toast: showed \"%s\" / \"%s\", expected \"%s\" / \"%s\" — it read the wrong marker"
				% [shown_name, shown_fact, String(entry["name"]), String(entry["fact"])])

	# TREASURE: the first approach of the run pays, and the amount is inside the
	# declared band. Flushing the burst with an absurd delta is what drives the
	# stagger to completion here — _process is off, so without it only the coin
	# _claim_treasure pays on contact would land, and the check would pass against
	# a burst whose remaining 14-24 coins never arrive.
	toast.call("_update_burst", 100.0)
	var paid_first: int = player.coins_paid
	if paid_first < treasure_min or paid_first > treasure_max:
		_fail("treasure: the first approach paid %d coins, outside TREASURE_COINS_MIN..MAX (%d..%d)"
				% [paid_first, treasure_min, treasure_max])
	var treasure_label: Label = toast.get("treasure_label")
	if not treasure_label.visible or treasure_label.text.is_empty():
		_fail("treasure: the card showed no \"+N coins\" line on the approach that paid %d" % paid_first)

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

	# --- Step 5b: THE TREASURE LATCH DOES NOT RE-ARM WITH THE CARD, and this is
	# the load-bearing difference between the two latches. Step 5 just proved the
	# CARD re-shows after a genuine departure (deliberate: the card is the reward
	# for the detour). The treasure must NOT: a landmark pays once per run, or the
	# whole feature is a coin farm you pace back and forth over.
	#
	# Steps 3 and 4 are covered by the same assertion — neither re-showed a card,
	# so neither may have paid either, and coins_paid has not been touched since
	# step 2.
	toast.call("_update_burst", 100.0)
	if player.coins_paid != paid_first:
		_fail("treasure: re-approaching the same landmark in the same run paid %d more coins — the per-run latch re-arms with the card"
				% (player.coins_paid - paid_first))
	if treasure_label.visible:
		_fail("treasure: the \"+N coins\" line was shown on a re-visit that paid nothing")

	# --- Step 5c: A NEW RUN CLEARS THE LATCH, and the amount is a pure function
	# of (landmark, run_seed).
	#
	# Driving it through the terrain's `run_seed` is driving the real trigger:
	# new_run() re-rolls that seed and restart_game() goes through new_run(), so
	# this is the same event a player pressing Play Again produces. A RESPAWN
	# re-rolls nothing, which is why the design says a death costs you no landmark
	# you had already emptied — and why there is deliberately nothing to drive for
	# that case beyond step 5b, which is exactly it.
	var amounts: Array[int] = []
	# Six seeds: enough that "the roll ignores run_seed entirely" cannot survive
	# the all-equal test below by luck (11 possible amounts, so 11^-5 ≈ 6e-6),
	# while every one of them independently proves the latch cleared.
	for probe_seed: int in [1, 2, 3, 5, 8, 13]:
		terrain.run_seed = probe_seed
		var before: int = player.coins_paid
		_approach_again(toast, player, radius + approach_pad - 1.0, radius + leave_pad + 5.0)
		var paid: int = player.coins_paid - before
		amounts.append(paid)
		if paid < treasure_min or paid > treasure_max:
			_fail("treasure: after run_seed changed to %d the same landmark paid %d coins, outside %d..%d — a new run did not clear the visited set"
					% [probe_seed, paid, treasure_min, treasure_max])
	var all_equal := true
	for paid: int in amounts:
		if paid != amounts[0]:
			all_equal = false
	if all_equal:
		_fail("treasure: one landmark paid the same %d coins across six different run_seeds — the amount does not depend on run_seed"
				% amounts[0])

	# --- Step 5d: DETERMINISM. Back on the original run seed, the same landmark
	# must pay the SAME amount it paid at step 2. That is the multiplayer promise
	# ("the same landmark pays the same amount to everyone in a run") measured
	# from the only side a single process can measure it: a roll off randomize(),
	# randi() or a shared stream cannot repeat a number six approaches later.
	terrain.run_seed = 424242
	var before_repeat: int = player.coins_paid
	_approach_again(toast, player, radius + approach_pad - 1.0, radius + leave_pad + 5.0)
	var paid_repeat: int = player.coins_paid - before_repeat
	if paid_repeat != paid_first:
		_fail("treasure: the same landmark on the same run_seed paid %d coins and then %d — the amount is not deterministic"
				% [paid_first, paid_repeat])

	# --- Step 5e: A SECOND LANDMARK REACHED MID-SHOWER MUST NOT SWALLOW THE FIRST
	# ONE'S REMAINING COINS. Trigger zones genuinely overlap (see step 6) and 1.2 s
	# of Air Rush covers 30 m, so leaving one landmark and arriving at the next
	# while the first is still paying is reachable in play. Under a burst that
	# ASSIGNS rather than ACCUMULATES, the first card advertises 15-25 coins and
	# delivers one — the loss is silent, which is exactly why it is measured.
	#
	# Driven with the flush deliberately WITHHELD between the two arrivals: that
	# is the whole scenario, and flushing first would make the two claims
	# sequential and the assertion vacuous.
	var far_marker := _make_marker(registry, 0, Vector3(0.0, 0.0, 200.0))
	root.add_child(far_marker)
	terrain.run_seed = 909090
	var before_overlap: int = player.coins_paid
	# Arrive at the first landmark, but do NOT drain the shower.
	player.global_position = Vector3(0.0, 0.0, radius + leave_pad + 5.0)
	toast.call("_scan")
	player.global_position = Vector3(0.0, 0.0, radius + approach_pad - 1.0)
	toast.call("_scan")
	_answer_correct(toast)
	var owed_first: int = int(toast.get("_burst_remaining"))
	# Arrive at the second, still mid-shower.
	player.global_position = Vector3(0.0, 0.0, 200.0)
	toast.call("_scan")
	_answer_correct(toast)
	var owed_both: int = int(toast.get("_burst_remaining"))
	toast.call("_update_burst", 100.0)
	var paid_overlap: int = player.coins_paid - before_overlap
	if owed_both <= owed_first:
		_fail("treasure: arriving at a second landmark mid-shower left %d coins owed, down from %d — the second burst replaced the first instead of joining it"
				% [owed_both, owed_first])
	if paid_overlap < treasure_min * 2 or paid_overlap > treasure_max * 2:
		_fail("treasure: two landmarks visited inside one burst window paid %d coins in total, outside 2 × %d..%d"
				% [paid_overlap, treasure_min, treasure_max])
	far_marker.queue_free()

	# --- Step 5f: A NEW RUN CANCELS A SHOWER STILL IN FLIGHT. new_run() can land
	# mid-payout (Play Again, or a multiplayer room's seed arriving), and
	# restart_game() wipes the run's coins immediately BEFORE it — so coins owed by
	# a world that no longer exists must not trickle into the fresh run's counter
	# for the next second. The visited-set clear alone does not cover this: it is
	# lazy, and the next claim may be a kilometre away.
	terrain.run_seed = 717171
	var before_cancel: int = player.coins_paid
	player.global_position = Vector3(0.0, 0.0, radius + leave_pad + 5.0)
	toast.call("_scan")
	player.global_position = Vector3(0.0, 0.0, radius + approach_pad - 1.0)
	toast.call("_scan")
	_answer_correct(toast)
	if int(toast.get("_burst_remaining")) <= 0:
		_fail("treasure: nothing was owed after a fresh approach — step 5f cannot measure the cancel")
	# The world changes underneath the shower.
	terrain.run_seed = 636363
	var mid_cancel: int = player.coins_paid
	toast.call("_update_burst", 100.0)
	if player.coins_paid != mid_cancel:
		_fail("treasure: %d coins from the previous run were paid into a new one — a run change does not cancel a shower in flight"
				% (player.coins_paid - mid_cancel))
	# NEGATIVE CONTROL: the cancel must be the RUN change, not the burst quietly
	# never paying. The approach that armed it did pay its arrival coin.
	if mid_cancel <= before_cancel:
		_fail("treasure: the approach before the run change paid nothing at all — step 5f's cancel assertion is vacuous")

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
	var second := _make_marker(registry, 0, Vector3(0.0, 0.0, -2.0))
	root.add_child(second)
	# Stand between them: inside both approach radii, nearer the second.
	player.global_position = Vector3(0.0, 0.0, -1.5)
	toast.call("_scan")
	# Resolve whatever that arrival asked, or the `not _quiz_pending` term in the
	# raise guard would be what blocks the second card and this step would pass
	# for the wrong reason — the `_active` latch is the thing under test.
	_answer_correct(toast)
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
	terrain.queue_free()
	# Freed nodes leave their groups on the NEXT frame, so without this check 5's
	# markers and toasts would still see this check's player and terrain.
	await process_frame


func _approach_again(toast: Control, player: Node3D, near: float, far: float) -> void:
	"""
	Walk the player genuinely out of range and back in, ANSWER whatever the
	arrival asked, and flush the burst a right answer armed. Leaving first is what
	re-arms the CARD latch (`_active`), which is the only way to raise a card —
	and therefore the only way to reach the treasure — a second time.
	"""
	_walk_in(toast, player, near, far)
	_answer_correct(toast)
	toast.call("_update_burst", 100.0)


func _walk_in(toast: Control, player: Node3D, near: float, far: float) -> void:
	"""Out of range and back in, leaving whatever card that raised untouched."""
	player.global_position = Vector3(0.0, 0.0, far)
	toast.call("_scan")
	player.global_position = Vector3(0.0, 0.0, near)
	toast.call("_scan")


func _answer_correct(toast: Control) -> void:
	"""
	Answer a pending question right, straight through the toast's own resolver.

	Check 4 measures the TREASURE, which is now what a right answer pays, so every
	one of its approaches routes through here. It deliberately calls `_answer`
	rather than feeding a key: which key answers which slot is check 7's business,
	and check 4 should not fail twice for one bug.
	"""
	if not bool(toast.get("_quiz_pending")):
		return
	toast.call("_answer", int(toast.get("_quiz_correct_slot")))


func _press_key(toast: Control, keycode: int) -> void:
	"""One real key-down event, through the toast's real `_unhandled_input`."""
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	toast.call("_unhandled_input", event)


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
	# Tracked by INDEX because that index is the marker's `kind` meta.
	var small_kind: int = 0
	var big_kind: int = 0
	for i: int in registry.size():
		if float((registry[i] as Dictionary)["radius"]) < float((registry[small_kind] as Dictionary)["radius"]):
			small_kind = i
		if float((registry[i] as Dictionary)["radius"]) > float((registry[big_kind] as Dictionary)["radius"]):
			big_kind = i
	var small: Dictionary = registry[small_kind]
	var big: Dictionary = registry[big_kind]
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

	for case: Array in [[small_kind, false], [big_kind, true]]:
		var kind: int = case[0]
		var entry: Dictionary = registry[kind]
		var expect_card: bool = case[1]

		var player := StubPlayer.new()
		player.add_to_group("player")
		root.add_child(player)
		var marker := _make_marker(registry, kind, Vector3.ZERO)
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


func _make_marker(registry: Array, kind: int, at: Vector3) -> Node3D:
	"""
	A stand-in for the bare Node3D spawn_landmark_in_chunk parents to the chunk:
	group "landmark" plus all four metas the world sets — name, fact, radius and
	the registry index `kind`, which is what the quiz card asks about.

	It takes the INDEX rather than the row because `kind` is the index: handing it
	a row would mean looking the index back up, and a stub whose kind disagreed
	with its name/fact would make check 7's "the right answer is among the three
	offered" assertion meaningless.
	"""
	var entry: Dictionary = registry[kind]
	var marker := Node3D.new()
	marker.add_to_group("landmark")
	marker.position = at
	marker.set_meta("name_key", entry["name"])
	marker.set_meta("fact_key", entry["fact"])
	marker.set_meta("radius", entry["radius"])
	marker.set_meta("kind", kind)
	return marker


func _clear_labels(toast: Control) -> void:
	toast.get("name_label").text = ""
	toast.get("fact_label").text = ""


func _labels_clear(toast: Control) -> bool:
	return toast.get("name_label").text.is_empty() and toast.get("fact_label").text.is_empty()


# ============================================================================
# CHECK 6 — the quiz option picker is pure, deterministic and region-aware
# ============================================================================

func _check_quiz_options(builders_script: GDScript, registry: Array) -> void:
	"""
	LandmarkBuilders.quiz_options() decides, with no packet and no state, which
	three names a "which landmark is this?" card offers. Everything about it fails
	silently: a picker that ignores run_seed still returns three plausible names,
	so do a picker that offers the same wrong answers everywhere, one that leaks the
	answer by always putting it in the same slot, and one whose distractors come
	from four different continents. None of those errors, none of them looks wrong
	from inside the script, and in a room a picker that is not PURE quietly shows
	each peer a different card for the same landmark.

	Pure logic only — no toast, no scene, no marker. The one thing this check
	cannot see is that the toast asks with the right `kind`; that is check 4's
	territory and phase 2's problem.
	"""
	# (a) THE VOCABULARY. A row with no region is not an error at run time — it
	# just falls through to whole-table distractors — so the registry is the
	# source of truth here, exactly as it is for the facts in check 3.
	var per_region: Dictionary = {}
	for entry_variant: Variant in registry:
		var entry: Dictionary = entry_variant
		var region: String = String(entry.get("region", ""))
		if not QUIZ_REGIONS.has(region):
			_fail("%s: region %s is not one of %s — the quiz picker cannot group it"
					% [String(entry["name"]), ("missing" if region.is_empty() else "\"%s\"" % region), str(QUIZ_REGIONS)])
			continue
		per_region[region] = int(per_region.get(region, 0)) + 1

	# Negative-control accumulators for (d): a picker that ignores an input still
	# passes every per-call assertion, and is only visible in the SPREAD over the
	# sweep. Kept as sets of stringified results because Dictionary keys are the
	# cheapest set GDScript has.
	var slots_seen: Dictionary = {}
	var distractor_sets_seen: Dictionary = {}
	var seed_varies := false
	var id_varies := false
	var fallback_widened := false

	for kind: int in registry.size():
		var entry: Dictionary = registry[kind]
		var place: String = String(entry["name"])
		var region: String = String(entry.get("region", ""))
		var same_region_rows: int = int(per_region.get(region, 0))
		var by_seed: Dictionary = {}
		var by_id: Dictionary = {}

		for run_seed: int in QUIZ_SEEDS:
			for landmark_id: int in QUIZ_IDS:
				var options: Array = builders_script.quiz_options(kind, landmark_id, run_seed)

				# (b) THE SHAPE. Three distinct in-range indices with the right
				# answer among them — everything a card needs to be answerable.
				if options.size() != 3:
					_fail("%s (id %d, seed %d): quiz_options returned %d options, expected 3"
							% [place, landmark_id, run_seed, options.size()])
					continue
				var distinct: Dictionary = {}
				var out_of_range := false
				for index_variant: Variant in options:
					var index: int = int(index_variant)
					distinct[index] = true
					if index < 0 or index >= registry.size():
						out_of_range = true
				if out_of_range:
					_fail("%s (id %d, seed %d): option index outside the registry: %s"
							% [place, landmark_id, run_seed, str(options)])
					continue
				if distinct.size() != 3:
					_fail("%s (id %d, seed %d): options are not distinct: %s — one row would appear twice on the card"
							% [place, landmark_id, run_seed, str(options)])
					continue
				if not options.has(kind):
					_fail("%s (id %d, seed %d): the correct answer %d is not among the options %s — the card is unanswerable"
							% [place, landmark_id, run_seed, kind, str(options)])
					continue

				# (c) DETERMINISM. Same question twice, byte-identical answer —
				# which is what makes every peer in a room see one card, and what
				# a rng.randomize() slip breaks.
				var again: Array = builders_script.quiz_options(kind, landmark_id, run_seed)
				if again != options:
					_fail("%s (id %d, seed %d): quiz_options is not deterministic — %s then %s"
							% [place, landmark_id, run_seed, str(options), str(again)])
					continue

				slots_seen[options.find(kind)] = true
				var distractors: Array = options.duplicate()
				distractors.erase(kind)
				distractors.sort()
				distractor_sets_seen[str(distractors)] = true
				by_seed[run_seed] = str(options)
				by_id[landmark_id] = str(options)

				# (e) REGION PREFERENCE, and its fallback. With two other rows to
				# spare, both wrong answers must be from the same continent — that
				# is the whole difference between a quiz and a giveaway. Where the
				# region cannot supply two (oceania, today), the fallback must
				# genuinely widen, which is observable as a distractor from
				# somewhere else.
				var foreign := 0
				for index_variant: Variant in distractors:
					var row: Dictionary = registry[int(index_variant)]
					if String(row.get("region", "")) != region:
						foreign += 1
				if same_region_rows >= 3:
					if foreign > 0:
						_fail("%s (%s, %d rows in region; id %d, seed %d): %d distractor(s) from another region: %s"
								% [place, region, same_region_rows, landmark_id, run_seed, foreign, str(options)])
				elif foreign > 0:
					fallback_widened = true

		# (d) per kind: the same landmark on different run_seeds / different ids
		# must not always give the same card. Asked as "at least one kind varies"
		# rather than "every kind varies" so the check can never flake on a lucky
		# collision while still failing flat for a picker that drops an input.
		if _distinct_values(by_seed) > 1:
			seed_varies = true
		if _distinct_values(by_id) > 1:
			id_varies = true

	# (d) the sweep-wide negative controls.
	if slots_seen.size() < 2:
		_fail("the correct answer landed in slot %s on every one of the %d × %d × %d draws — the answer's position is not rolled"
				% [str(slots_seen.keys()), registry.size(), QUIZ_SEEDS.size(), QUIZ_IDS.size()])
	if distractor_sets_seen.size() <= registry.size():
		_fail("only %d distinct distractor pairs over %d landmarks × %d seeds × %d ids — the wrong answers are fixed per landmark"
				% [distractor_sets_seen.size(), registry.size(), QUIZ_SEEDS.size(), QUIZ_IDS.size()])
	if not seed_varies:
		_fail("no landmark's options changed across %d run_seeds — run_seed is not in the quiz hash" % QUIZ_SEEDS.size())
	if not id_varies:
		_fail("no landmark's options changed across %d landmark ids — the id is not in the quiz hash" % QUIZ_IDS.size())
	if not fallback_widened and _has_underpopulated_region(per_region):
		_fail("a region with fewer than 3 rows never produced an outside distractor — the whole-table fallback is dead code")


# ============================================================================
# CHECK 7 — the quiz card: asks, pays only on a right answer, and asks once
# ============================================================================

func _check_quiz_toast(registry: Array) -> void:
	"""
	Drive the real landmark_toast.gd through the whole question, with the real
	stubs check 4 uses. Check 6 proved the three NAMES are a fair question; this
	proves the CARD that shows them behaves.

	Every step is an effect measurement with a control beside it, the same house
	rule the rest of this file follows: (a) refuses to pass unless the card is
	asking and nothing has been paid, so every "it paid" below means something;
	(f) presses a digit with no question pending and requires nothing to move,
	which is the control for every step that presses one.

	The keys go in as real InputEventKey objects through `_unhandled_input`, and
	the tap goes in as the Button's own `pressed` signal, because "tap == hotkey"
	is a claim about two code paths and asserting it against one of them proves
	nothing.
	"""
	# Steps (h)-(m) read `paused` as an assertion about THIS card, so a stale pause
	# left behind by an earlier check would fail a dozen of them in confusing
	# places. Measured: check 5 frees its toast with a question still pending, so
	# without landmark_toast's `_exit_tree` release the tree arrives here frozen
	# and step (b) reports "pressing the digit did not resolve the question".
	if paused:
		_fail("quiz: the tree was already paused when check 7 started — an earlier check left a pause behind, and a toast freed with a question up must release it")
		paused = false

	var toast_script: GDScript = load(TOAST_SCRIPT)
	var toast_consts: Dictionary = toast_script.get_script_constant_map()
	var approach_pad: float = float(toast_consts["APPROACH_PAD"])
	var leave_pad: float = float(toast_consts["LEAVE_PAD"])
	var quiz_timeout: float = float(toast_consts["QUIZ_TIMEOUT"])
	var option_count: int = int(toast_consts["OPTION_COUNT"])
	var answer_keycodes: Array = toast_consts["ANSWER_KEYCODES"]
	var treasure_min: int = int(toast_consts["TREASURE_COINS_MIN"])
	var treasure_max: int = int(toast_consts["TREASURE_COINS_MAX"])
	var prompt: String = String(toast_consts["QUIZ_PROMPT"])

	var player := StubPlayer.new()
	player.add_to_group("player")
	root.add_child(player)
	var terrain := StubTerrain.new()
	terrain.run_seed = 515051
	terrain.add_to_group("terrain")
	root.add_child(terrain)

	# The LAST registry row, so a toast that always asked about entry 0 could not
	# pass (b)'s "the right answer reveals THIS landmark" assertion.
	var kind: int = registry.size() - 1
	var entry: Dictionary = registry[kind]
	var radius: float = float(entry["radius"])
	var marker := _make_marker(registry, kind, Vector3.ZERO)
	root.add_child(marker)

	var toast := Control.new()
	toast.set_script(toast_script)
	root.add_child(toast)
	await process_frame
	toast.set_process(false)

	var near: float = radius + approach_pad - 1.0
	var far: float = radius + leave_pad + 5.0
	var name_label: Label = toast.get("name_label")
	var fact_label: Label = toast.get("fact_label")
	var treasure_label: Label = toast.get("treasure_label")
	var buttons: Array = toast.get("_option_buttons")

	# --- (a) The first approach ASKS, and pays nothing yet.
	_walk_in(toast, player, near, far)
	if not toast.visible:
		_fail("quiz: no card at all on the first approach of the run")
	if not bool(toast.get("_quiz_pending")):
		_fail("quiz: the first approach of the run asked nothing — the card went straight to the answer")
	if name_label.text != prompt:
		_fail("quiz: the card's headline reads %s, expected the prompt %s"
				% [name_label.text.c_escape(), prompt.c_escape()])
	# THE FACT IS THE REVEAL. Shown beside the question it names the answer, and
	# nothing else in this file would notice — the card looks entirely normal.
	if fact_label.visible:
		_fail("quiz: the fact is on screen beside the question — it is the answer")
	var offered: Array[String] = []
	for slot: int in option_count:
		var button: Button = buttons[slot]
		if not (button.get_parent() as Control).visible:
			_fail("quiz: option row %d is hidden while a question is pending" % slot)
		offered.append(button.text)
	for slot: int in option_count:
		for other: int in range(slot + 1, option_count):
			if offered[slot] == offered[other]:
				_fail("quiz: options %d and %d both read %s — the card offers the same name twice"
						% [slot, other, offered[slot].c_escape()])
	if not offered.has(String(entry["name"])):
		_fail("quiz: the three options %s do not include %s, the landmark being asked about"
				% [str(offered), String(entry["name"]).c_escape()])
	# THE CONTROL FOR EVERY "IT PAID" BELOW: a card that armed the burst on
	# arrival (i.e. the pre-quiz behaviour with three buttons drawn over it) pays
	# here, before anyone answered anything.
	toast.call("_update_burst", 100.0)
	if player.coins_paid != 0:
		_fail("quiz: %d coins were paid before the question was answered" % player.coins_paid)

	# --- (b) The right digit pays the burst and reveals the name and the fact.
	var correct_slot: int = int(toast.get("_quiz_correct_slot"))
	if correct_slot < 0 or correct_slot >= option_count:
		_fail("quiz: the correct answer is slot %d, which is not one of the %d offered — the card is unanswerable"
				% [correct_slot, option_count])
		correct_slot = 0
	_press_key(toast, int((answer_keycodes[correct_slot] as Array)[0]))
	if bool(toast.get("_quiz_pending")):
		_fail("quiz: pressing the digit for slot %d did not resolve the question" % correct_slot)
	toast.call("_update_burst", 100.0)
	var paid_right: int = player.coins_paid
	if paid_right < treasure_min or paid_right > treasure_max:
		_fail("quiz: a right answer paid %d coins, outside TREASURE_COINS_MIN..MAX (%d..%d)"
				% [paid_right, treasure_min, treasure_max])
	if name_label.text != String(entry["name"]) or fact_label.text != String(entry["fact"]) or not fact_label.visible:
		_fail("quiz: after a right answer the card reads %s / %s (fact %s), expected the landmark's own name and fact revealed"
				% [name_label.text.c_escape(), fact_label.text.c_escape(),
				   "shown" if fact_label.visible else "hidden"])
	if not treasure_label.visible or not treasure_label.text.begins_with("Correct"):
		_fail("quiz: the verdict after a right answer reads %s, expected the \"Correct! +N coins\" line"
				% treasure_label.text.c_escape())
	for slot: int in option_count:
		if (buttons[slot].get_parent() as Control).visible:
			_fail("quiz: option row %d is still on screen after the question was answered" % slot)

	# --- (c) A wrong digit reveals the same answer and pays NOTHING.
	terrain.run_seed = 515052
	_walk_in(toast, player, near, far)
	var before_wrong: int = player.coins_paid
	var wrong_slot: int = (int(toast.get("_quiz_correct_slot")) + 1) % option_count
	_press_key(toast, int((answer_keycodes[wrong_slot] as Array)[0]))
	toast.call("_update_burst", 100.0)
	if player.coins_paid != before_wrong:
		_fail("quiz: a wrong answer paid %d coins — the burst is not gated on the answer"
				% (player.coins_paid - before_wrong))
	if name_label.text != String(entry["name"]) or fact_label.text != String(entry["fact"]) or not fact_label.visible:
		_fail("quiz: a wrong answer did not reveal the correct name and its fact — it reads %s / %s"
				% [name_label.text.c_escape(), fact_label.text.c_escape()])
	if treasure_label.text != String(toast_consts["QUIZ_WRONG"]):
		_fail("quiz: the verdict after a wrong answer reads %s, expected %s"
				% [treasure_label.text.c_escape(), String(toast_consts["QUIZ_WRONG"]).c_escape()])

	# --- (d) No answer at all: QUIZ_TIMEOUT resolves it as wrong, with its own
	# verdict. Driven through `_process` rather than `_update_quiz` on purpose —
	# a clock that is never called from the frame is not a timeout.
	terrain.run_seed = 515053
	_walk_in(toast, player, near, far)
	var before_timeout: int = player.coins_paid
	toast.call("_process", quiz_timeout + 1.0)
	if bool(toast.get("_quiz_pending")):
		_fail("quiz: the question was still pending %.1f s after it was asked — QUIZ_TIMEOUT (%.1f s) never fires"
				% [quiz_timeout + 1.0, quiz_timeout])
	toast.call("_update_burst", 100.0)
	if player.coins_paid != before_timeout:
		_fail("quiz: a timed-out question paid %d coins" % (player.coins_paid - before_timeout))
	if treasure_label.text != String(toast_consts["QUIZ_TIMEOUT_VERDICT"]):
		_fail("quiz: the verdict after a timeout reads %s, expected %s"
				% [treasure_label.text.c_escape(), String(toast_consts["QUIZ_TIMEOUT_VERDICT"]).c_escape()])
	if name_label.text != String(entry["name"]) or not fact_label.visible:
		_fail("quiz: a timeout did not reveal the answer — the card reads %s" % name_label.text.c_escape())

	# --- (e) NO RE-ASK. Leave past LEAVE_PAD and come back in the SAME run: the
	# plain card, no options, no coins. This is the step that fails if `_visited`
	# is marked at the answer instead of at the arrival — within one visit the two
	# orders are indistinguishable, which is why the walk out and back is the only
	# way to see it.
	var before_return: int = player.coins_paid
	_walk_in(toast, player, near, far)
	if bool(toast.get("_quiz_pending")):
		_fail("quiz: coming back to a landmark asked about it a second time in the same run")
	if name_label.text != String(entry["name"]) or not fact_label.visible:
		_fail("quiz: the return visit did not show the plain name-and-fact card — it reads %s"
				% name_label.text.c_escape())
	for slot: int in option_count:
		if (buttons[slot].get_parent() as Control).visible:
			_fail("quiz: option row %d is on screen on a re-visit" % slot)
	toast.call("_update_burst", 100.0)
	if player.coins_paid != before_return:
		_fail("quiz: a re-visit paid %d coins — the landmark can be farmed"
				% (player.coins_paid - before_return))

	# --- (f) NEGATIVE CONTROL for every key press above: a digit with no question
	# pending must change nothing at all.
	var before_stray: int = player.coins_paid
	var stray_name: String = name_label.text
	var stray_verdict: String = treasure_label.text
	_press_key(toast, int((answer_keycodes[0] as Array)[0]))
	if player.coins_paid != before_stray:
		_fail("quiz: a digit pressed with no question pending paid %d coins"
				% (player.coins_paid - before_stray))
	if name_label.text != stray_name or treasure_label.text != stray_verdict:
		_fail("quiz: a digit pressed with no question pending rewrote the card")

	# --- (g) TAP == HOTKEY. The option Button's own `pressed` signal, which is the
	# path a touchscreen (and a mouse click) takes. A card whose buttons were never
	# connected still answers every digit, so nothing above notices.
	terrain.run_seed = 515054
	_walk_in(toast, player, near, far)
	var before_tap: int = player.coins_paid
	var tap_slot: int = int(toast.get("_quiz_correct_slot"))
	(buttons[tap_slot] as Button).emit_signal("pressed")
	toast.call("_update_burst", 100.0)
	var paid_tap: int = player.coins_paid - before_tap
	if paid_tap < treasure_min or paid_tap > treasure_max:
		_fail("quiz: tapping the correct option paid %d coins, outside %d..%d — the option Buttons answer nothing"
				% [paid_tap, treasure_min, treasure_max])

	# --- (h) ANOTHER OVERLAY'S PAUSE. Two claims in one approach, and they are the
	# two halves of the reworked input guard's negative side: a digit pressed under
	# a pause the card does NOT own must not answer, and the resolution that
	# eventually comes must not release a pause the card never took.
	#
	# The tree is paused BEFORE the approach, which is how this state is reached
	# for real: in a room the card takes no pause of its own (step (l)), so a
	# player who opens the skill tree over a pending question is paused by somebody
	# else entirely. Under the pre-ruling guard (`if get_tree().paused: return`)
	# this step passes and step (i) fails; under no guard at all this one fails.
	terrain.run_seed = 515055
	paused = true
	_walk_in(toast, player, near, far)
	if not bool(toast.get("_quiz_pending")):
		_fail("quiz: step (h) cannot measure anything — no question was asked under the foreign pause")
	if bool(toast.get("_paused_by_us")):
		_fail("quiz: the card claimed ownership of a pause that was already somebody else's")
	var before_paused: int = player.coins_paid
	var paused_slot: int = int(toast.get("_quiz_correct_slot"))
	_press_key(toast, int((answer_keycodes[paused_slot] as Array)[0]))
	if not bool(toast.get("_quiz_pending")):
		_fail("quiz: a digit answered the question under another overlay's pause — a player closing a panel with the number row answers blind")
	toast.call("_update_burst", 100.0)
	if player.coins_paid != before_paused:
		_fail("quiz: %d coins were paid by a digit pressed under another overlay's pause"
				% (player.coins_paid - before_paused))
	# THE RESOLUTION MUST NOT RELEASE A PAUSE THE CARD NEVER TOOK — the
	# `_paused_by_us` half of the shared guard, and the exact bug an unconditional
	# `get_tree().paused = false` here would be: the skill tree comes back to a
	# world that is running behind it. The timeout is the only resolution reachable
	# in this state, the digits being correctly dead.
	toast.call("_process", quiz_timeout + 1.0)
	if bool(toast.get("_quiz_pending")):
		_fail("quiz: the timeout did not resolve a question left pending under another overlay's pause")
	if not paused:
		_fail("quiz: resolving the card released a pause it never took — the skill tree, the pause screen or the MP panel would come back to a running world")
	paused = false

	# --- (i) THE CARD TAKES THE PAUSE, AND THE ANSWER GIVES IT BACK. The owner
	# ruling in two assertions: the world stops while the question is up, and it
	# starts again the moment the question is answered. The digit that answers is
	# also the POSITIVE control for the reworked input guard — under the old
	# `if get_tree().paused: return` the card would freeze the world and then
	# refuse the only key that unfreezes it.
	terrain.run_seed = 515057
	_walk_in(toast, player, near, far)
	if not paused:
		_fail("quiz: the question was asked without pausing the tree — the player is still reading three names while running")
	if not bool(toast.get("_paused_by_us")):
		_fail("quiz: the tree is paused for the question but the card does not record the pause as its own — it can never release it")
	var answer_slot: int = int(toast.get("_quiz_correct_slot"))
	var before_answer: int = player.coins_paid
	_press_key(toast, int((answer_keycodes[answer_slot] as Array)[0]))
	if bool(toast.get("_quiz_pending")):
		_fail("quiz: the digit did not answer under the card's OWN pause — the world is frozen and the key that lifts it is refused")
	if paused or bool(toast.get("_paused_by_us")):
		_fail("quiz: answering the question left the tree paused — the game never starts again")
	toast.call("_update_burst", 100.0)
	if player.coins_paid - before_answer < treasure_min:
		_fail("quiz: the digit pressed under the card's own pause paid %d coins — it resolved without answering"
				% (player.coins_paid - before_answer))

	# --- (j) THE TIMEOUT RELEASES IT TOO, and this is the path that matters most:
	# a player who presses nothing at all has no other way out of a frozen world,
	# which is exactly why QUIZ_TIMEOUT survived the ruling that removed its
	# original job (you cannot walk away from a paused card).
	terrain.run_seed = 515058
	_walk_in(toast, player, near, far)
	if not paused:
		_fail("quiz: step (j) cannot measure the timeout release — the ask did not pause")
	toast.call("_process", quiz_timeout + 1.0)
	if bool(toast.get("_quiz_pending")):
		_fail("quiz: the question outlived QUIZ_TIMEOUT (%.1f s) while the world was paused for it" % quiz_timeout)
	if paused or bool(toast.get("_paused_by_us")):
		_fail("quiz: a timed-out question held on to its pause — nothing else can lift it and the run is over")

	# --- (k) A RUN CHANGE UNDER A PENDING QUESTION. `_cancel_quiz` drops the card
	# without resolving it (the world it belonged to is gone) and is the third and
	# last exit from `_quiz_pending` — the one that leaves no card on screen to
	# explain a pause it forgot to give back.
	terrain.run_seed = 515059
	_walk_in(toast, player, near, far)
	if not paused:
		_fail("quiz: step (k) cannot measure the cancel release — the ask did not pause")
	terrain.run_seed = 515060
	toast.call("_sync_run")
	if bool(toast.get("_quiz_pending")):
		_fail("quiz: a new run did not cancel the pending question")
	if paused or bool(toast.get("_paused_by_us")):
		_fail("quiz: a new run cancelled the question but kept its pause — a fresh run frozen with no card on screen to explain it")

	# --- (l) IN A ROOM, NO PAUSE AT ALL. `get_tree().paused` is local and
	# crocodiles are master-simulated, so pausing here freezes the world for every
	# other peer. The card must still ASK — the question was never the part in
	# dispute — and must still answer to a digit, i.e. in a room it is byte-for-byte
	# the card that shipped before the ruling.
	#
	# THE NUMPAD ROW rides along here, as it always has somewhere in this check:
	# ANSWER_KEYCODES offers two keycodes per slot and a card that only ever heard
	# the top row would pass every other step. It sits on the one approach with no
	# pause of anybody's in play, so a failure here is unambiguously about the key.
	var mp := StubMp.new()
	mp.add_to_group("mp")
	root.add_child(mp)
	terrain.run_seed = 515061
	_walk_in(toast, player, near, far)
	if not bool(toast.get("_quiz_pending")):
		_fail("quiz: no question was asked in a room — the pause is what a room withholds, not the card")
	if paused or bool(toast.get("_paused_by_us")):
		_fail("quiz: the card paused the tree while in a room — a paused master stalls the simulation for every other peer")
	var room_slot: int = int(toast.get("_quiz_correct_slot"))
	var before_room: int = player.coins_paid
	_press_key(toast, int((answer_keycodes[room_slot] as Array)[1]))
	if bool(toast.get("_quiz_pending")):
		_fail("quiz: the numpad digit for slot %d did not answer the live card in a room" % room_slot)
	toast.call("_update_burst", 100.0)
	var paid_room: int = player.coins_paid - before_room
	if paid_room < treasure_min or paid_room > treasure_max:
		_fail("quiz: the numpad digit for slot %d paid %d coins, outside %d..%d — the numpad row does not answer"
				% [room_slot, paid_room, treasure_min, treasure_max])
	mp.queue_free()
	# Freed nodes leave their groups on the NEXT frame, so step (m) would still see
	# this room and take no pause.
	await process_frame

	# --- (m) THE CLOCK REALLY RUNS WHILE THE WORLD IS FROZEN. Every step above
	# drives `_process` BY HAND, so every one of them passes against a toast the
	# ENGINE would never call while paused — and that is precisely the softlock
	# this change risks: the card freezes the world, its own timeout freezes with
	# it, and nothing is left alive to lift the pause. So this step hands the frame
	# back to the engine and measures the quiz clock moving on its own, which is
	# only possible if the node took PROCESS_MODE_ALWAYS along with the pause.
	# Asserting `process_mode` directly would be a getter read-back; the timer
	# moving is the effect that actually keeps the game playable.
	toast.set_process(true)
	terrain.run_seed = 515062
	_walk_in(toast, player, near, far)
	if not paused:
		_fail("quiz: step (m) cannot measure the frozen clock — the ask did not pause")
	var timer_at_ask: float = float(toast.get("_quiz_timer"))
	for _frame: int in 4:
		await process_frame
	var timer_after: float = float(toast.get("_quiz_timer"))
	if timer_after >= timer_at_ask:
		_fail("quiz: the question's own clock did not move over four frames with the tree paused for it (%.3f s -> %.3f s) — QUIZ_TIMEOUT can never fire and the pause never lifts"
				% [timer_at_ask, timer_after])
	toast.set_process(false)
	_answer_correct(toast)
	toast.call("_update_burst", 100.0)
	if paused:
		_fail("quiz: step (m) left the tree paused")

	# --- (n) A BACKGROUNDED TAB DOES NOT RESOLVE THE QUESTION BEHIND THE PLAYER.
	# `mobile_input.pause_game()` early-returns on an already-paused tree, so a
	# focus loss during a question takes no ownership of our pause and never raises
	# the "tap to resume" overlay — leaving QUIZ_TIMEOUT free to fire in a
	# backgrounded tab, unpause, and hand back a running world with a crocodile in
	# it. The FOCUS_IN half is the control: it proves the clock was held rather
	# than broken.
	terrain.run_seed = 515063
	_walk_in(toast, player, near, far)
	if not paused:
		_fail("quiz: step (n) cannot measure the focus hold — the ask did not pause")
	toast.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	toast.call("_process", quiz_timeout + 1.0)
	if not bool(toast.get("_quiz_pending")):
		_fail("quiz: the question timed out while the app was unfocused — the world unpauses in a backgrounded tab with nobody watching")
	if not paused:
		_fail("quiz: the pause was released while the app was unfocused")
	toast.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	toast.call("_process", quiz_timeout + 1.0)
	if bool(toast.get("_quiz_pending")):
		_fail("quiz: the question never resolved after the app regained focus — the clock was stopped, not held")
	if paused:
		_fail("quiz: the pause survived the question that regained focus and timed out")

	toast.queue_free()
	marker.queue_free()
	player.queue_free()
	terrain.queue_free()
	await process_frame


func _distinct_values(by_input: Dictionary) -> int:
	var seen: Dictionary = {}
	for value: Variant in by_input.values():
		seen[value] = true
	return seen.size()


func _has_underpopulated_region(per_region: Dictionary) -> bool:
	for region: Variant in per_region:
		if int(per_region[region]) < 3:
			return true
	return false
