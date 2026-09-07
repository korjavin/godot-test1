extends SceneTree
## The parser checks for the multiplayer layer: every check that instances no
## MANAGER (bead godot-test1-ftn.33's partition) — `MpCodec` statics and pure
## functions, plus the one avatar the ability check stands up (check 24 reads
## `_ready()`-built state, which is why `_initialize` waits a frame). Split out
## of `scripts/mp_selfcheck.gd`; CI shards the glob BY FILE, so this file is its
## own shard unit with its own Sentinel set.
##
## What it guards (section numbers below):
##
##   2. presence parser, 3. forced seed, 4. peer ids, 6. join-snapshot parser,
##   7. presence backcompat, 8. retired heart fields, 9. hero index,
##   10. croc-sync parser, 12. room multiplier, the `cap` / `pad` / `gate` verb
##   parsers, 24. ability visual state.
##
## Run it headless:
##
##     godot --headless --path . --script res://scripts/mp_codec_selfcheck.gd
##
## Prints "SELFCHECK OK" and quits 0, or prints the first failure and quits 1.
##
## Everything here is an explicit `if` rather than an `assert` on purpose:
## asserts are stripped from release builds, and this file's whole value is that
## it keeps working when somebody runs it a year from now against a release
## export. It touches no network and no WebRTC.


const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")
const MPManager: GDScript = preload("res://scripts/mp_manager.gd")
## The codec is reached through the `MpCodec` global class name everywhere it is
## CALLED. The preload stays for parity with `mp_selfcheck.gd` (bead ftn.33's
## "same preloads" rule) — the only `get_script_constant_map()` caller is there.
const MP_CODEC: GDScript = preload("res://scripts/mp_codec.gd")
const Terrain: GDScript = preload("res://scripts/endless_terrain.gd")
const Coin: GDScript = preload("res://scripts/coin.gd")
const Player: GDScript = preload("res://scripts/player_controller.gd")


func _initialize() -> void:
	Sentinel.isolate_user_state()
	# WAIT ONE FRAME FIRST. At `_initialize` the SceneTree's own root is not yet
	# inside the tree, so a node added to it never gets `_ready()` — and the
	# ability check below reads state the avatar builds there.
	await process_frame
	var failure: String = await _run_checks()
	if failure.is_empty():
		Sentinel.finish(self)
	else:
		printerr("SELFCHECK FAILED: " + failure)
		quit(1)


func _run_checks() -> String:
	"""Run every check in order. Returns "" on success, else the first failure."""
	var failure: String = _check_presence_parser()
	if not failure.is_empty():
		return failure
	failure = _check_forced_seed()
	if not failure.is_empty():
		return failure
	failure = _check_peer_ids()
	if not failure.is_empty():
		return failure
	failure = _check_state_parser()
	if not failure.is_empty():
		return failure
	failure = _check_presence_backcompat()
	if not failure.is_empty():
		return failure
	failure = _check_retired_heart_keys_are_tolerated()
	if not failure.is_empty():
		return failure
	failure = _check_hero_index()
	if not failure.is_empty():
		return failure
	failure = _check_croc_sync_parser()
	if not failure.is_empty():
		return failure
	failure = _check_room_multiplier()
	if not failure.is_empty():
		return failure
	failure = _check_captive_parser()
	if not failure.is_empty():
		return failure
	failure = _check_pad_parser()
	if not failure.is_empty():
		return failure
	failure = _check_gate_parser()
	if not failure.is_empty():
		return failure
	return _check_ability_visual_state()


# =============================================================================
# 2. UNTRUSTED PACKET PARSER
# =============================================================================

func _check_presence_parser() -> String:
	var good := {
		"p": Vector3(1.0, 2.0, 3.0),
		"y": 0.5,
		"c": 0,
		"s": 4.0,
		"g": true,
	}
	var decoded: Dictionary = MpCodec.decode_presence(var_to_bytes(good))
	if decoded.is_empty():
		return "parser rejected a well-formed packet"
	if decoded["p"] != good["p"] or decoded["c"] != 0 or decoded["g"] != true:
		return "parser mangled a well-formed packet: %s" % decoded

	# A finite but absurd yaw must come out BOUNDED, not merely accepted: it is
	# assigned straight to RemoteAvatar.rotation.y, and lerp_angle's `from +
	# short_way * weight` leaves 1e30 at 1e30 forever.
	var wild: Dictionary = MpCodec.decode_presence(var_to_bytes({
		"p": Vector3.ZERO, "y": 1.0e30, "c": 0, "s": 0.0, "g": true
	}))
	if wild.is_empty() or absf(wild["y"]) > TAU:
		return "parser let an absurd yaw through unbounded: %s" % wild

	# Each of these must be dropped whole, and none may crash the parser.
	# Two of them make the engine print a "decode_variant ... ERR_INVALID_DATA"
	# error line — that is bytes_to_var refusing the garbage, i.e. exactly the
	# behaviour under test. A passing run is noisy; only "SELFCHECK FAILED" and a
	# non-zero exit code mean anything.
	var bad: Array = [
		["random bytes", PackedByteArray([0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x22])],
		["empty bytes", PackedByteArray()],
		["not a dictionary", var_to_bytes("hello")],
		["missing p", var_to_bytes({"y": 0.0, "c": 0, "s": 0.0, "g": true})],
		["p as String", var_to_bytes({
			"p": "over there", "y": 0.0, "c": 0, "s": 0.0, "g": true
		})],
		["c out of range", var_to_bytes({
			"p": Vector3.ZERO, "y": 0.0, "c": 999999, "s": 0.0, "g": true
		})],
		["c negative", var_to_bytes({
			"p": Vector3.ZERO, "y": 0.0, "c": -7, "s": 0.0, "g": true
		})],
		["NaN position", var_to_bytes({
			"p": Vector3(NAN, 0.0, 0.0), "y": 0.0, "c": 0, "s": 0.0, "g": true
		})],
		# Finite but absurd. `s` is the one that latches: RemoteAvatar._animate
		# accumulates it into stride_phase, so one such packet makes every limb
		# rotation NaN for the rest of the room.
		["absurd speed", var_to_bytes({
			"p": Vector3.ZERO, "y": 0.0, "c": 0, "s": 1.0e30, "g": true
		})],
		["absurd position", var_to_bytes({
			"p": Vector3(1.0e30, 0.0, 0.0), "y": 0.0, "c": 0, "s": 0.0, "g": true
		})],
	]
	for case in bad:
		var result: Dictionary = MpCodec.decode_presence(case[1])
		if not result.is_empty():
			return "parser accepted a bad packet (%s): %s" % [case[0], result]
	Sentinel.done("presence_parser")
	return ""


