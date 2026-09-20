extends SceneTree
## ============================================================================
## SAVE FORMAT SELF-CHECK — run headless, prints "SELFCHECK OK", exits 0
## ============================================================================
##
##     godot --headless --path . --script res://scripts/save_selfcheck.gd
##
## Guards `scripts/save_state.gd` (epic godot-test1-i8yu, bead .1), the pure
## v1 encode/decode both save tiers share — and bead .2's slot on top of it:
## `BestRunStore.save_slot()` / `write_save_slot()` / `clear_save_slot()` plus
## the player's `save_snapshot()` / `write_save()` / `has_save()` /
## `continue_save()`. Nine checks:
##
##   1. ROUND TRIP. A full boundary state (seed at MAX_RUN_SEED, pos at
##      MAX_ABS_POS, hero 3, four captives, both masks maxed, all 9 lift stops)
##      encodes, decodes to equal values, and re-encodes byte-equal; a minimal
##      state with empty captives/lift round-trips too.
##   2. EVERY BOUND PROBED BOTH WAYS. Each over-bound value decodes to `{}` —
##      seed past MAX_RUN_SEED, seed as 1e999 (INF), negative seed, fractional
##      seed, pos INF/NaN/past MAX_ABS_POS, hero -1 and 4, negative coins and
##      distance, unknown captive name, five captives, a non-lift id in lift,
##      an oversize lift, bit 40 in either mask, v=2, v missing, an oversize
##      string, `[]` / `{` / scalar malformed blobs, pos as a string — and every
##      one of the 13 fields missing in turn. The positive side of each bound
##      is check 1's boundary state. The loop asserts its own count, so a v1
##      field added without a probe fails BY COUNT.
##   3. WIRE LITERAL. A minimal valid blob typed by hand decodes to the exact
##      expected Dictionary — pins the wire shape so the lobby's Go test (.4)
##      can carry the same literal.
##   4. CANONICAL BYTES. `encode(decode(LITERAL)) == LITERAL`.
##   5. STORE SLOT. Write reads back; `clear_save_slot()` empties it;
##      `archive_world()` and `new_game()` clear it (an ended campaign and a
##      fresh one both have no Continue).
##   6. PLAYER ROUND TRIP. A headed run (seed, pos, hero 2, coins 37, distance
##      1200, one captive, both masks, one lift landing) writes through the
##      slot; a FRESH player and terrain `continue_save()` it back: seed, hero,
##      coins, distance, captives (AND the tower's mirror), masks, the lift id
##      in `shell.earned`, and the distance origin reset under the body. The
##      position asserts the `_place_near` ring (12.5 m), not the bead's 2 m —
##      the ring's outer radius is 12 m, so 2 m contradicts the mandated seam.
##   7. REFUSALS. `save_snapshot()` is `{}` under game over; `continue_save()`
##      refuses in a room (position untouched), on an archived world, and on a
##      bad blob; `has_save()` is false with no slot and after an archive.
##   8. CHANGE GATE. Two writes with nothing moved are byte-identical with
##      `saved_at` unmoved (past the clock tick, so a missing gate cannot hide
##      behind the same second); a 5 m step rewrites.
##   9. HQ RESTORE AT THE LANDING (owner ruling 2026-09-20). An indoor save
##      with an earned stop restores at that landing's lift stand — up-storey,
##      far from the door's outside point, with the lift re-lit; with no
##      landing earned it restores at the entry.
##   10. RESTORE REPLACES (send-back round 1). Captives the checkpoint lacks
##      leave through the mirror seam both ways; masks assign, never OR.
##   11. DISTANCE ACCUMULATES (send-back round 1). Base + offset: 100 m past a
##      1200 m checkpoint reads 1300 on both figures, not a frozen 1200.
##   12. PENDING LIFT (send-back round 1). A shell-less restore waits its
##      landings on the player: the next snapshot still carries them, and the
##      first streamed shell earns them.
##
## NON-VACUOUS by construction (bead .1 names the shape): checks 1, 3 and 4
## expect VALUES, not `{}`. The named mutations each turn a check RED:
## M1 (decode skips is_valid) fails check 2; M2 (captives name check dropped)
## fails check 2's unknown-name probe; M3 (size gate removed) fails check 2's
## oversize probe; M4 (is_valid false for everything) fails checks 1 and 3.
## Bead .2's own five, each naming its check: M1 (restore skips
## `set_active_character`) fails check 6's hero assert; M2 (restore writes
## `captive_heroes` directly) fails check 6's tower-mirror assert; M3
## (`continue_save` ignores `room_seed()`) fails check 7's room refusal; M4
## (the change gate removed) fails check 8's byte-identical assert; M5
## (`archive_world` stops clearing) fails check 5 — plus the landing mutation
## (indoor restore at the door instead of the landing) fails check 9.
## Round-1 mutations, one per MAJOR: restore-the-merge fails check 10, drop
## the pending list fails check 12, origin-without-base fails check 11.

## The end-of-check sentinel — see `scripts/selfcheck_sentinel.gd` for why every
## check stamps itself and the report site never prints SELFCHECK OK itself.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")
const SaveState := preload("res://scripts/save_state.gd")
const TowerGraph := preload("res://scripts/tower_graph.gd")
const MpManager: GDScript = preload("res://scripts/mp_manager.gd")
const BestRunStore := preload("res://scripts/best_run_store.gd")

## The bead's own acceptance list, as a source-of-truth string scan rather than
## a second dependency: the mirrored hero names must still be the heroes.
const PLAYER_SOURCE: String = "res://scripts/player_controller.gd"

## v1 carries exactly twelve fields (bead .1's blob). Every "we probed N
## fields" below is asserted against this, never merely counted.
const V1_FIELD_COUNT: int = 13

