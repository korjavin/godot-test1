extends SceneTree
## ============================================================================
## SAVE FORMAT SELF-CHECK — run headless, prints "SELFCHECK OK", exits 0
## ============================================================================
##
##     godot --headless --path . --script res://scripts/save_selfcheck.gd
##
## Guards `scripts/save_state.gd` (epic godot-test1-i8yu, bead .1), the pure
## v1 encode/decode both save tiers share. Four checks:
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
##
## NON-VACUOUS by construction (bead .1 names the shape): checks 1, 3 and 4
## expect VALUES, not `{}`. The named mutations each turn a check RED:
## M1 (decode skips is_valid) fails check 2; M2 (captives name check dropped)
## fails check 2's unknown-name probe; M3 (size gate removed) fails check 2's
## oversize probe; M4 (is_valid false for everything) fails checks 1 and 3.

## The end-of-check sentinel — see `scripts/selfcheck_sentinel.gd` for why every
## check stamps itself and the report site never prints SELFCHECK OK itself.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")
const SaveState := preload("res://scripts/save_state.gd")
const TowerGraph := preload("res://scripts/tower_graph.gd")
const MpManager: GDScript = preload("res://scripts/mp_manager.gd")

## The bead's own acceptance list, as a source-of-truth string scan rather than
## a second dependency: the mirrored hero names must still be the heroes.
const PLAYER_SOURCE: String = "res://scripts/player_controller.gd"

## v1 carries exactly twelve fields (bead .1's blob). Every "we probed N
## fields" below is asserted against this, never merely counted.
const V1_FIELD_COUNT: int = 13

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