# =============================================================================
# 3. FORCED SEED
# =============================================================================

func _check_forced_seed() -> String:
	# Never added to the tree, so _ready() (which would generate a whole world)
	# does not run — set_run_seed and _roll_biome_offset are pure.
	var terrain = Terrain.new()
	terrain.set_run_seed(12345)
	if terrain.run_seed != 12345:
		terrain.free()
		return "set_run_seed(12345) left run_seed == %d" % terrain.run_seed
	var first: Vector2 = terrain.biome_offset

	terrain.set_run_seed(12345)
	var second: Vector2 = terrain.biome_offset

	# A DIFFERENT seed must give a DIFFERENT offset. Without this the two checks
	# below are satisfied by a `_roll_biome_offset()` that ignores its seed
	# entirely and returns a fixed non-zero constant — i.e. they do not pin the
	# property this check is named for, that `run_seed` actually reaches the
	# biome field.
	terrain.set_run_seed(54321)
	var other: Vector2 = terrain.biome_offset
	terrain.free()

	if first != second:
		return "same seed gave different biome offsets: %s vs %s" % [first, second]
	if first == Vector2.ZERO:
		return "set_run_seed did not derive a biome offset"
	if other == first:
		return "a different seed gave the same biome offset — run_seed does not reach the biome field"
	Sentinel.done("forced_seed")
	return ""


# =============================================================================
# 4. PEER ID MAPPING
# =============================================================================

func _check_peer_ids() -> String:
	var samples: Array[String] = [
		"0123456789abcdef",
		"fedcba9876543210",
		"a1b2c3d4e5f60718",
		"00000000000000ff",
		"ffffffffffffffff",
	]
	var seen: Dictionary = {}
	for id in samples:
		var value: int = MpCodec.peer_int_id(id)
		if value < 2:
			return "peer_int_id(%s) == %d — must clear the reserved 0 and 1" % [id, value]
		if seen.has(value):
			return "peer_int_id collision: %s and %s both give %d" % [seen[value], id, value]
		seen[value] = id
	Sentinel.done("peer_ids")
	return ""


# =============================================================================
# 6. JOIN-SNAPSHOT PARSER
# =============================================================================