## Bead .2's round-trip fixtures: the acceptance case (seed, pos, hero 2, coins
## 37, distance 1200, captive primm, both masks, one lift landing).
const ROUND_TRIP_SEED: int = 20260904
const ROUND_TRIP_POS: Vector3 = Vector3(200.0, 2.0, -300.0)
const ROUND_TRIP_LIFT: String = "lift_stop_s3"
const PLAYER_SCENE: String = "res://scenes/player.tscn"
const TERRAIN_SCRIPT: String = "res://scripts/endless_terrain.gd"
const SHELL_SCENE: String = "res://scenes/tower/tower_shell.tscn"
const INTERIOR_SCENE: String = "res://scenes/tower/tower_interior.tscn"

## Check 3's hand-typed wire shape, in the encoder's own canonical form
## (sorted keys, no spaces) so check 4 can demand byte-equality with it.
const LITERAL: String = "{\"captives\":[\"primm\",\"teibi\"],\"coins\":1250,\"distance\":3340,\"explored\":7,\"hero\":2,\"in_hq\":true,\"landing\":\"lift_stop_s3\",\"lift\":[\"lift_stop_s3\"],\"pos\":[1234.5,0.0,-9876.25],\"saved_at\":1758326400,\"seed\":20260904,\"v\":1,\"waypoints\":3}"

var _failures: Array[String] = []


func _initialize() -> void:
	Sentinel.isolate_user_state()
	_check_round_trip()
	_check_bounds_reject()
	_check_wire_literal()
	_check_canonical_bytes()
	await _check_store_slot()
	await _check_player_round_trip()
	await _check_refusals()
	await _check_change_gate()
	await _check_hq_restore_at_landing()
	await _check_restore_replaces()
	await _check_distance_accumulates()
	await _check_pending_lift_ids()
	_report()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _rejects(raw: String, label: String) -> void:
	if not SaveState.decode(raw).is_empty():
		_failures.append("accepted %s: %s" % [label, raw.left(160)])


func _report() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
	else:
		for line: String in _failures:
			printerr("FAIL: %s" % line)
		printerr("SELFCHECK FAILED (%d)" % _failures.size())
		quit(1)


# ---------------------------------------------------------------------------
# CHECK 1 — a full boundary state and a minimal state both round-trip
# ---------------------------------------------------------------------------

func _check_round_trip() -> void:
	var all_stops: Array = []
	for row: Dictionary in TowerGraph.lift_stops():
		all_stops.append(String(row.get("unlock", "")))
	var full: Dictionary = {
		"captives": ["windman", "primm", "teibi", "phoboman"],
		"coins": 9007199254740990, # largest float-exact int under the cap (2^53 - 1 has no float spelling),
		"distance": 123456789,
		"explored": 4194303,
		"hero": 3,
		"in_hq": true,
		"landing": all_stops.back(),
		"lift": all_stops,
		"pos": [300000.0, -300000.0, 0.0],
		"saved_at": 1758326400,
		"seed": 4294967295,
		"v": 1,
		"waypoints": 2047,
	}
	_expect(SaveState.is_valid(full), "boundary state should be valid")
	var first: String = SaveState.encode(full)
	_expect(not first.is_empty(), "boundary state should encode")
	_expect(first.length() <= SaveState.MAX_SAVE_BYTES, "boundary blob oversize")
	var back: Dictionary = SaveState.decode(first)
	_expect(not back.is_empty(), "boundary blob should decode")
	_expect(back.get("seed", -1) == 4294967295, "seed should survive the wire")
	_expect(back.get("hero", -1) == 3, "hero should survive the wire")
	_expect(back.get("coins", -1) == 9007199254740990, "coins should survive the wire")
	_expect(back.get("explored", -1) == 4194303, "explored mask should survive")
	_expect(back.get("waypoints", -1) == 2047, "waypoint mask should survive")
	_expect(back.get("landing", "") == all_stops.back(), "landing should survive")
	_expect(back.get("captives", []) == ["windman", "primm", "teibi", "phoboman"],
		"captives should survive the wire")
	_expect((back.get("lift", []) as Array).size() == all_stops.size(),
		"lift stops should survive the wire")
	var pos_back: Array = back.get("pos", [])
	_expect(pos_back == [300000.0, -300000.0, 0.0], "pos should survive")
	_expect(pos_back.size() == 3 and typeof(pos_back[0]) == TYPE_FLOAT,
		"pos should decode as floats")
	_expect(SaveState.encode(back) == first, "re-encode should be byte-equal")
	# The positive half of every check-2 bound lives in that state: seed AT
	# the max, pos AT the max, hero 3, four captives, both masks maxed, the
	# full lift. What follows is the empty extreme.
	var minimal: Dictionary = {
		"captives": [],
		"coins": 0,
		"distance": 0,
		"explored": 0,
		"hero": 0,
		"in_hq": false,
		"landing": "",
		"lift": [],
		"pos": [0.0, 0.0, 0.0],
		"saved_at": 0,
		"seed": 0,
		"v": 1,
		"waypoints": 0,
	}
	var tiny: String = SaveState.encode(minimal)
	_expect(not tiny.is_empty(), "minimal state should encode")
	var tiny_back: Dictionary = SaveState.decode(tiny)
	_expect(not tiny_back.is_empty(), "minimal blob should decode")
	_expect(tiny_back.get("captives", [null]) == [] and tiny_back.get("lift", [null]) == [],
		"empty sets should survive the wire")
	_expect(tiny_back.get("landing", "") == "", "empty landing should survive")
	_expect(SaveState.encode(tiny_back) == tiny, "minimal re-encode byte-equal")
	Sentinel.done("round_trip")


# ---------------------------------------------------------------------------
# CHECK 2 — every bound fails closed, and the mirrored literals match the tables
# ---------------------------------------------------------------------------

