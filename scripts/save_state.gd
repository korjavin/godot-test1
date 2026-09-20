class_name SaveState
extends RefCounted
## ============================================================================
## THE SAVE FORMAT (v1) — one JSON blob for both save tiers (epic godot-test1-i8yu)
## ============================================================================
##
## Both tiers (the `[save]` slot in `best_run.cfg` / `ck_save`, and the lobby's
## future `/save`) hold the SAME string, so there is ONE parse path. Everything
## that comes back from storage is untrusted — the server copy is written by
## whoever knows the id, and localStorage is editable by hand — hence
## `mp_codec.gd`'s rule applies verbatim: type-check and bound every field, and
## `decode()` returns `{}` on ANY fault, never a partial dict.
##
## The blob (v1):
##   {"v":1,"saved_at":<unix s>,"seed":<0..MAX_RUN_SEED>,"pos":[x,y,z],
##    "hero":<0..3>,"coins":<int>=0>,"distance":<int>=0>,
##    "captives":[<hero name>...],"explored":<22-bit mask>,"waypoints":<11-bit mask>,
##    "lift":[<lift ids>...],"landing":<lift id or "">,"in_hq":<bool>}
##
## `landing` is the restore point inside the HQ (owner amendment 2026-09-20):
## a save made indoors restores AT THE LIFT — the last landing visited — never
## at an interior XYZ. It is `""` while no landing has been earned yet and is
## only read when `in_hq` is true; `pos` stays for the field case. The value is
## one of the shell's per-run lift ids (the set `tower_shell.earned` holds and
## the profile drops), never the monotone `tower_checkpoint` gate id.
##
## PURE: static only, no nodes, no autoload, no file I/O, no RNG. The game side
## (bead .2) only calls `SaveState.encode(state)` / `SaveState.decode(raw)`.
## Canonical bytes come free: `JSON.stringify` sorts keys, and both ends
## normalize (ints as ints, positions as floats), so two equal states are
## byte-equal and `encode(decode(s)) == s` holds for every canonical `s`.

## Wire major. v != 1 decodes as no-save: a future v2 decoder migrates v1 up,
## a v1 decoder never guesses at v2 (forward-only).
const VERSION: int = 1

## The v1 field count. The self-check's missing-field loop must erase exactly
## this many keys — a field added without a probe fails BY COUNT.
const KEYS: Array[String] = ["captives", "coins", "distance", "explored",
	"hero", "in_hq", "landing", "lift", "pos", "saved_at", "seed", "v",
	"waypoints"]

## Same bound `mp_manager._receive_seed` enforces before its `int()` cast: JSON
## numbers arrive as floats, `1e999` parses to INF, and `int(INF)` traps wasm.
const MAX_RUN_SEED: float = 4294967295.0

## A few hundred km. The field is infinite but a float beyond that is a corrupt
## blob, not a player.
const MAX_ABS_POS: float = 300000.0

## ~6x the real blob size. An oversize string is "no save" BEFORE `parse_string`.
const MAX_SAVE_BYTES: int = 2048

## `player_controller.CHARACTERS.size() - 1` (four heroes); mirrored, not
## referenced, so this file stays dependency-free toward the player.
const MAX_HERO_INDEX: int = 3

## Mirrors `player_controller.CHARACTERS` names (:615). An unknown name rejects
## the whole blob — a renamed hero must land here too, or saves stop loading.
const HERO_NAMES: Array[String] = ["windman", "primm", "teibi", "phoboman"]

## One captive per hero; five entries is corruption, not a crowd.
const MAX_CAPTIVES: int = 4

## 22 landmark bits (`budapest_plan.SLOTS`); bit 22 and up is corruption.
const EXPLORED_MASK_MAX: int = 4194303

## 11 waypoint circles (`terrain_waypoints.WAYPOINT_COUNT`); bit 11 and up is
## corruption.
const WAYPOINT_MASK_MAX: int = 2047

## One entry per `tower_graph.lift_stops()` row (9 today: upper, maze, s3-s7,
## s9, s10); each id must pass `TowerGraph.is_lift_stop_id`, which is derived
## from the same rows, so a prefix lookalike (`lift_stop_s8`) still fails.
const MAX_LIFT_IDS: int = 9

## 2^53 - 1, as an INT: the float literal `9007199254740991.0` does not survive
## Godot's decimal parse exactly, so the cap lives in the int domain and the
## check below compares there. Doubles stop being exact integers above it, so
## the unbounded counters (coins, distance, saved_at) cap here rather than
## losing precision silently through the wire float.
const MAX_SAFE_INT: int = 9007199254740991


## The whole validity rule, and what `decode()` uses: every key present, every
## value typed and bounded. Anything else is `{}` at the call site.
static func is_valid(state: Dictionary) -> bool:
	for key: String in KEYS:
		if not state.has(key):
			return false
	if not _is_int_in(state["v"], 1, 1):
		return false
	if not _is_int_in(state["saved_at"], 0, MAX_SAFE_INT):
		return false
	if not _is_int_in(state["seed"], 0, int(MAX_RUN_SEED)):
		return false
	if not _is_int_in(state["hero"], 0, MAX_HERO_INDEX):
		return false
	if not _is_int_in(state["coins"], 0, MAX_SAFE_INT):
		return false
	if not _is_int_in(state["distance"], 0, MAX_SAFE_INT):
		return false
	if not _is_int_in(state["explored"], 0, EXPLORED_MASK_MAX):
		return false
	if not _is_int_in(state["waypoints"], 0, WAYPOINT_MASK_MAX):
		return false
	if typeof(state["in_hq"]) != TYPE_BOOL:
		return false
	if not _is_pos(state["pos"]):
		return false
	if not _is_name_set(state["captives"], HERO_NAMES, MAX_CAPTIVES):
		return false
	if not _is_lift(state["lift"]):
		return false
	if not _is_landing(state["landing"]):
		return false
	return true