func _check_state_parser() -> String:
	"""
	`decode_state()` against hostile payloads. Its parameter is a typed
	`Dictionary` and `LobbyClient` only ever hands it one, so "not a dictionary"
	is enforced by the signature and cannot be exercised from here — an empty
	dictionary (every field missing) is the reachable shape of that case.

	EVERY PAYLOAD BELOW STILL CARRIES `ls`, ON PURPOSE. It is a retired heart field
	(bead godot-test1-0bc) and this file keeps sending it because an OLD PEER does:
	its presence in a snapshot must change nothing about how the snapshot is read,
	which makes each of these rows a second, free assertion of the wire tolerance
	check 8 owns.
	"""
	var good := {
		"cc": 42.0, "ls": 2.0, "dd": 1337.0,
		"px": 10.0, "py": 2.0, "pz": -5.0,
		"ids": [111.0, 222.0, -333.0],
	}
	var snapshot: Dictionary = MpCodec.decode_state(good)
	if snapshot.is_empty():
		return "state parser rejected a well-formed snapshot"
	if snapshot["cc"] != 42 or snapshot["dd"] != 1337:
		return "state parser mangled the counters: %s" % snapshot
	if snapshot.has("ls"):
		return "state parser carried the retired heart field through: %s" % snapshot
	if snapshot["pos"] != Vector3(10.0, 2.0, -5.0):
		return "state parser mangled the position: %s" % snapshot["pos"]
	if snapshot["ids"] != [111, 222, -333]:
		return "state parser mangled the id list: %s" % snapshot["ids"]
	# `dead` (the room's crushed-crocodile kill list) follows `gc`/`gs`'s rule, not
	# `ids`': MISSING IS NOT MALFORMED, because a peer on a build without the field
	# is still worth its position, its counters and its coin ids. `good` above
	# carries none, so it must read as an empty list rather than dropping.
	if snapshot["dead"] != ([] as Array[int]):
		return "state parser invented a kill list: %s" % snapshot["dead"]
	var with_dead: Dictionary = MpCodec.decode_state({
		"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
		"ids": [], "dead": [7.0, -8.0],
	})
	if with_dead.is_empty() or with_dead["dead"] != [7, -8]:
		return "state parser mangled the kill list: %s" % with_dead
	# `gc` (the room's frozen departed-member bank) follows the presence counters'
	# rule: MISSING IS NOT MALFORMED. `good` above carries none, so an older peer's
	# snapshot still lands, reading as zero. Its old sibling `gs` — the departed
	# members' spent HEARTS — retired with the hearts, so a snapshot carrying it is
	# accepted and the field is never read.
	if snapshot["gc"] != 0:
		return "state parser invented a departed-member bank: %s" % snapshot
	var with_gone: Dictionary = MpCodec.decode_state({
		"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
		"gc": 500.0, "gs": 3.0, "ids": [],
	})
	if with_gone.is_empty() or with_gone["gc"] != 500:
		return "state parser mangled the departed-member bank: %s" % with_gone
	if with_gone.has("gs"):
		return "state parser carried the retired departed-hearts field through: %s" % with_gone
	# `go` (the tower's opened set, bead godot-test1-d81) follows the same rule:
	# MISSING IS NOT MALFORMED, so a peer on a build without the field is still
	# worth its position and its counters. `good` above carries none, so it must
	# read as an empty list rather than dropping.
	if (snapshot["go"] as Array) != []:
		return "state parser invented an opened set: %s" % str(snapshot["go"])
	var with_opened: Dictionary = MpCodec.decode_state({
		"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
		"ids": [], "go": ["tower_vault", "tower_rescue_primm"],
	})
	if with_opened.is_empty() \
			or (with_opened["go"] as Array) != ["tower_vault", "tower_rescue_primm"]:
		return "state parser mangled the opened set: %s" % str(with_opened)
	var bad_opened: Array[Dictionary] = [
		{"cc": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0, "ids": [],
			"go": "tower_vault"},
		{"cc": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0, "ids": [],
			"go": [7]},
		{"cc": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0, "ids": [],
			"go": [""]},
	]
	for bad_snapshot: Dictionary in bad_opened:
		if not MpCodec.decode_state(bad_snapshot).is_empty():
			return "state parser accepted the malformed opened set %s" % str(bad_snapshot)

	# An over-long list is TRUNCATED, not rejected — the ids are sent
	# most-recent-first, so the head is the part nearest the joiner, and the
	# counters and position are still worth having.
	var long_ids: Array = []
	for i: int in range(MpCodec.MAX_STATE_IDS + 64):
		long_ids.append(float(i))
	var truncated: Dictionary = MpCodec.decode_state({
		"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
		"ids": long_ids,
	})
	if truncated.is_empty():
		return "state parser dropped an over-long snapshot instead of truncating it"
	if (truncated["ids"] as Array).size() != MpCodec.MAX_STATE_IDS:
		return "state parser truncated to %d ids, expected %d" % [
			(truncated["ids"] as Array).size(), MpCodec.MAX_STATE_IDS
		]
	# The kill list is bounded by the SAME cap at the SAME end, or a hostile peer
	# buys an unbounded `_dead_crocs` write with one snapshot.
	var long_dead: Dictionary = MpCodec.decode_state({
		"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
		"ids": [], "dead": long_ids,
	})
	if long_dead.is_empty():
		return "state parser dropped an over-long kill list instead of truncating it"
	if (long_dead["dead"] as Array).size() != MpCodec.MAX_STATE_IDS:
		return "state parser truncated the kill list to %d ids, expected %d" % [
			(long_dead["dead"] as Array).size(), MpCodec.MAX_STATE_IDS
		]

	# Each of these must be dropped WHOLE — a snapshot is trusted entire or not
	# at all, exactly like a presence packet.
	var bad: Array = [
		["empty payload", {}],
		["missing ids", {
			"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0
		}],
		["ids not an array", {
			"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
			"ids": "all of them"
		}],
		["an id that is not a number", {
			"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
			"ids": [1.0, "two", 3.0]
		}],
		["cc as String", {
			"cc": "lots", "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
			"ids": []
		}],
		["negative counter", {
			"cc": -1.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
			"ids": []
		}],
		["absurd counter", {
			"cc": 1.0e18, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
			"ids": []
		}],
		["NaN counter", {
			"cc": NAN, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
			"ids": []
		}],
		["NaN position", {
			"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": NAN, "py": 0.0, "pz": 0.0,
			"ids": []
		}],
		["INF position", {
			"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": INF, "pz": 0.0,
			"ids": []
		}],
		# Finite but absurd: this one feeds the join placement, so an accepted
		# 1e30 anchor drops the joiner where the terrain will never build.
		["absurd position", {
			"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 1.0e30, "py": 0.0, "pz": 0.0,
			"ids": []
		}],
		# Absent `gc` is fine (above); PRESENT AND BAD still drops the payload,
		# like every other LIVE field here. A retired one is different and is a
		# GOOD case rather than a bad one — see the block under the loop.
		["gc as String", {
			"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
			"gc": "loads", "ids": []
		}],
		# Absent `dead` is fine (above); PRESENT AND BAD drops the payload whole,
		# exactly as a bad `ids` does — same validator, same rule.
		["dead not an array", {
			"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
			"ids": [], "dead": "all of them"
		}],
		["a dead id that is not a number", {
			"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
			"ids": [], "dead": [1.0, "two", 3.0]
		}],
		["NaN dead id", {
			"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
			"ids": [], "dead": [NAN]
		}],
		# Past 2^53 an int() cast is undefined and on wasm the trunc can trap the
		# module — the reason MAX_STATE_ID_MAGNITUDE exists, now on both lists.
		["dead id past the double's exact range", {
			"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
			"ids": [], "dead": [1.0e30]
		}],
	]
	for case in bad:
		var result: Dictionary = MpCodec.decode_state(case[1])
		if not result.is_empty():
			return "state parser accepted a bad snapshot (%s): %s" % [case[0], result]

	# A RETIRED KEY IS NOT A FIELD ANY MORE, so a hostile value in one may not drop
	# the packet either — that would be validating a key nothing reads, and it would
	# make an old peer's honest `gs: 3` one refactor away from being a disconnect.
	# The negative `gs` below sat in the `bad` table above until bead
	# godot-test1-0bc; this is the same row, on the other side of the ledger.
	var stale: Dictionary = MpCodec.decode_state({
		"cc": 7.0, "dd": 9.0, "px": 0.0, "py": 0.0, "pz": 0.0, "ids": [],
		"ls": -1.0, "gs": -1.0,
	})
	if stale.is_empty():
		return "state parser dropped a snapshot over a retired heart field — an old peer "\
			+ "still sending ls/gs must be read for everything it does say"
	if stale["cc"] != 7 or stale["dd"] != 9:
		return "state parser mangled a snapshot that carried retired fields: %s" % stale
	Sentinel.done("state_parser")
	return ""


# =============================================================================
# 7. PRESENCE BACKWARD COMPATIBILITY
# =============================================================================