func _check_bounds_reject() -> void:
	# The mirrors first: a stale literal here must fail LOUD, not accept wide.
	_expect(SaveState.MAX_RUN_SEED == MpManager.MAX_RUN_SEED,
		"seed bound drifted from mp_manager.MAX_RUN_SEED")
	_expect(SaveState.MAX_LIFT_IDS == TowerGraph.lift_stops().size(),
		"lift cap drifted from the tower's stop rows")
	_expect(SaveState.MAX_HERO_INDEX == SaveState.HERO_NAMES.size() - 1,
		"hero cap is not names-minus-one")
	_expect(SaveState.EXPLORED_MASK_MAX == (1 << 22) - 1,
		"explored cap is not 22 bits")
	_expect(SaveState.WAYPOINT_MASK_MAX == (1 << 11) - 1,
		"waypoint cap is not 11 bits")
	_expect(SaveState.KEYS.size() == V1_FIELD_COUNT,
		"KEYS holds %d fields, not the v1 %d" % [SaveState.KEYS.size(), V1_FIELD_COUNT])
	var player_source: String = FileAccess.get_file_as_string(PLAYER_SOURCE)
	for hero_name: String in SaveState.HERO_NAMES:
		_expect(player_source.contains("\"name\": \"%s\"" % hero_name),
			"hero %s left player_controller.CHARACTERS" % hero_name)
	# Then the probes. Each goes through decode (never is_valid alone), so M1
	# — decode returning the parsed dict unvalidated — turns this check RED.
	var seed_token: String = "\"seed\":20260904"
	_rejects(LITERAL.replace(seed_token, "\"seed\":4294967296"), "seed over max")
	_rejects(LITERAL.replace(seed_token, "\"seed\":1e999"), "seed INF")
	_rejects(LITERAL.replace(seed_token, "\"seed\":-1"), "negative seed")
	_rejects(LITERAL.replace(seed_token, "\"seed\":1.5"), "fractional seed")
	_rejects(LITERAL.replace(seed_token, "\"seed\":\"20260904\""), "string seed")
	var pos_token: String = "\"pos\":[1234.5,0.0,-9876.25]"
	_rejects(LITERAL.replace(pos_token, "\"pos\":[1e999,0.0,0.0]"), "pos INF")
	_rejects(LITERAL.replace(pos_token, "\"pos\":[400000.0,0.0,0.0]"), "pos over max")
	_rejects(LITERAL.replace(pos_token, "\"pos\":[-400000.0,0.0,0.0]"), "pos under min")
	_rejects(LITERAL.replace(pos_token, "\"pos\":\"nowhere\""), "pos as string")
	_rejects(LITERAL.replace(pos_token, "\"pos\":[1.0,2.0]"), "pos of two")
	_rejects(LITERAL.replace("\"hero\":2", "\"hero\":-1"), "hero -1")
	_rejects(LITERAL.replace("\"hero\":2", "\"hero\":4"), "hero 4")
	_rejects(LITERAL.replace("\"hero\":2", "\"hero\":\"primm\""), "hero as name")
	_rejects(LITERAL.replace("\"coins\":1250", "\"coins\":-5"), "negative coins")
	_rejects(LITERAL.replace("\"coins\":1250", "\"coins\":1.5"), "fractional coins")
	_rejects(LITERAL.replace("\"distance\":3340", "\"distance\":-1"), "negative distance")
	_rejects(LITERAL.replace("\"saved_at\":1758326400", "\"saved_at\":-1"), "negative saved_at")
	_rejects(LITERAL.replace("\"explored\":7", "\"explored\":1099511627776"),
		"explored bit 40")
	_rejects(LITERAL.replace("\"waypoints\":3", "\"waypoints\":1099511627776"),
		"waypoints bit 40")
	_rejects(LITERAL.replace("\"captives\":[\"primm\",\"teibi\"]",
		"\"captives\":[\"primm\",\"mallory\"]"), "unknown captive name")
	_rejects(LITERAL.replace("\"captives\":[\"primm\",\"teibi\"]",
		"\"captives\":[\"windman\",\"primm\",\"teibi\",\"phoboman\",\"primm\"]"),
		"five captives")
	_rejects(LITERAL.replace("\"captives\":[\"primm\",\"teibi\"]",
		"\"captives\":\"primm\""), "captives as string")
	_rejects(LITERAL.replace("\"lift\":[\"lift_stop_s3\"]",
		"\"lift\":[\"lift_stop_s8\"]"), "prefix lookalike lift id")
	_rejects(LITERAL.replace("\"lift\":[\"lift_stop_s3\"]",
		"\"lift\":[\"lift_stop_upper\",\"lift_stop_maze\",\"lift_stop_s3\",\"lift_stop_s4\",\"lift_stop_s5\",\"lift_stop_s6\",\"lift_stop_s7\",\"lift_stop_s9\",\"lift_stop_s10\",\"lift_stop_s3\"]"),
		"oversize lift")
	_rejects(LITERAL.replace("\"landing\":\"lift_stop_s3\"", "\"landing\":\"lift_stop_s8\""),
		"prefix lookalike landing")
	_rejects(LITERAL.replace("\"landing\":\"lift_stop_s3\"", "\"landing\":\"tower_checkpoint\""),
		"gate id as landing")
	_rejects(LITERAL.replace("\"landing\":\"lift_stop_s3\"", "\"landing\":5"),
		"landing as int")
	_rejects(LITERAL.replace("\"in_hq\":true", "\"in_hq\":1"), "in_hq as int")
	_rejects(LITERAL.replace("\"v\":1", "\"v\":2"), "v=2")
	_rejects(LITERAL.replace(",\"v\":1", ""), "v missing")
	_rejects("[]", "array blob")
	_rejects("{", "truncated blob")
	_rejects("", "empty blob")
	_rejects("\"lobby\"", "string blob")
	_rejects("null", "null blob")
	# The oversize probe stays otherwise VALID (blank padding), so only the
	# size gate can catch it — removing the gate (M3) turns this RED.
	var padding: String = "".lpad(SaveState.MAX_SAVE_BYTES + 1 - LITERAL.length(), " ")
	_rejects(LITERAL + padding, "oversize blob")
	# JSON has no NaN/INF literals, so these go through is_valid directly, plus
	# the encode-then-decode path a caller would actually drive.
	var wet: Dictionary = SaveState.decode(LITERAL)
	wet["pos"] = [NAN, 0.0, 0.0]
	_expect(not SaveState.is_valid(wet), "NaN pos should be invalid")
	_rejects(SaveState.encode(wet), "NaN pos should not round-trip")
	wet = SaveState.decode(LITERAL)
	wet["pos"] = [INF, 0.0, 0.0]
	_expect(not SaveState.is_valid(wet), "INF pos should be invalid")
	_rejects(SaveState.encode(wet), "INF pos should not round-trip")
	_expect(not SaveState.is_valid({}), "empty dict should be invalid")
	# Every field missing in turn. The count IS the assertion: a thirteenth