## A valid state as a canonical string (`""` when invalid — which itself
## decodes as no-save, so an invalid state can never reach storage).
static func encode(state: Dictionary) -> String:
	if not is_valid(state):
		return ""
	return JSON.stringify(_normalized(state))


## The one parse path. Empty Dictionary on ANY fault — oversize, malformed,
## wrong shape, out of range — never a partial dict.
static func decode(raw: String) -> Dictionary:
	if raw.length() > MAX_SAVE_BYTES:
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var state: Dictionary = parsed
	if not is_valid(state):
		return {}
	return _normalized(state)


## Canonical value shapes: ints as ints (the wire gives floats), positions as
## floats, arrays as fresh copies. What makes re-encode byte-stable.
static func _normalized(state: Dictionary) -> Dictionary:
	var pos_in: Array = state["pos"]
	var captives_in: Array = state["captives"]
	var lift_in: Array = state["lift"]
	var captives_out: Array = []
	for hero_name: Variant in captives_in:
		captives_out.append(String(hero_name))
	var lift_out: Array = []
	for stop_id: Variant in lift_in:
		lift_out.append(String(stop_id))
	return {
		"captives": captives_out,
		"coins": _to_int(state["coins"]),
		"distance": _to_int(state["distance"]),
		"explored": _to_int(state["explored"]),
		"hero": _to_int(state["hero"]),
		"in_hq": bool(state["in_hq"]),
		"landing": String(state["landing"]),
		"lift": lift_out,
		"pos": [float(pos_in[0]), float(pos_in[1]), float(pos_in[2])],
		"saved_at": _to_int(state["saved_at"]),
		"seed": _to_int(state["seed"]),
		"v": VERSION,
		"waypoints": _to_int(state["waypoints"]),
	}


## A JSON number (int or float — the parser yields floats) holding an exact
## integer inside [lo, hi]. `floor` keeps `1.5` out, `is_finite` is the
## wasm-trap guard, and the verdict is an INT comparison: a float bound cannot
## spell 2^53 - 1 exactly, so the ±1.0 prefilter only absorbs that rounding and
## the cast-then-compare decides. A value with no exact float spelling (like
## int 2^53 - 1, which parses as 2^53) fails the final compare — correctly, as
## it could never survive the wire float.
static func _is_int_in(value: Variant, lo: int, hi: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var as_float: float = float(value)
	if not is_finite(as_float) or as_float != floor(as_float):
		return false
	if as_float < float(lo) - 1.0 or as_float > float(hi) + 1.0:
		return false
	var as_int: int = int(as_float)
	return as_int >= lo and as_int <= hi


## Three finite floats inside the world bound. Ints ride along (a hand-written
## blob may say `0`) and normalize to floats at the seam above.
static func _is_pos(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	var coords: Array = value
	if coords.size() != 3:
		return false
	for axis: Variant in coords:
		if typeof(axis) != TYPE_INT and typeof(axis) != TYPE_FLOAT:
			return false
		var metres: float = float(axis)
		if not is_finite(metres) or absf(metres) > MAX_ABS_POS:
			return false
	return true


## A duplicate-free array of known names, at most `cap`. Both name sets in v1
## are sets game-side, so a repeated entry is corruption, not a spare.
static func _is_name_set(value: Variant, allowed: Array[String], cap: int) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	var names: Array = value
	if names.size() > cap:
		return false
	var seen: Dictionary = {}
	for entry: Variant in names:
		if typeof(entry) != TYPE_STRING:
			return false
		var entry_name: String = String(entry)
		if not allowed.has(entry_name) or seen.has(entry_name):
			return false
		seen[entry_name] = true
	return true


## The HQ restore landing: `""` (no landing earned yet — the doorway case),
## otherwise one id passing the tower's own derived predicate, exactly the
## bound the `lift` set's members obey. `tower_checkpoint` is deliberately NOT
## admitted: it is a monotone gate id, not a landing, and the restore rides
## the lift.
static func _is_landing(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var landing_id: String = String(value)
	return landing_id == "" or TowerGraph.is_lift_stop_id(landing_id)


## The HQ's per-run lift memory: at most one entry per stop row, each passing
## the tower's own derived predicate (never a prefix rule).
static func _is_lift(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	var stops: Array = value
	if stops.size() > MAX_LIFT_IDS:
		return false
	var seen: Dictionary = {}
	for entry: Variant in stops:
		if typeof(entry) != TYPE_STRING:
			return false
		var stop_id: String = String(entry)
		if not TowerGraph.is_lift_stop_id(stop_id) or seen.has(stop_id):
			return false
		seen[stop_id] = true
	return true


## Integer value of a number `_is_int_in` already admitted (exact: admission
## means the float and the int spell the same value, so the cast is lossless).
static func _to_int(value: Variant) -> int:
	return int(float(value))