func _check_presence_backcompat() -> String:
	"""
	A phase-3 peer sends a presence packet with no `cc`/`dd`. Dropping those whole
	would make that peer INVISIBLE rather than merely uncounted, so absent must read
	as 0 — only a field that is present and bad may drop the packet.
	"""
	var legacy: Dictionary = MpCodec.decode_presence(var_to_bytes({
		"p": Vector3(3.0, 1.0, 4.0), "y": 0.25, "c": 1, "s": 2.0, "g": false
	}))
	if legacy.is_empty():
		return "parser rejected a phase-3 shaped packet (no shared totals)"
	if legacy["cc"] != 0 or legacy["dd"] != 0:
		return "a phase-3 packet did not read as zero contributions: %s" % legacy
	# ...and the compatibility runs FORWARD as well as back: `lv` (this peer's
	# spent hearts) and `rl` (the room's) retired with the hearts in bead
	# godot-test1-0bc, so they must be absent from what the parser hands out.
	if legacy.has("lv") or legacy.has("rl"):
		return "the presence parser still publishes a retired heart field: %s" % legacy
	# `pz` (the room-wide pause, bead godot-test1-3a2) is the newest field on this
	# packet and takes the same rule: a phase-3 peer sends none and must read as
	# "not pausing", or an older build would silently freeze the room it joins.
	if legacy.get("pz", null) != false:
		return "a packet with no pz did not read as not-paused: %s" % legacy
	for sent: bool in [true, false]:
		var explicit: Dictionary = MpCodec.decode_presence(var_to_bytes({
			"p": Vector3.ZERO, "y": 0.0, "c": 0, "s": 0.0, "g": true, "pz": sent
		}))
		if explicit.is_empty() or explicit["pz"] != sent:
			return "pz %s did not round-trip: %s" % [sent, explicit]
	# ...and unlike the counters there is nothing here to clamp, so a `pz` that is
	# not a bool is malformed and drops the packet WHOLE. `1` is the interesting
	# case: `bool(1)` is true everywhere in GDScript, so a parser that coerced
	# would let a peer pause the room with an int and never be noticed.
	# `null` is in the list on purpose: it is the one malformed shape that reads
	# as ABSENT through `get(key, null)`, so it is what a `has()`-less validator
	# would let past while every other junk value here failed.
	for junk: Variant in [1, 0, "yes", 1.0, Vector3.ZERO, null]:
		var poisoned_pause: Dictionary = MpCodec.decode_presence(var_to_bytes({
			"p": Vector3.ZERO, "y": 0.0, "c": 0, "s": 0.0, "g": true, "pz": junk
		}))
		if not poisoned_pause.is_empty():
			return "parser accepted a non-bool pz (%s): %s" % [junk, poisoned_pause]

	# Present-and-bad still drops the packet whole.
	var poisoned: Dictionary = MpCodec.decode_presence(var_to_bytes({
		"p": Vector3.ZERO, "y": 0.0, "c": 0, "s": 0.0, "g": true, "cc": -5
	}))
	if not poisoned.is_empty():
		return "parser accepted a negative coin contribution: %s" % poisoned

	# THE MIRROR OF THE SAME RULE, from the other side. Phase 5 discriminates
	# packet kinds on a `"t"` key and absence means presence, so a packet from a
	# LATER build — one carrying a verb this one has never heard of — must be
	# ignored, not fed to the presence path. It would decode there: the fields
	# below are a perfectly valid presence packet, so ONLY THE DISCRIMINATOR stops
	# it. Pin the discriminator itself: driving `_receive_mesh_verb()` instead
	# would assert nothing at all, because that function has no presence branch to
	# leak through and so passes however the dispatch is written.
	var later_build: Dictionary = {
		"t": "zzz_a_verb_from_a_later_build",
		"p": Vector3.ZERO, "y": 0.0, "c": 0, "s": 0.0, "g": true, "cc": 99,
	}
	if MpCodec.packet_kind(later_build) != "zzz_a_verb_from_a_later_build":
		return "a packet carrying an unknown verb did not read as that verb"
	var phase4: Dictionary = {"p": Vector3.ZERO, "y": 0.0, "c": 0, "s": 0.0, "g": true}
	if MpCodec.packet_kind(phase4) != "":
		return "a phase-3/4 packet with no \"t\" did not read as presence"
	Sentinel.done("presence_backcompat")
	return ""


# =============================================================================
# 8. THE RETIRED HEART FIELDS, AND THE OLD PEER STILL SENDING THEM
# =============================================================================

## What the shared-hearts machine used to put on the wire, both transports. `lv`
## and `rl` rode the presence broadcast, `ls` and `gs` the join snapshot. Bead
## godot-test1-0bc retired all four as MEANING and stopped sending `lv`/`rl`;
## `ls`/`gs` are still emitted as inert zeroes (case (e) fails the build if they
## are not). This list is what must keep being TOLERATED on the way IN, and it is
## the whole subject of check 8.
const RETIRED_WIRE_KEYS: Array[String] = ["lv", "rl", "ls", "gs"]