# field without a probe fails here, not silently.
	var erased: int = 0
	for key: String in SaveState.KEYS:
		var without: Dictionary = SaveState.decode(LITERAL)
		without.erase(key)
		erased += 1
		if not SaveState.decode(JSON.stringify(without)).is_empty():
			_failures.append("accepted blob missing %s" % key)
	_expect(erased == SaveState.KEYS.size(), "erased %d keys of %d" % [erased, SaveState.KEYS.size()])
	_expect(erased == V1_FIELD_COUNT, "probed %d fields, not the v1 %d" % [erased, V1_FIELD_COUNT])
	Sentinel.done("bounds_reject")


# ---------------------------------------------------------------------------
# CHECK 3 — the hand-typed literal decodes to the exact expected state
# ---------------------------------------------------------------------------

func _check_wire_literal() -> void:
	var state: Dictionary = SaveState.decode(LITERAL)
	_expect(not state.is_empty(), "literal should decode")
	_expect(state.get("v", 0) == 1, "literal v")
	_expect(state.get("saved_at", -1) == 1758326400, "literal saved_at")
	_expect(state.get("seed", -1) == 20260904, "literal seed")
	_expect(state.get("hero", -1) == 2, "literal hero")
	_expect(state.get("coins", -1) == 1250, "literal coins")
	_expect(state.get("distance", -1) == 3340, "literal distance")
	_expect(state.get("captives", []) == ["primm", "teibi"], "literal captives")
	_expect(state.get("explored", -1) == 7, "literal explored")
	_expect(state.get("waypoints", -1) == 3, "literal waypoints")
	_expect(state.get("lift", []) == ["lift_stop_s3"], "literal lift")
	_expect(state.get("in_hq", false) == true, "literal in_hq")
	_expect(state.get("landing", "") == "lift_stop_s3", "literal landing")
	_expect(state.get("pos", []) == [1234.5, 0.0, -9876.25], "literal pos")
	Sentinel.done("wire_literal")


# ---------------------------------------------------------------------------
# CHECK 4 — the literal is already canonical: re-encode is byte-equal
# ---------------------------------------------------------------------------

func _check_canonical_bytes() -> void:
	_expect(LITERAL.length() <= SaveState.MAX_SAVE_BYTES, "literal oversize")
	_expect(SaveState.encode(SaveState.decode(LITERAL)) == LITERAL,
		"re-encode should be byte-equal")
	Sentinel.done("canonical_bytes")

# ---------------------------------------------------------------------------
# CHECK 5 — the slot: write reads back, clear empties, archive/new_game clear
# ---------------------------------------------------------------------------

func _check_store_slot() -> void:
	var blob: String = LITERAL
	BestRunStore.write_save_slot(blob)
	_expect(BestRunStore.save_slot() == blob, "slot should read back the write")
	BestRunStore.clear_save_slot()
	_expect(BestRunStore.save_slot() == "", "clear should empty the slot")
	# An ended campaign has no Continue: the latch is set AND the slot is empty.
	BestRunStore.write_save_slot(blob)
	BestRunStore.archive_world()
	_expect(BestRunStore.world_archived(),
		"archive should set the latch (negative control)")
	_expect(BestRunStore.save_slot() == "", "archive should clear the slot")
	BestRunStore.new_game()
	_expect(not BestRunStore.world_archived(), "new_game should clear the latch")
	# ...and a New Game has none either.
	BestRunStore.write_save_slot(blob)
	BestRunStore.new_game()
	_expect(BestRunStore.save_slot() == "", "new_game should clear the slot")
	Sentinel.done("store_slot")


# ---------------------------------------------------------------------------
# CHECK 6 — the field round trip: write on one player, restore on a fresh one
# ---------------------------------------------------------------------------

func _check_player_round_trip() -> void:
	BestRunStore.clear_save_slot()
	var terrain = await _make_terrain()
	if terrain == null:
		Sentinel.done("player_round_trip")
		return
	terrain.set_run_seed(ROUND_TRIP_SEED)
	var player = await _make_player()
	if player == null:
		await _clear_world(terrain, null, null)
		Sentinel.done("player_round_trip")
		return
	var tower = await _make_tower_at(terrain.tower_site())
	if tower == null:
		await _clear_world(terrain, player, null)
		Sentinel.done("player_round_trip")
		return
	# Arrange the run: hero 2, a personal tally, one captive, both masks, one
	# lift landing earned through the shell's own seam.
	player.set_active_character(2)
	player.set("own_coins", 37)
	player.set("coins_collected", 37)
	player.set("own_distance", 1200)
	player.set("run_distance", 1200)
	player.set("explored_mask", 41)
	player.set("waypoint_mask", 9)
	player.set_hero_captive("primm", true)
	tower.call("mark_opened", ROUND_TRIP_LIFT)
	player.global_position = ROUND_TRIP_POS
	# Synchronous: with no chunks built there is no ground, so any frame between
	# the placement and the snapshot is a fall that moves the assertion.
	player.write_save()
	var raw: String = BestRunStore.save_slot()
	_expect(not raw.is_empty(), "write_save should fill the slot")
	var snap: Dictionary = SaveState.decode(raw)
	_expect(snap.get("seed", -1) == ROUND_TRIP_SEED, "seed should be snapshotted")
	_expect(snap.get("hero", -1) == 2, "hero should be snapshotted")
	_expect(snap.get("coins", -1) == 37, "own coins should be snapshotted")
	_expect(snap.get("distance", -1) == 1200, "own distance should be snapshotted")
	_expect(snap.get("captives", []) == ["primm"], "captives should be snapshotted")
	_expect(snap.get("explored", -1) == 41, "explored mask should be snapshotted")
	_expect(snap.get("waypoints", -1) == 9, "waypoint mask should be snapshotted")
	_expect(snap.get("lift", []) == [ROUND_TRIP_LIFT], "lift ids should be snapshotted")
	_expect(snap.get("in_hq", true) == false, "field save should not be in_hq")
	_expect(snap.get("landing", "x") == "", "field save should carry no landing")
	_expect((snap.get("pos", []) as Array) == [200.0, 2.0, -300.0],
		"pos should be snapshotted exactly")
	# A FRESH player and terrain: the restore is the joiner path, not a reload.
	await _clear_world(terrain, player, tower)
	var terrain2 = await _make_terrain()
	if terrain2 == null:
		Sentinel.done("player_round_trip")
		return
	var player2 = await _make_player()
	var tower2 = await _make_shell_at(terrain2.tower_site())
	var spy := CaptiveSpy.new()
	# Parked far from anywhere the harness stands: the spy is only a
	# `set_captive` seam, but `_is_in_hq_now()` answers off WHATEVER node is in
	# the group — a spy at the origin reads "indoors" for the spawning player,
	# the crossing edge flips, and its auto-checkpoint clobbers the slot before
	# `continue_save()` reads it (deterministic at --fixed-fps, load-flaky
	# otherwise, invisible at full speed where no physics step lands in the
	# one-frame window).
	spy.position = Vector3(5000.0, 0.0, 5000.0)
	spy.add_to_group("tower_interior")
	root.add_child(spy)
	await process_frame
	if player2 == null or tower2 == null:
		spy.queue_free()
		await _clear_world(terrain2, player2, tower2)
		Sentinel.done("player_round_trip")
		return
	_expect(await player2.continue_save(), "continue_save should accept the slot")
	_expect(int(terrain2.get("run_seed")) == ROUND_TRIP_SEED,
		"seed should restore through new_run")
	var xz := Vector2(player2.global_position.x, player2.global_position.z)
	# `_place_near()` settles on rings out to 12 m, so the bead's 2 m figure is
	# the ring's, not the anchor's: this asserts the ring, which is what proves
	# the joiner path ran rather than an exact set.
	_expect(xz.distance_to(Vector2(ROUND_TRIP_POS.x, ROUND_TRIP_POS.z)) <= 12.5,
		"pos should restore onto the _place_near ring")
	_expect(player2.get("current_character_index") == 2, "hero should restore")
	_expect(player2.get("own_coins") == 37 and player2.get("coins_collected") == 37,
		"coins should restore personally, not from the room bank")
	_expect(player2.get("own_distance") == 1200 and player2.get("run_distance") == 1200,
		"distance should restore")
	var captives_back: Dictionary = player2.get("captive_heroes")
	_expect(captives_back == {"primm": true}, "captive set should restore")
	_expect(player2.get("explored_mask") == 41, "explored mask should OR back")
	_expect(player2.get("waypoint_mask") == 9, "waypoint mask should OR back")
	_expect(bool(tower2.call("is_opened", ROUND_TRIP_LIFT)),
		"the lift landing should re-light")
	_expect(Array(tower2.call("earned_ids")).has(ROUND_TRIP_LIFT),
		"the lift landing should sit in shell.earned")
	# M2's detector: a restore that writes `captive_heroes` directly never
	# calls the seam — the spy stays silent. The seam is `set_hero_captive`,
	# never the dict.
	_expect(spy.calls == [["primm", true]],
		"the tower mirror should hold primm after restore")
	# A restore is not distance run: the origin resets under the body, so the
	# next metre walked counts from there instead of banking the jump.
	var origin: Vector2 = player2.get("own_distance_origin")
	_expect(origin.distance_to(xz) < 0.05,
		"own_distance_origin should reset under the restored body")
	spy.queue_free()
	await _clear_world(terrain2, player2, tower2)
	Sentinel.done("player_round_trip")


# ---------------------------------------------------------------------------
# CHECK 7 — refusals: bad body, a room, an ended world, a bad blob
# ---------------------------------------------------------------------------

func _check_refusals() -> void:
	var terrain = await _make_terrain()
	if terrain == null:
		Sentinel.done("refusals")
		return
	terrain.set_run_seed(ROUND_TRIP_SEED)
	var player = await _make_player()
	if player == null:
		await _clear_world(terrain, null, null)
		Sentinel.done("refusals")
		return
	# A body that is not the player's to move is not a body to save.
	player.set("is_game_over", true)
	_expect(player.save_snapshot().is_empty(),
		"save_snapshot should refuse while is_game_over")
	player.set("is_game_over", false)
	# A room: the master's seed wins, so Continue refuses and moves nothing. The
	# slot holds a RESTORABLE field save (written from this body, synchronously,
	# so gravity cannot move it first) — so only the room refusal can explain a
	# refusal: without it (M3) the restore proceeds and the body moves.
	player.global_position = ROUND_TRIP_POS
	player.write_save()
	_expect(player.has_save(), "setup: the field save should be restorable")
	player.set_physics_process(false)
	var stub := FakeRoomSeed.new()
	stub.add_to_group("mp")
	root.add_child(stub)
	await process_frame
	var before: Vector3 = player.global_position
	_expect(not await player.continue_save(), "continue_save should refuse in a room")
	_expect(player.global_position == before,
		"a refused restore should move nothing")
	stub.queue_free()
	player.set_physics_process(true)
	await process_frame
	# An ended world: the slot was cleared at archive time, so there is nothing
	# to Continue — and the latch says so even if a blob survived.
	BestRunStore.write_save_slot(LITERAL)
	BestRunStore.archive_world()
	_expect(not player.has_save(), "has_save should be false on an archived world")
	BestRunStore.new_game()
	# A bad blob decodes as no-save and refuses without moving.
	BestRunStore.write_save_slot("garbage")
	_expect(not await player.continue_save(), "continue_save should refuse a bad blob")
	BestRunStore.clear_save_slot()
	_expect(not player.has_save(), "has_save should be false on an empty slot")
	await _clear_world(terrain, player, null)
	Sentinel.done("refusals")