func _check_retired_heart_keys_are_tolerated() -> String:
	"""
	Wire compatibility by TOLERANT DECODERS, which is the pattern this file already
	holds every optional field to — never a protocol version bump.

	Hearts are gone (bead godot-test1-0bc) and with them the MEANING of the four
	fields that carried them — two of which, `ls` and `gs`, this build still emits
	as inert zeroes so the previous build's snapshot parser keeps accepting us (case
	(e)). A peer on an older build does not know any of it and keeps sending all
	four at live values, at whatever values its own dead arithmetic produced — including values
	that would have been REJECTED when the fields were live (`gs: -1` sat in check
	6's hostile table until this bead). Dropping such a packet would make that peer
	invisible over a number nothing reads, so the rule is three-part and all three
	are asserted here:

	  * ACCEPTED — the packet lands, on both transports;
	  * IGNORED — not one retired key comes back out of either decoder, so nothing
	    downstream can start reading one again by accident;
	  * UNVALIDATED — a hostile value in a retired key changes nothing, because
	    validating a field nobody reads is how the tolerance rots back into a
	    requirement.

	AND THE MIRROR, which is the half that actually catches a mistake: a LIVE field
	next to them is still fully validated. Without it "the packet was accepted"
	would also be true of a decoder that had stopped checking anything at all.
	"""
	# (a) PRESENCE. A full phase-5 packet plus the two retired keys, hostile.
	var presence: Dictionary = MpCodec.decode_presence(var_to_bytes({
		"p": Vector3(1.0, 2.0, 3.0), "y": 0.5, "c": 0, "s": 1.0, "g": true,
		"cc": 40, "dd": 12, "lv": -7, "rl": "three hearts",
	}))
	if presence.is_empty():
		return "the presence parser dropped a packet over a retired heart field — an old "\
			+ "peer still sending lv/rl would go invisible rather than merely uncounted"
	if presence["cc"] != 40 or presence["dd"] != 12:
		return "a packet carrying retired fields lost its live counters: %s" % presence

	# (b) THE JOIN SNAPSHOT, the other transport, the other two keys.
	var snapshot: Dictionary = MpCodec.decode_state({
		"cc": 40.0, "dd": 12.0, "px": 1.0, "py": 2.0, "pz": 3.0, "ids": [],
		"ls": -7.0, "gs": "three hearts",
	})
	if snapshot.is_empty():
		return "the snapshot parser dropped a join over a retired heart field — a joining "\
			+ "old peer would arrive with no position and no coin ids"
	if snapshot["cc"] != 40 or snapshot["dd"] != 12:
		return "a snapshot carrying retired fields lost its live counters: %s" % snapshot

	# (c) IGNORED, both ways out.
	for key: String in RETIRED_WIRE_KEYS:
		if presence.has(key):
			return "the presence parser hands out the retired field '%s': %s" % [key, presence]
		if snapshot.has(key):
			return "the snapshot parser hands out the retired field '%s': %s" % [key, snapshot]

	# (d) THE MIRROR: a LIVE field beside them is still validated, so (a) and (b)
	#     are tolerance rather than a decoder that has stopped looking.
	if not MpCodec.decode_presence(var_to_bytes({
		"p": Vector3.ZERO, "y": 0.0, "c": 0, "s": 0.0, "g": true,
		"cc": -5, "lv": 0,
	})).is_empty():
		return "the presence parser accepted a negative LIVE counter — relaxing the retired "\
			+ "keys has relaxed the trust boundary with them"
	if not MpCodec.decode_state({
		"cc": -1.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0, "ids": [], "ls": 0.0,
	}).is_empty():
		return "the snapshot parser accepted a negative LIVE counter — relaxing the retired "\
			+ "keys has relaxed the trust boundary with them"

	# (e) AND THE OTHER DIRECTION, which a tolerant decoder cannot cover by itself:
	#     OLD READS NEW. `build_version` deliberately refuses to reload a peer that
	#     is mid-run or in a room, so an old client outlives the deploy and both
	#     directions are live at once.
	#
	#     The pre-godot-test1-0bc snapshot parser REQUIRES `ls` and drops a payload
	#     without it whole — costing that joiner this peer's position, collected-coin
	#     ids, kill list and frozen bank for the room's whole life — so the send side
	#     keeps the two retired keys as inert zeroes for one release. Read off the
	#     source rather than a live manager: `_send_state_to()` needs a lobby, a room
	#     and a mesh, none of which exist headless.
	var source: String = FileAccess.get_file_as_string("res://scripts/mp_manager.gd")
	var send_start: int = source.find("func _send_state_to(")
	var send_end: int = source.find("\nfunc ", send_start + 1)
	var send_body: String = source.substr(send_start, send_end - send_start)
	for key: String in ["ls", "gs"]:
		if not send_body.contains('"%s": 0' % key):
			return "the join snapshot no longer sends the retired key '%s' — this build " % key \
				+ "does not read it, but the PREVIOUS one requires 'ls' and drops the whole "\
				+ "snapshot without it, so an old peer in a mixed room joins blind"

	# ...and the same rule one verb along. An older MASTER still publishes the
	# retired OVERTAKEN verdict (`co: 3`); the `room` packet is also the captive-set
	# repair channel, so a build that bounded `co` at its own highest verdict would
	# stop that room's cells converging over a field nobody reads. It folds UP, to
	# FAILED — never down to "running", which is the one value a non-master can
	# never leave: the master's verdict is its only exit from the scene, so a peer
	# reading OVERTAKEN as "still going" is sealed in the block on a dead clock for
	# the room's whole life.
	var stale: Dictionary = MpCodec.decode_room({"cap": ["primm"], "cd": 12.0, "co": 3})
	if stale.is_empty():
		return "decode_room dropped a packet over a retired verdict — an old master's "\
			+ "OVERTAKEN would cost the room its captive-set repair, not just the verdict"
	if stale["co"] != MpCodec.CUSTODY_VERDICT_MAX or stale["cap"] != ["primm"]:
		return "decode_room read a retired verdict as %s — an unreadable outcome must "\
			% str(stale) + "fold to FAILED, or the peer never leaves the break-out"
	if MpCodec.decode_room({"cap": [], "cd": 12.0, "co": 2})["co"] != 2:
		return "decode_room lost a verdict this build DOES know — the fold above is "\
			+ "swallowing live outcomes with the retired one"
	Sentinel.done("retired_heart_keys_are_tolerated")
	return ""


# =============================================================================
# 9. HERO NAME → CHARACTER INDEX
# =============================================================================

func _check_hero_index() -> String:
	"""
	The hero split is named by the lobby in strings and applied by the player in
	indices, so this lookup is the join between them. A silent -1 for a hero this
	build DOES have would strand that peer with no playable character.
	"""
	var characters: Array = Player.CHARACTERS
	for i: int in range(characters.size()):
		var hero: String = str((characters[i] as Dictionary).get("name", ""))
		var got: int = MPManager.hero_index(hero)
		if got != i:
			return "hero_index(%s) == %d, expected %d" % [hero, got, i]
	for unknown in ["", "gandalf", "WINDMAN"]:
		if MPManager.hero_index(unknown) != -1:
			return "hero_index(%s) resolved — an unknown hero must give -1" % unknown
	Sentinel.done("hero_index")
	return ""


# =============================================================================
# 10. CROCODILE SYNC PARSER
# =============================================================================