# ---------------------------------------------------------------------------
# CHECK 8 — the change gate: a standing player writes nothing, a step writes
# ---------------------------------------------------------------------------

func _check_change_gate() -> void:
	BestRunStore.clear_save_slot()
	var terrain = await _make_terrain()
	if terrain == null:
		Sentinel.done("change_gate")
		return
	terrain.set_run_seed(ROUND_TRIP_SEED)
	var player = await _make_player()
	if player == null:
		await _clear_world(terrain, null, null)
		Sentinel.done("change_gate")
		return
	player.global_position = ROUND_TRIP_POS
	# Physics off: with no chunks built there is no ground, and a fall between
	# the two writes is a change the gate must NOT absorb.
	player.set_physics_process(false)
	player.write_save()
	var first: String = BestRunStore.save_slot()
	_expect(not first.is_empty(), "the first write should fill the slot")
	var first_at: int = int(SaveState.decode(first).get("saved_at", -1))
	# Past the clock tick, so a missing gate (M4) cannot hide behind the same
	# second: without the gate the rewrite carries a newer saved_at.
	await create_timer(1.2).timeout
	player.write_save()
	_expect(BestRunStore.save_slot() == first,
		"a standing player should write byte-identical bytes")
	_expect(int(SaveState.decode(BestRunStore.save_slot()).get("saved_at", -2)) == first_at,
		"saved_at should not move when nothing changed")
	# One step: the rest changed, so the slot follows.
	player.global_position += Vector3(5.0, 0.0, 0.0)
	player.write_save()
	_expect(BestRunStore.save_slot() != first, "a 5 m step should rewrite the slot")
	player.set_physics_process(true)
	await _clear_world(terrain, player, null)
	Sentinel.done("change_gate")


# ---------------------------------------------------------------------------
# CHECK 9 — an indoor save restores at the lift, never at the door
# ---------------------------------------------------------------------------

func _check_hq_restore_at_landing() -> void:
	BestRunStore.clear_save_slot()
	var terrain = await _make_terrain()
	if terrain == null:
		Sentinel.done("hq_restore_at_landing")
		return
	terrain.set_run_seed(ROUND_TRIP_SEED)
	var player = await _make_player()
	var tower = await _make_tower_at(terrain.tower_site())
	if player == null or tower == null:
		await _clear_world(terrain, player, tower)
		Sentinel.done("hq_restore_at_landing")
		return
	var interior: Node3D = tower.get_node_or_null("TowerInterior") as Node3D
	_expect(interior != null, "the manual tower should carry its interior")
	if interior == null:
		await _clear_world(terrain, player, tower)
		Sentinel.done("hq_restore_at_landing")
		return
	# Stand on the s3 landing with its stop earned, then snapshot synchronously:
	# no frame may pass between the placement and the write or gravity moves it.
	var floor_s3 := _stop_floor(ROUND_TRIP_LIFT)
	_expect(floor_s3 >= 0, "s3 should land on a real storey (negative control)")
	tower.call("mark_opened", ROUND_TRIP_LIFT)
	var stand: Vector3 = interior.global_position + TowerInterior.lift_stand(floor_s3)
	player.global_position = stand
	player.write_save()
	var raw: String = BestRunStore.save_slot()
	var snap: Dictionary = SaveState.decode(raw)
	_expect(snap.get("in_hq", false) == true, "the landing save should be in_hq")
	_expect(String(snap.get("landing", "")) == ROUND_TRIP_LIFT,
		"the landing field should name the earned stop")
	# Fresh everything: the restore must climb back to the landing, not the door.
	await _clear_world(terrain, player, tower)
	var terrain2 = await _make_terrain()
	if terrain2 == null:
		Sentinel.done("hq_restore_at_landing")
		return
	terrain2.set_run_seed(ROUND_TRIP_SEED + 1)
	var player2 = await _make_player()
	if player2 == null:
		await _clear_world(terrain2, null, null)
		Sentinel.done("hq_restore_at_landing")
		return
	# NO manual tower here: the restore's own `new_run()` + ring streams the
	# terrain's shell (the one production lookup finds), and a manual second
	# shell would rival it in the group.
	_expect(await player2.continue_save(), "continue_save should accept the indoor slot")
	var tower2: Node = get_first_node_in_group("tower")
	_expect(tower2 != null, "the restore should have streamed the tower")
	var interior2: Node3D = get_first_node_in_group("tower_interior") as Node3D
	_expect(interior2 != null, "the restore should have streamed the interior")
	var want: Vector3 = interior2.global_position + TowerInterior.lift_stand(floor_s3)
	var got: Vector3 = player2.global_position
	_expect(got.distance_to(want) < 1.0,
		"an indoor save should restore at the landing's lift stand")
	_expect(got.y > 10.0, "the restore should be up-storey, not at the door")
	var site: Vector3 = terrain2.tower_site()
	var door_out := Vector3(site.x + terrain2.TOWER_RADIUS + 20.0, 0.0, site.z)
	_expect(Vector2(got.x - door_out.x, got.z - door_out.z).length() > 20.0,
		"the restore should not be at the door's outside point")
	_expect(bool(tower2.call("is_opened", ROUND_TRIP_LIFT)),
		"the restored landing should re-light the lift")
	# ...and with no landing earned, the entry: a second player in the same
	# world, standing on an unearned landing, snapshots landing "".
	var player3 = await _make_player()
	if player3 == null:
		await _clear_world(terrain2, player2, tower2)
		Sentinel.done("hq_restore_at_landing")
		return
	var floor_s4 := _stop_floor("lift_stop_s4")
	_expect(floor_s4 >= 0, "s4 should land on a real storey (negative control)")
	player3.global_position = interior2.global_position \
		+ TowerInterior.lift_stand(floor_s4)
	player3.write_save()
	var snap3: Dictionary = SaveState.decode(BestRunStore.save_slot())
	_expect(String(snap3.get("landing", "x")) == "",
		"an unearned landing should snapshot landing empty")
	_expect(await player3.continue_save(), "continue_save should accept the entry slot")
	# The second restore's own `new_run` freed and re-streamed the tower, so
	# the interior is re-read, never reused: a stale node is a freed one.
	var interior3: Node3D = get_first_node_in_group("tower_interior") as Node3D
	var entry_want: Vector3 = interior3.global_position + TowerInterior.entry_stand()
	_expect(player3.global_position.distance_to(entry_want) < 1.0,
		"landing empty should restore at the entry")
	player3.queue_free()
	await _clear_world(terrain2, player2, null)
	Sentinel.done("hq_restore_at_landing")