func _check_croc_sync_parser() -> String:
	"""
	`decode_croc_sync()` — the FOURTH trust boundary, and the widest-reaching one:
	an accepted packet drives every crocodile in the room, so a NaN that gets
	through interpolates to NaN for the room's life with no path back. Whole or
	nothing, exactly like the other three parsers.
	"""
	var good := {
		"t": "croc",
		"i": PackedInt32Array([11, 22]),
		"x": PackedFloat32Array([
			1.0, 0.0, 2.0, 0.5,
			-3.0, 0.0, 4.0, 1.25,
		]),
		"f": PackedByteArray([MpCodec.CROC_FLAG_CHASING, 0]),
	}
	var sync: Dictionary = MpCodec.decode_croc_sync(good)
	if sync.is_empty():
		return "croc-sync parser rejected a well-formed packet"
	var ids: PackedInt32Array = sync["ids"]
	var xf: PackedFloat32Array = sync["xf"]
	var flags: PackedByteArray = sync["flags"]
	if ids.size() != 2 or flags.size() != 2 or xf.size() != 8:
		return "croc-sync parser mangled the entry counts: %d/%d/%d" % [
			ids.size(), xf.size(), flags.size()
		]
	if ids[1] != 22 or flags[0] != MpCodec.CROC_FLAG_CHASING \
			or not is_equal_approx(xf[4], -3.0):
		return "croc-sync parser mangled a well-formed packet: %s" % sync

	# An absurd yaw comes back WRAPPED, not dropped — the same normalise-rather-
	# than-refuse rule `decode_presence` applies to `y`, and for the same reason:
	# the receiver eases it with lerp_angle, which is `from + short_way * weight`,
	# and `1e30 + anything small IS 1e30`.
	var wild: Dictionary = MpCodec.decode_croc_sync({
		"i": PackedInt32Array([1]),
		"x": PackedFloat32Array([0.0, 0.0, 0.0, 1.0e30]),
		"f": PackedByteArray([0]),
	})
	if wild.is_empty():
		return "croc-sync parser dropped an absurd yaw instead of wrapping it"
	var wrapped: float = (wild["xf"] as PackedFloat32Array)[3]
	if wrapped < 0.0 or wrapped >= TAU:
		return "croc-sync parser let an absurd yaw through unbounded: %f" % wrapped

	# One entry too many. Built at the cap + 1 so the check pins the BOUNDARY, not
	# merely "some big number is refused".
	var over_ids := PackedInt32Array()
	var over_xf := PackedFloat32Array()
	var over_flags := PackedByteArray()
	for i: int in range(MpCodec.MAX_CROC_SYNC + 1):
		over_ids.append(i)
		over_flags.append(0)
		over_xf.append_array(PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))

	# Each of these must be dropped WHOLE.
	var bad: Array = [
		["empty payload", {}],
		["missing i", {
			"x": PackedFloat32Array([0.0, 0.0, 0.0, 0.0]), "f": PackedByteArray([0])
		}],
		["missing x", {"i": PackedInt32Array([1]), "f": PackedByteArray([0])}],
		["missing f", {
			"i": PackedInt32Array([1]), "x": PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
		}],
		# A plain Array indexes just fine and would then hand a String to
		# `global_position` — the exact type confusion the EXACT packed-type test
		# in the parser exists to stop.
		["i as a plain Array", {
			"i": [1], "x": PackedFloat32Array([0.0, 0.0, 0.0, 0.0]),
			"f": PackedByteArray([0])
		}],
		["x as a plain Array", {
			"i": PackedInt32Array([1]), "x": [0.0, 0.0, 0.0, 0.0],
			"f": PackedByteArray([0])
		}],
		["f as a plain Array", {
			"i": PackedInt32Array([1]), "x": PackedFloat32Array([0.0, 0.0, 0.0, 0.0]),
			"f": [0]
		}],
		# The three arrays describe the SAME entries, so a size mismatch is a
		# truncated or hostile packet and walking it reads off the end of one.
		["f shorter than i", {
			"i": PackedInt32Array([1, 2]),
			"x": PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
			"f": PackedByteArray([0])
		}],
		["x not 4 per entry", {
			"i": PackedInt32Array([1]), "x": PackedFloat32Array([0.0, 0.0, 0.0]),
			"f": PackedByteArray([0])
		}],
		["more entries than MAX_CROC_SYNC", {
			"i": over_ids, "x": over_xf, "f": over_flags
		}],
		["NaN coordinate", {
			"i": PackedInt32Array([1]), "x": PackedFloat32Array([NAN, 0.0, 0.0, 0.0]),
			"f": PackedByteArray([0])
		}],
		["INF coordinate", {
			"i": PackedInt32Array([1]), "x": PackedFloat32Array([0.0, INF, 0.0, 0.0]),
			"f": PackedByteArray([0])
		}],
		# Finite but absurd: a crocodile stands in the same world a player does,
		# so it takes the presence packet's coordinate bound.
		["coordinate past MAX_PRESENCE_COORD", {
			"i": PackedInt32Array([1]),
			"x": PackedFloat32Array([
				0.0, 0.0, MpCodec.MAX_PRESENCE_COORD * 10.0, 0.0
			]),
			"f": PackedByteArray([0])
		}],
		["NaN yaw", {
			"i": PackedInt32Array([1]), "x": PackedFloat32Array([0.0, 0.0, 0.0, NAN]),
			"f": PackedByteArray([0])
		}],
	]
	for case in bad:
		var result: Dictionary = MpCodec.decode_croc_sync(case[1])
		if not result.is_empty():
			return "croc-sync parser accepted a bad packet (%s): %s" % [case[0], result]
	Sentinel.done("croc_sync_parser")
	return ""


# =============================================================================
# 12. ROOM COIN MULTIPLIER
# =============================================================================

func _check_room_multiplier() -> String:
	"""
	The master prices EVERY claim in the room with this, so a drift from the
	player's own `get_streak_multiplier()` pays every coin in the room at the
	wrong rate. Pinned against the player's constants, not against a copy of the
	expression.
	"""
	var step: int = Player.STREAK_COINS_PER_STEP
	var bonus: int = Player.STREAK_MAX_BONUS

	var cases: Array = [
		# [streak, expected, what it pins]
		[0, 1, "no streak is x1"],
		[step - 1, 1, "the step is a floor, not a rounding"],
		[step, 2, "one step of STREAK_COINS_PER_STEP is +1"],
		[step * bonus, 1 + bonus, "the cap is 1 + STREAK_MAX_BONUS"],
		[step * (bonus + 99), 1 + bonus, "past the cap stays at the cap"],
	]
	for case in cases:
		var got: int = MPManager.room_multiplier_from(case[0], step, bonus)
		if got != case[1]:
			return "room_multiplier_from(%d) == %d, expected %d — %s" % [
				case[0], got, case[1], case[2]
			]

	# A zero step size would be a division by zero on the master's hot path.
	if MPManager.room_multiplier_from(50, 0, bonus) != 1:
		return "room_multiplier_from did not guard a zero step size"
	Sentinel.done("room_multiplier")
	return ""


func _check_captive_parser() -> String:
	"""
	The `cap` parser against hostile packets — the fifth trust boundary.

	THE HONEST PACKETS ARE TESTED FIRST AND THEY ARE THE POINT: a parser that
	returns `{}` for everything passes every rejection below, so the acceptances
	are what stop this check being vacuous.
	"""
	var good: Dictionary = MpCodec.decode_captive({"t": "cap", "h": "primm", "c": true})
	if good.get("h", "") != "primm" or good.get("c", null) != true:
		return "decode_captive dropped an honest capture (%s)" % str(good)
	var release: Dictionary = MpCodec.decode_captive({"t": "cap", "h": "teibi", "c": false})
	if release.get("h", "") != "teibi" or release.get("c", null) != false:
		return "decode_captive dropped an honest release (%s)" % str(release)

	# ...and everything a peer that is not speaking this protocol could send. `c`
	# has to be a real BOOL and not a truthy number, because the mesh carries real
	# types (`var_to_bytes`) and a number there is a peer this build cannot read.
	var hostile: Array[Dictionary] = [
		{"t": "cap", "c": true},                                   # no hero at all
		{"t": "cap", "h": 7, "c": true},                            # hero is a number
		{"t": "cap", "h": "", "c": true},                           # hero is empty
		{"t": "cap", "h": "x".repeat(MpCodec.MAX_HERO_NAME + 1), "c": true},
		{"t": "cap", "h": "primm"},                                 # no direction
		{"t": "cap", "h": "primm", "c": 1},                         # direction is a number
		{"t": "cap", "h": "primm", "c": "true"},                    # ...or a string
		{"t": "cap", "h": ["primm"], "c": true},                    # hero is an array
	]
	for packet: Dictionary in hostile:
		if not MpCodec.decode_captive(packet).is_empty():
			return "decode_captive accepted the hostile packet %s" % str(packet)
	Sentinel.done("captive_parser")
	return ""


func _check_pad_parser() -> String:
	"""
	The `pad` verb's two pure halves — the SIXTH trust boundary (bead
	godot-test1-3iy.22).

	The verb carries a storey and a plate index and NO POSITION, so the whole of
	its safety is these two functions plus the plan lookup between them: is that a
	plate the building draws, and was the sender standing on it. The honest cases
	are asserted first, or a parser that dropped everything would pass every
	rejection below.
	"""
	var good: Dictionary = MpCodec.decode_pad({"t": "pad", "f": 3, "p": 1})
	if int(good.get("f", -1)) != 3 or int(good.get("p", -1)) != 1:
		return "decode_pad dropped an honest press (%s)" % str(good)
	if MpCodec.decode_pad({"t": "pad", "f": 0, "p": 0}).is_empty():
		return "decode_pad dropped storey 0 pad 0 — the keep's own plate"

	# `var_to_bytes` round-trips real types, so a float or a numeric string in
	# either field is a peer that is not speaking this protocol.
	var hostile: Array[Dictionary] = [
		{"t": "pad", "p": 1},                       # no storey
		{"t": "pad", "f": 3},                       # no plate
		{"t": "pad", "f": 3.0, "p": 1},             # storey is a float
		{"t": "pad", "f": 3, "p": "1"},             # plate is a string
		{"t": "pad", "f": -1, "p": 1},              # negative storey
		{"t": "pad", "f": 3, "p": -2},              # negative plate
		{"t": "pad", "f": [3], "p": 1},             # storey is an array
		{"t": "pad", "f": true, "p": 1},            # ...or a bool
	]
	for packet: Dictionary in hostile:
		if not MpCodec.decode_pad(packet).is_empty():
			return "decode_pad accepted the hostile packet %s" % str(packet)

	# ...and the second half: a press is only a press if the sender was there. The
	# plate is a 1.94 m cell and a storey is ~78 m across, so "somewhere on the
	# floor" must NOT pass — that is the whole attack this half exists to stop.
	var plate := Vector3(120.0, 40.0, -8.0)
	if not MpCodec.pad_press_in_reach(plate + Vector3(1.0, 0.0, 1.0), plate):
		return "pad_press_in_reach refused a peer standing on the plate"
	if MpCodec.pad_press_in_reach(plate + Vector3(0.0, 0.0, 40.0), plate):
		return "pad_press_in_reach accepted a peer 40 m from the plate — a modified"\
				+ " client could divert any guard in the building from anywhere"
	if MpCodec.pad_press_in_reach(plate, Vector3.INF):
		return "pad_press_in_reach accepted a plate no plan draws (Vector3.INF is"\
				+ " pad_world's refusal, and it must not read as a distance)"
	if MpCodec.pad_press_in_reach(Vector3(NAN, 0.0, 0.0), plate):
		return "pad_press_in_reach accepted a NaN sender position"
	Sentinel.done("pad_parser")
	return ""