# ---------------------------------------------------------------------------
# HARNESS — bare terrain, the player scene, the tower's own assembly
# ---------------------------------------------------------------------------

## A room stub whose seed always answers: the "in a room" half of the refusals.
class FakeRoomSeed extends Node:
	func room_seed() -> Variant:
		return 7


## A tower-interior stand-in that records the captive mirror seam: the restore
## must reach the tower through `set_hero_captive()` (which calls `set_captive`
## here), never a direct `captive_heroes` write the building never sees. The
## real interior would mask M2 — it re-seeds `_captives` from the player set on
## build — so the spy, not `_captives`, is the detector.
class CaptiveSpy extends Node3D:
	var calls: Array = []
	func set_captive(hero: String, held: bool) -> void:
		calls.append([hero, held])


func _make_terrain():
	"""
	A REAL terrain node in the tree, not a stub (`tower_site_selfcheck`'s
	recipe): `set_run_seed()` seeds it without building, `continue_save()`'s
	own `new_run()` builds the ring it restores into. UNTYPED on purpose — the
	terrain script has no `class_name`, so its consts (`TOWER_RADIUS`) and
	methods only resolve dynamically.
	"""
	var terrain := Node3D.new()
	terrain.set_script(load(TERRAIN_SCRIPT))
	root.add_child(terrain)
	await process_frame
	if not terrain.has_method("set_run_seed"):
		_expect(false, "terrain script failed to attach (run --import first?)")
		terrain.queue_free()
		return null
	return terrain


func _make_player() -> Node:
	"""The shipped player scene, in the tree (`progression_selfcheck`'s idiom)."""
	var packed: PackedScene = load(PLAYER_SCENE)
	if packed == null:
		_expect(false, "could not load %s" % PLAYER_SCENE)
		return null
	var player: Node = packed.instantiate()
	root.add_child(player)
	await physics_frame
	if not player.has_method("save_snapshot"):
		_expect(false, "player has no save_snapshot — did the script fail to attach?")
		player.queue_free()
		return null
	return player


func _make_shell_at(site: Vector3) -> Node3D:
	"""
	The shell alone, parked on the site: the `earned` set without the
	interior's triggers or its build-time captive re-seed.
	"""
	var shell := load(SHELL_SCENE).instantiate() as Node3D
	shell.position = site
	root.add_child(shell)
	await process_frame
	return shell


func _make_tower_at(site: Vector3) -> Node3D:
	"""
	Shell plus interior, assembled the way `endless_terrain` assembles them —
	the interior added BEFORE the shell enters the tree (`tower_lift_selfcheck`'s
	`_make_tower`), parked on the site.
	"""
	var shell := load(SHELL_SCENE).instantiate() as Node3D
	shell.add_child(load(INTERIOR_SCENE).instantiate())
	shell.position = site
	root.add_child(shell)
	await process_frame
	return shell


func _stop_floor(stop_id: String) -> int:
	"""The storey `stop_id`'s room lands on, or -1 for an unplanned one."""
	for row in TowerGraph.lift_stops():
		if String(row.get("unlock", "")) == stop_id:
			return TowerInterior.landing_floor(String(row.get("room", "")))
	return -1


func _clear_world(terrain: Node, player: Node, tower: Node) -> void:
	"""Free a check's world and let the groups forget it before the next."""
	for node in [terrain, player, tower]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	await process_frame
	await physics_frame

# ---------------------------------------------------------------------------
# CHECK 10 — a restore REPLACES per-run state, never merges into it
# ---------------------------------------------------------------------------

func _check_restore_replaces() -> void:
	BestRunStore.clear_save_slot()
	var terrain = await _make_terrain()
	if terrain == null:
		Sentinel.done("restore_replaces")
		return
	terrain.set_run_seed(ROUND_TRIP_SEED)
	# The checkpoint: hero 1, a small tally, NOBODY captive, small masks.
	var writer = await _make_player()
	if writer == null:
		await _clear_world(terrain, null, null)
		Sentinel.done("restore_replaces")
		return
	writer.set_active_character(1)
	writer.set("own_coins", 5)
	writer.set("coins_collected", 5)
	writer.set("own_distance", 60)
	writer.set("run_distance", 60)
	writer.set("explored_mask", 7)
	writer.set("waypoint_mask", 3)
	writer.global_position = ROUND_TRIP_POS
	writer.write_save()
	_expect(writer.has_save(), "setup: the checkpoint should be restorable")
	await _clear_world(terrain, writer, null)
	# A running player who has since been playing: primm captured, wide masks,
	# a big tally — none of it in the checkpoint.
	var terrain2 = await _make_terrain()
	if terrain2 == null:
		Sentinel.done("restore_replaces")
		return
	var player2 = await _make_player()
	var spy := CaptiveSpy.new()
	spy.position = Vector3(5000.0, 0.0, 5000.0)
	spy.add_to_group("tower_interior")
	root.add_child(spy)
	await process_frame
	if player2 == null:
		spy.queue_free()
		await _clear_world(terrain2, null, null)
		Sentinel.done("restore_replaces")
		return
	player2.set_hero_captive("primm", true)
	player2.set("own_coins", 999)
	player2.set("explored_mask", 255)
	player2.set("waypoint_mask", 1023)
	_expect(await player2.continue_save(), "continue_save should accept the slot")
	# The checkpoint's roster, not the union: primm walks free again, through
	# the mirror seam both ways.
	var captives_back: Dictionary = player2.get("captive_heroes")
	_expect(captives_back.is_empty(), "captives the checkpoint lacks should leave")
	_expect(spy.calls == [["primm", true], ["primm", false]],
		"the tower mirror should follow captives out as well as in")
	_expect(player2.get("explored_mask") == 7, "explored mask should be replaced")
	_expect(player2.get("waypoint_mask") == 3, "waypoint mask should be replaced")
	_expect(player2.get("current_character_index") == 1, "hero should restore")
	_expect(player2.get("own_coins") == 5, "coins should restore")
	spy.queue_free()
	await _clear_world(terrain2, player2, null)
	Sentinel.done("restore_replaces")


# ---------------------------------------------------------------------------
# CHECK 11 — distance keeps climbing from the checkpoint (base + offset)
# ---------------------------------------------------------------------------

func _check_distance_accumulates() -> void:
	BestRunStore.clear_save_slot()
	var terrain = await _make_terrain()
	if terrain == null:
		Sentinel.done("distance_accumulates")
		return
	terrain.set_run_seed(ROUND_TRIP_SEED)
	var writer = await _make_player()
	if writer == null:
		await _clear_world(terrain, null, null)
		Sentinel.done("distance_accumulates")
		return
	writer.set("own_distance", 1200)
	writer.set("run_distance", 1200)
	writer.global_position = ROUND_TRIP_POS
	writer.write_save()
	_expect(writer.has_save(), "setup: the 1200 m checkpoint should be restorable")
	await _clear_world(terrain, writer, null)
	var terrain2 = await _make_terrain()
	if terrain2 == null:
		Sentinel.done("distance_accumulates")
		return
	var player2 = await _make_player()
	if player2 == null:
		await _clear_world(terrain2, null, null)
		Sentinel.done("distance_accumulates")
		return
	_expect(await player2.continue_save(), "continue_save should accept the slot")
	# Seated, not frozen: both figures read the checkpoint with the new travel
	# measured from under the body.
	_expect(player2.get("own_distance") == 1200, "own distance should restore")
	_expect(player2.get("run_distance") == 1200, "run distance should restore")
	_expect(player2.get("own_distance_base") == 1200, "own base should seat")
	_expect(player2.get("run_distance_base") == 1200, "run base should seat")
	# 100 m on foot counts from the checkpoint, not from zero and not from a
	# second 1200: an origin reset without the base (the old code) stays 1200.
	player2.global_position += Vector3(100.0, 0.0, 0.0)
	await physics_frame
	await physics_frame
	_expect(player2.get("own_distance") == 1300,
		"own distance should climb from the checkpoint")
	_expect(player2.get("run_distance") == 1300,
		"run distance should climb from the checkpoint")
	await _clear_world(terrain2, player2, null)
	Sentinel.done("distance_accumulates")


# ---------------------------------------------------------------------------
# CHECK 12 — lift landings survive a shell-less restore via the pending list
# ---------------------------------------------------------------------------

func _check_pending_lift_ids() -> void:
	BestRunStore.clear_save_slot()
	var terrain = await _make_terrain()
	if terrain == null:
		Sentinel.done("pending_lift_ids")
		return
	terrain.set_run_seed(ROUND_TRIP_SEED)
	var writer = await _make_player()
	var tower = await _make_tower_at(terrain.tower_site())
	if writer == null or tower == null:
		await _clear_world(terrain, writer, tower)
		Sentinel.done("pending_lift_ids")
		return
	tower.call("mark_opened", ROUND_TRIP_LIFT)
	writer.global_position = ROUND_TRIP_POS
	writer.write_save()
	var snap: Dictionary = SaveState.decode(BestRunStore.save_slot())
	_expect(snap.get("lift", []) == [ROUND_TRIP_LIFT], "setup: the save should carry the lift")
	await _clear_world(terrain, writer, tower)
	# Restore with NO shell in the tree (a field position far from the tower):
	# the landing must wait on the player, not die with the frame.
	var terrain2 = await _make_terrain()
	if terrain2 == null:
		Sentinel.done("pending_lift_ids")
		return
	var player2 = await _make_player()
	if player2 == null:
		await _clear_world(terrain2, null, null)
		Sentinel.done("pending_lift_ids")
		return
	_expect(await player2.continue_save(), "continue_save should accept the slot")
	_expect(Array(player2.get("_pending_lift_ids")) == [ROUND_TRIP_LIFT],
		"the landing should wait pending with no shell to take it")
	var snap2: Dictionary = player2.save_snapshot()
	_expect(snap2.get("lift", []) == [ROUND_TRIP_LIFT],
		"the next snapshot must still carry the pending landing")
	# A shell streams in: the pending ids seat `earned` on the first tick, and
	# the snapshot keeps carrying them.
	var tower2 = await _make_shell_at(terrain2.tower_site())
	await physics_frame
	await physics_frame
	_expect(Array(tower2.call("earned_ids")).has(ROUND_TRIP_LIFT),
		"the streamed shell should earn the pending landing")
	_expect(Array(player2.get("_pending_lift_ids")).is_empty(),
		"the pending list should drain into the shell")
	var snap3: Dictionary = player2.save_snapshot()
	_expect(snap3.get("lift", []) == [ROUND_TRIP_LIFT],
		"the snapshot should carry the landing after the drain")
	await _clear_world(terrain2, player2, tower2)
	Sentinel.done("pending_lift_ids")