func _check_gate_parser() -> String:
	"""
	The `gate` verb — bead godot-test1-d81 — against hostile packets.

	THE HONEST PACKET COMES FIRST AND IT IS THE POINT: a parser that returned
	`{}` for everything would pass every rejection below while leaving the
	room's doorways stone on every screen but the opener's.
	"""
	var honest: Dictionary = {"t": "gate", "id": TowerGraph.GATE_DEMAND}
	var good: Dictionary = MpCodec.decode_gate(honest)
	if good.is_empty() or str(good["id"]) != TowerGraph.GATE_DEMAND:
		return "decode_gate dropped an honest opening (%s)" % str(good)

	# An honest round-trip THROUGH BYTES: what the opener publishes must survive
	# the codec, or the room replays an opening nobody made.
	var trip: Dictionary = MpCodec.decode_gate(bytes_to_var(var_to_bytes(honest)))
	if trip.is_empty() or str(trip) != str(good):
		return "decode_gate did not round-trip an honest opening (%s)" % str(trip)

	# The range list accepts what the graph declares: every id the opened set
	# may ever hold must cross this parser, or a build that authors a gate
	# breaks every older room instead of opening it.
	for gid: String in TowerGraph.opened_ids():
		if gid.length() > MpCodec.MAX_GATE_ID:
			return "declared gate id '%s' outgrows MAX_GATE_ID — the room would drop it" % gid
		if MpCodec.decode_gate({"t": "gate", "id": gid}).is_empty():
			return "decode_gate dropped the declared id '%s'" % gid

	# ...and everything a peer that is not speaking this protocol could send.
	var hostile: Array[Dictionary] = [
		{"t": "gate"},
		{"t": "gate", "id": 7},
		{"t": "gate", "id": 7.5},
		{"t": "gate", "id": true},
		{"t": "gate", "id": ""},
		{"t": "gate", "id": "tower_monthly_special"},
		{"t": "gate", "id": Vector2(1.0, 2.0)},
		{"t": "gate", "id": "x".repeat(MpCodec.MAX_GATE_ID + 1)},
	]
	for packet: Dictionary in hostile:
		if not MpCodec.decode_gate(packet).is_empty():
			return "decode_gate accepted the hostile packet %s" % str(packet)

	# The verb has to be budgeted like every other one `_receive_mesh_verb`
	# dispatches — a monotone set is not a rate bound.
	if not MPManager.VERB_BUDGET_PER_SEC.has("gate"):
		return "the gate verb has no VERB_BUDGET_PER_SEC row"
	Sentinel.done("gate_parser")
	return ""


# =============================================================================
# 24. THE ABILITY STATE A WATCHER SEES (bead godot-test1-69p)
# =============================================================================

func _check_ability_visual_state() -> String:
	"""
	Teibi's Resize and Windman's Air Rush ride the presence packet as `ab`, one
	byte of `player_controller.ABILITY_BIT_*` flags, and RemoteAvatar draws them.
	Validated exactly like every other relayed number — and ABSENT MUST READ AS
	NORMAL, or a peer on an older build turns invisible instead of merely
	normal-sized.
	"""
	var base: Dictionary = {
		"p": Vector3.ZERO, "y": 0.0, "c": 0, "s": 0.0, "g": true,
	}

	# Absent: a peer that never sends the field draws the plain pose.
	var legacy: Dictionary = MpCodec.decode_presence(var_to_bytes(base))
	if legacy.is_empty() or int(legacy["ab"]) != 0:
		return "a presence packet without `ab` did not read as no ability: %s" % legacy

	# Present and honest: the bits survive the wire intact.
	var giant: Dictionary = base.duplicate()
	giant["ab"] = Player.ABILITY_BIT_GIANT | Player.ABILITY_BIT_FLYING
	var flown: Dictionary = MpCodec.decode_presence(var_to_bytes(giant))
	if flown.is_empty() or int(flown["ab"]) != int(giant["ab"]):
		return "the ability bits did not survive the packet: %s" % flown

	# Present and hostile: dropped WHOLE, like every other bad field.
	for bad: Variant in ["giant", -1, 300, NAN, INF]:
		var poison: Dictionary = base.duplicate()
		poison["ab"] = bad
		if not MpCodec.decode_presence(var_to_bytes(poison)).is_empty():
			return "the parser accepted a malformed ability field: %s" % str(bad)

	# The SCALE a watcher draws is the player's own constant, not a second copy,
	# and it is total: unknown bits draw normal, contradictory bits draw giant.
	var scales: Array = [
		[0, 1.0, "no bits is normal size"],
		[Player.ABILITY_BIT_FLYING, 1.0, "flying alone does not resize anybody"],
		[Player.ABILITY_BIT_SMALL, Player.TEIBI_SCALE_SMALL, "the small form"],
		[Player.ABILITY_BIT_GIANT, Player.TEIBI_SCALE_BIG, "the giant form"],
		[Player.ABILITY_BIT_SMALL | Player.ABILITY_BIT_GIANT, Player.TEIBI_SCALE_BIG,
			"both size bits at once resolve to giant, not to something undefined"],
		[1 << 7, 1.0, "a bit this build has never heard of draws normal"],
	]
	for case in scales:
		var got: float = Player.ability_visual_scale(case[0])
		if not is_equal_approx(got, case[1]):
			return "ability_visual_scale(%d) == %f, expected %f — %s" % [
				case[0], got, case[1], case[2]
			]

	# ...and the avatar actually WEARS it. A live RemoteAvatar, fed one presence
	# sample the way the drain feeds it, must scale its model and NOTHING ELSE:
	# the isolation contract says an avatar has no body, so there is nothing else
	# to scale, and the isolation contract (`_check_avatar_isolation`, check 1 in `scripts/mp_selfcheck.gd`) is what keeps it that way.
	var avatar: RemoteAvatar = RemoteAvatar.new()
	root.add_child(avatar)
	avatar.setup("watcher")
	avatar.receive_state(Vector3.ZERO, 0.0, 0, 0.0, true, Player.ABILITY_BIT_GIANT)
	if avatar.ability_bits != Player.ABILITY_BIT_GIANT:
		avatar.free()
		return "the avatar did not store the ability bits it was handed"
	# Eased, not snapped, so one long step lands on the target rather than near it.
	avatar._tick_ability_scale(10.0)
	var worn: float = avatar.model_root.scale.x
	avatar.free()
	if not is_equal_approx(worn, Player.TEIBI_SCALE_BIG):
		return "the avatar settled at scale %f, expected the giant %f" % [
			worn, Player.TEIBI_SCALE_BIG
		]
	Sentinel.done("ability_visual_state")
	return ""
