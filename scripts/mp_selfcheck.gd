extends SceneTree
## The one runnable check for the multiplayer layer. Run it headless:
##
##     godot --headless --path . --script res://scripts/mp_selfcheck.gd
##
## Prints "SELFCHECK OK" and quits 0, or prints the first failure and quits 1.
##
## Everything here is an explicit `if` rather than an `assert` on purpose:
## asserts are stripped from release builds, and this file's whole value is that
## it keeps working when somebody runs it a year from now against a release
## export. It touches no network and no WebRTC — only the pure parts, plus two
## scenes instanced into a throwaway node (the avatar's model and one coin),
## because two of the contracts below live in `_ready()` and cannot be checked
## without one.
##
## What it guards, and why each one is worth a check:
##
##   1. The RemoteAvatar ISOLATION CONTRACT — no groups, no CollisionObject3D
##      anywhere in the subtree. This is the one that fails loudly instead of
##      turning into "why are the crocodiles chasing a hologram?".
##   2. The presence packet parser against hostile bytes — the trust boundary.
##   3. Forced seeds — the same seed must give the same biome field, or two
##      peers in one room walk different worlds.
##   4. The peer-id derivation — stable, ≥ 2, and collision-free over samples.
##   5. Coin identity — the id is a pure function of position, so two peers
##      sharing a seed name the same coin the same thing; AND a live coin latches
##      that id at spawn, so its bob (nearly a whole id cell) cannot rename it.
##   6. The join-snapshot parser against hostile payloads — the third trust
##      boundary, and the one that feeds the joiner's placement.
##   7. Backward compatibility: a phase-3 presence packet (no shared totals)
##      must still decode, or an older peer goes invisible instead of uncounted.
##   8. The shared-lives arithmetic — the room's hearts, off by one is a death.
##   9. Hero name → CHARACTERS index, the lookup the hero split rides on.
##  10. The crocodile-sync parser against hostile packets — the fourth trust
##      boundary, and the one that drives every crocodile in the room.
##  11. Crocodile identity — the id is a pure function of the node name, which
##      the terrain derives deterministically, so two peers name the same
##      crocodile the same thing; AND a live croc latches it in _ready().
##  12. The room's coin multiplier arithmetic, pinned against the player's own
##      streak constants — the master prices every claim with it.
##  13. The group anchor rule — where a mid-run joiner lands AND where a death
##      inside a room respawns. A spread group must never anchor on the empty
##      midpoint, INCLUDING for a dying master, which is never in the map.
##  14. The two join-snapshot WORLD SWEEPS, measured as effects on real nodes
##      with a negative control each: the kill list must squash the crocodile it
##      names and no other, and the collected set must spend the chest it names
##      and no other. Both bugs look like nothing on a headless machine and need
##      two browsers plus a giant Teibi to reproduce by hand.
##  15. The jump hatch for REMOTE members — a teammate who is off the ground must
##      not be offered as a crocodile's quarry, and one jumper must not veto the
##      scent of the grounded teammate beside them.
##  16. The room's HEARTS as the master's own state, pinned against the stateless
##      formula it replaces: a grant that lands at LIVES_CAP is burnt, a death is
##      charged once, and a master migration carries the count over.
##  17. The claim's BASE VALUE, which is what a room's pickups credit to
##      meta-progression — non-zero, distinct from the multiplied award, and
##      UNFORGEABLE: derived from the winner's own pending claim rather than from
##      the confirm, so a hostile master cannot mint persisted progression.
##  18. Terrain FOCUS POINTS — the chunks that stay loaded around a far teammate,
##      so the master has crocodiles there to simulate at all. Measured in metres
##      against SIM_RADIUS, with the memory cap and the release both pinned.

const MPManager: GDScript = preload("res://scripts/mp_manager.gd")
const Terrain: GDScript = preload("res://scripts/endless_terrain.gd")
const Coin: GDScript = preload("res://scripts/coin.gd")
const Player: GDScript = preload("res://scripts/player_controller.gd")
const CrocAI: GDScript = preload("res://scripts/piglet_crocodile_ai.gd")


func _initialize() -> void:
	# WAIT ONE FRAME FIRST. At `_initialize` the SceneTree's own root is not yet
	# inside the tree, so a node added to it never gets `_ready()` and reports a
	# zero `global_transform` — which would make the live-coin check below pass
	# vacuously against a coin that was never actually spawned.
	await process_frame
	var failure: String = _run_checks()
	if failure.is_empty():
		print("SELFCHECK OK")
		quit(0)
	else:
		printerr("SELFCHECK FAILED: " + failure)
		quit(1)


func _run_checks() -> String:
	"""Run every check in order. Returns "" on success, else the first failure."""
	var failure: String = _check_avatar_isolation()
	if not failure.is_empty():
		return failure
	failure = _check_presence_parser()
	if not failure.is_empty():
		return failure
	failure = _check_forced_seed()
	if not failure.is_empty():
		return failure
	failure = _check_peer_ids()
	if not failure.is_empty():
		return failure
	failure = _check_coin_ids()
	if not failure.is_empty():
		return failure
	failure = _check_state_parser()
	if not failure.is_empty():
		return failure
	failure = _check_presence_backcompat()
	if not failure.is_empty():
		return failure
	failure = _check_shared_lives()
	if not failure.is_empty():
		return failure
	failure = _check_hero_index()
	if not failure.is_empty():
		return failure
	failure = _check_croc_sync_parser()
	if not failure.is_empty():
		return failure
	failure = _check_croc_ids()
	if not failure.is_empty():
		return failure
	failure = _check_room_multiplier()
	if not failure.is_empty():
		return failure
	failure = _check_group_anchor()
	if not failure.is_empty():
		return failure
	failure = _check_join_world_sweeps()
	if not failure.is_empty():
		return failure
	failure = _check_remote_scent()
	if not failure.is_empty():
		return failure
	failure = _check_room_lives_ordering()
	if not failure.is_empty():
		return failure
	failure = _check_claim_base_value()
	if not failure.is_empty():
		return failure
	failure = _check_terrain_focus_points()
	if not failure.is_empty():
		return failure
	failure = _check_hunter_sync()
	if not failure.is_empty():
		return failure
	return _check_acquisition_cue()


# =============================================================================
# 1. ISOLATION CONTRACT
# =============================================================================

func _check_avatar_isolation() -> String:
	# EVERY playable character, not just CHARACTERS[0]. The contract is that no
	# remote model joins a group or carries a CollisionObject3D, and an Area3D
	# added to primm/teibi/phoboman is exactly the regression this exists to catch
	# — walking one scene would let three of the four through.
	#
	# A FRESH AVATAR PER INDEX is load-bearing: `set_character` silently drops a
	# swap inside SWAP_COOLDOWN_MS (500 ms), so successive calls on one avatar
	# would all keep the first model and three quarters of the loop would re-walk
	# the same scene.
	for index: int in Player.CHARACTERS.size():
		var avatar := RemoteAvatar.new()
		avatar.setup("selfcheck-peer")
		avatar.set_character(index)

		# `set_character` has four SILENT early-return paths (bad index, same index,
		# the swap cooldown, a load() that returned null). Any of them would leave an
		# empty subtree here and the walk below would pass by covering nothing —
		# a green run that guards precisely zero of the contract. Assert it loaded.
		if avatar.character_node == null:
			avatar.free()
			return "set_character(%d) instanced no model — the isolation walk would be vacuous" % index

		var failure: String = _walk_isolation(avatar, avatar)
		avatar.free()
		if not failure.is_empty():
			return "%s (character %d)" % [failure, index]
	return ""


func _walk_isolation(node: Node, root: Node) -> String:
	"""Depth-first: nothing in the subtree may be grouped or physical."""
	if not node.get_groups().is_empty():
		return "%s joins groups %s — a RemoteAvatar subtree must join none" % [
			root.get_path_to(node), node.get_groups()
		]
	if node is CollisionObject3D:
		return "%s is a CollisionObject3D — a RemoteAvatar carries no collision" % \
			root.get_path_to(node)
	for child in node.get_children():
		var failure: String = _walk_isolation(child, root)
		if not failure.is_empty():
			return failure
	return ""


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
	var decoded: Dictionary = MPManager.decode_presence(var_to_bytes(good))
	if decoded.is_empty():
		return "parser rejected a well-formed packet"
	if decoded["p"] != good["p"] or decoded["c"] != 0 or decoded["g"] != true:
		return "parser mangled a well-formed packet: %s" % decoded

	# A finite but absurd yaw must come out BOUNDED, not merely accepted: it is
	# assigned straight to RemoteAvatar.rotation.y, and lerp_angle's `from +
	# short_way * weight` leaves 1e30 at 1e30 forever.
	var wild: Dictionary = MPManager.decode_presence(var_to_bytes({
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
		var result: Dictionary = MPManager.decode_presence(case[1])
		if not result.is_empty():
			return "parser accepted a bad packet (%s): %s" % [case[0], result]
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
		var value: int = MPManager.peer_int_id(id)
		if value < 2:
			return "peer_int_id(%s) == %d — must clear the reserved 0 and 1" % [id, value]
		if seen.has(value):
			return "peer_int_id collision: %s and %s both give %d" % [seen[value], id, value]
		seen[value] = id
	return ""


# =============================================================================
# 5. COIN IDENTITY
# =============================================================================

func _check_coin_ids() -> String:
	"""
	`Coin.id_at()` is the whole coin-identity scheme: no id is ever transmitted
	with a coin, so a joiner despawning what an incumbent already banked works
	ONLY if the same position gives the same id on both peers.

	The positions below sit mid-cell on purpose (x * COIN_ID_QUANT lands on a
	whole number), because a coin exactly on a cell boundary is the scheme's
	documented second ceiling — it may round either way — and pinning that here
	would be pinning the ceiling rather than the contract.
	"""
	var here := Vector3(1.0, 0.5, 2.0)
	var id: int = Coin.id_at(here)

	if Coin.id_at(here) != id:
		return "Coin.id_at is not stable for the same position"

	# A metre away is eight cells away — a different coin, and it must say so.
	if Coin.id_at(here + Vector3(1.0, 0.0, 0.0)) == id:
		return "Coin.id_at collided across a metre in x"
	if Coin.id_at(here + Vector3(0.0, 0.0, 1.0)) == id:
		return "Coin.id_at collided across a metre in z"

	# The same coin, jittered by less than a millimetre: sub-cell motion must NOT
	# rename it.
	for jitter in [Vector3(0.0004, -0.0004, 0.0004), Vector3(-0.0009, 0.0009, -0.0009)]:
		if Coin.id_at(here + jitter) != id:
			return "Coin.id_at renamed a coin over a %s jitter" % jitter

	# THE BOB IS NOT SUB-CELL, and that is why a live coin must LATCH its id at
	# spawn instead of recomputing it from global_position. `_process` swings the
	# coin BOB_AMOUNT (0.12 m) about base_y — ±0.96 of a 12.5 cm cell — so an id
	# read at collection time would name a different cell than the one read at
	# spawn: the joiner asks `is_coin_collected()` about one id and the collector
	# publishes another, and the replay misses on most pickups. Check the real
	# node, not the pure function: the pure function is SUPPOSED to differ here.
	if Coin.id_at(here) == Coin.id_at(here + Vector3(0.0, Coin.BOB_AMOUNT, 0.0)):
		return "the bob no longer crosses an id cell — this check has stopped guarding anything"
	var coin: Node3D = load("res://scenes/collectibles/coin.tscn").instantiate()
	coin.position = here
	root.add_child(coin)
	var spawn_id: int = coin.coin_id()
	coin.position.y = here.y + Coin.BOB_AMOUNT  # what _process does every frame
	var bobbed_id: int = coin.coin_id()
	coin.free()
	if bobbed_id != spawn_id:
		return "a bobbing coin renamed itself (%d -> %d) — coin_id must be latched at spawn" % [
			spawn_id, bobbed_id
		]
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
	"""
	var good := {
		"cc": 42.0, "ls": 2.0, "dd": 1337.0,
		"px": 10.0, "py": 2.0, "pz": -5.0,
		"ids": [111.0, 222.0, -333.0],
	}
	var snapshot: Dictionary = MPManager.decode_state(good)
	if snapshot.is_empty():
		return "state parser rejected a well-formed snapshot"
	if snapshot["cc"] != 42 or snapshot["ls"] != 2 or snapshot["dd"] != 1337:
		return "state parser mangled the counters: %s" % snapshot
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
	var with_dead: Dictionary = MPManager.decode_state({
		"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
		"ids": [], "dead": [7.0, -8.0],
	})
	if with_dead.is_empty() or with_dead["dead"] != [7, -8]:
		return "state parser mangled the kill list: %s" % with_dead
	# `gc`/`gs` (the room's frozen departed-member totals) follow the presence
	# counters' rule: MISSING IS NOT MALFORMED. `good` above carries neither, so
	# an older peer's snapshot still lands, reading as zero.
	if snapshot["gc"] != 0 or snapshot["gs"] != 0:
		return "state parser invented departed-member totals: %s" % snapshot
	var with_gone: Dictionary = MPManager.decode_state({
		"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
		"gc": 500.0, "gs": 3.0, "ids": [],
	})
	if with_gone.is_empty() or with_gone["gc"] != 500 or with_gone["gs"] != 3:
		return "state parser mangled the departed-member totals: %s" % with_gone

	# An over-long list is TRUNCATED, not rejected — the ids are sent
	# most-recent-first, so the head is the part nearest the joiner, and the
	# counters and position are still worth having.
	var long_ids: Array = []
	for i: int in range(MPManager.MAX_STATE_IDS + 64):
		long_ids.append(float(i))
	var truncated: Dictionary = MPManager.decode_state({
		"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
		"ids": long_ids,
	})
	if truncated.is_empty():
		return "state parser dropped an over-long snapshot instead of truncating it"
	if (truncated["ids"] as Array).size() != MPManager.MAX_STATE_IDS:
		return "state parser truncated to %d ids, expected %d" % [
			(truncated["ids"] as Array).size(), MPManager.MAX_STATE_IDS
		]
	# The kill list is bounded by the SAME cap at the SAME end, or a hostile peer
	# buys an unbounded `_dead_crocs` write with one snapshot.
	var long_dead: Dictionary = MPManager.decode_state({
		"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
		"ids": [], "dead": long_ids,
	})
	if long_dead.is_empty():
		return "state parser dropped an over-long kill list instead of truncating it"
	if (long_dead["dead"] as Array).size() != MPManager.MAX_STATE_IDS:
		return "state parser truncated the kill list to %d ids, expected %d" % [
			(long_dead["dead"] as Array).size(), MPManager.MAX_STATE_IDS
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
		# Absent gc/gs is fine (above); PRESENT AND BAD still drops the payload,
		# like every other field here.
		["gc as String", {
			"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
			"gc": "loads", "ids": []
		}],
		["negative gs", {
			"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0,
			"gs": -1.0, "ids": []
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
		var result: Dictionary = MPManager.decode_state(case[1])
		if not result.is_empty():
			return "state parser accepted a bad snapshot (%s): %s" % [case[0], result]
	return ""


# =============================================================================
# 7. PRESENCE BACKWARD COMPATIBILITY
# =============================================================================

func _check_presence_backcompat() -> String:
	"""
	A phase-3 peer sends a presence packet with no `cc`/`lv`/`dd`. Dropping those
	whole would make that peer INVISIBLE rather than merely uncounted, so absent
	must read as 0 — only a field that is present and bad may drop the packet.
	"""
	var legacy: Dictionary = MPManager.decode_presence(var_to_bytes({
		"p": Vector3(3.0, 1.0, 4.0), "y": 0.25, "c": 1, "s": 2.0, "g": false
	}))
	if legacy.is_empty():
		return "parser rejected a phase-3 shaped packet (no shared totals)"
	if legacy["cc"] != 0 or legacy["lv"] != 0 or legacy["dd"] != 0:
		return "a phase-3 packet did not read as zero contributions: %s" % legacy

	# Present-and-bad still drops the packet whole.
	var poisoned: Dictionary = MPManager.decode_presence(var_to_bytes({
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
	if MPManager.packet_kind(later_build) != "zzz_a_verb_from_a_later_build":
		return "a packet carrying an unknown verb did not read as that verb"
	var phase4: Dictionary = {"p": Vector3.ZERO, "y": 0.0, "c": 0, "s": 0.0, "g": true}
	if MPManager.packet_kind(phase4) != "":
		return "a phase-3/4 packet with no \"t\" did not read as presence"
	return ""


# =============================================================================
# 8. SHARED LIVES ARITHMETIC
# =============================================================================

func _check_shared_lives() -> String:
	"""The room's hearts. Off by one here is a death that should not have been."""
	var base: int = Player.MAX_LIVES
	var per: int = Player.EXTRA_LIFE_COINS
	var cap: int = Player.LIVES_CAP

	var cases: Array = [
		# [bank, spent, expected, what it pins]
		[0, 0, base, "a fresh room starts on MAX_LIVES"],
		[per, 0, base + 1, "one extra life per EXTRA_LIFE_COINS banked"],
		[per * 2 - 1, 1, base, "integer division floors: 149 banked is +1, not +2"],
		[0, base, 0, "spending every heart lands on 0"],
		[0, base + 99, 0, "over-spending clamps to 0, never negative"],
		[per * 99, 0, cap, "the bank cannot push past LIVES_CAP"],
	]
	for case in cases:
		var got: int = MPManager.shared_lives_from(case[0], case[1], base, per, cap)
		if got != case[2]:
			return "shared_lives_from(%d, %d) == %d, expected %d — %s" % [
				case[0], case[1], got, case[2], case[3]
			]
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
		"f": PackedByteArray([MPManager.CROC_FLAG_CHASING, 0]),
	}
	var sync: Dictionary = MPManager.decode_croc_sync(good)
	if sync.is_empty():
		return "croc-sync parser rejected a well-formed packet"
	var ids: PackedInt32Array = sync["ids"]
	var xf: PackedFloat32Array = sync["xf"]
	var flags: PackedByteArray = sync["flags"]
	if ids.size() != 2 or flags.size() != 2 or xf.size() != 8:
		return "croc-sync parser mangled the entry counts: %d/%d/%d" % [
			ids.size(), xf.size(), flags.size()
		]
	if ids[1] != 22 or flags[0] != MPManager.CROC_FLAG_CHASING \
			or not is_equal_approx(xf[4], -3.0):
		return "croc-sync parser mangled a well-formed packet: %s" % sync

	# An absurd yaw comes back WRAPPED, not dropped — the same normalise-rather-
	# than-refuse rule `decode_presence` applies to `y`, and for the same reason:
	# the receiver eases it with lerp_angle, which is `from + short_way * weight`,
	# and `1e30 + anything small IS 1e30`.
	var wild: Dictionary = MPManager.decode_croc_sync({
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
	for i: int in range(MPManager.MAX_CROC_SYNC + 1):
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
				0.0, 0.0, MPManager.MAX_PRESENCE_COORD * 10.0, 0.0
			]),
			"f": PackedByteArray([0])
		}],
		["NaN yaw", {
			"i": PackedInt32Array([1]), "x": PackedFloat32Array([0.0, 0.0, 0.0, NAN]),
			"f": PackedByteArray([0])
		}],
	]
	for case in bad:
		var result: Dictionary = MPManager.decode_croc_sync(case[1])
		if not result.is_empty():
			return "croc-sync parser accepted a bad packet (%s): %s" % [case[0], result]
	return ""


# =============================================================================
# 11. CROCODILE IDENTITY
# =============================================================================

func _check_croc_ids() -> String:
	"""
	`croc_id_for()` is the whole crocodile-identity scheme, and it is the coin's
	argument one level up: no id is ever transmitted with a crocodile, so the
	master driving a peer's crocodile works ONLY if the terrain's deterministic
	node name names the same animal on both. Two crocodiles that differ by their
	index — or by their spawner's prefix — must not collide, or the master's
	sync drives the wrong body.
	"""
	var name_a: String = "Crocodile_3_-4_2"
	var id: int = CrocAI.croc_id_for(name_a)
	if CrocAI.croc_id_for(name_a) != id:
		return "croc_id_for is not stable for the same name"
	if CrocAI.croc_id_for("Crocodile_3_-4_3") == id:
		return "croc_id_for collided across the spawn index"
	if CrocAI.croc_id_for("PatrolCrocodile_3_-4_2") == id:
		return "croc_id_for collided across the spawner prefix"

	# EVERY id MUST SURVIVE THE WIRE. The sync packet carries ids in a
	# PackedInt32Array, so an id above INT32_MAX wraps negative in transit, misses
	# the receiver's `_synced_crocs` lookup and is dropped on the deliberately
	# SILENT "not my chunk" path — which is why the stability and distinctness
	# checks above passed while 43% of the pack was never synced at all. Sweep the
	# real name scheme rather than one hand-picked name: the failure is a property
	# of the hash's range, so a single example only pins whichever half it landed in.
	var wire: PackedInt32Array = PackedInt32Array()
	for cx: int in range(-6, 7):
		for i: int in range(10):
			var probe: String = "Crocodile_%d_%d_%d" % [cx, cx * 3 - 1, i]
			var probe_id: int = CrocAI.croc_id_for(probe)
			wire.clear()
			wire.append(probe_id)
			if wire[0] != probe_id:
				return "croc_id_for(%s) == %d does not survive PackedInt32Array (%d)" % [
					probe, probe_id, wire[0]
				]

	# The live node LATCHES it in _ready(), so nothing that touches the node later
	# can quietly rename this crocodile mid-run — check the real thing, because
	# the pure function passing says nothing about where the node reads its name.
	var croc: Node = load("res://scenes/characters/piglet_crocodile.tscn").instantiate()
	croc.name = name_a
	root.add_child(croc)
	var live_id: int = croc.croc_id()
	croc.free()
	if live_id != id:
		return "a live crocodile's croc_id() (%d) does not match croc_id_for(%s) (%d)" % [
			live_id, name_a, id
		]
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
	return ""


# =============================================================================
# 13. GROUP ANCHOR (where a joiner arrives, and where a death respawns)
# =============================================================================

func _check_group_anchor() -> String:
	"""
	`_anchor_of()` decides where a mid-run joiner lands (`_join_anchor()`) AND
	where a player who dies inside a room comes back (`group_anchor()`), so a
	wrong answer here teleports somebody into empty ground with nothing to see
	and no error anywhere — the class of failure a headless run cannot eyeball.

	The third case is the one that bites and the reason this check exists:
	`_peer_state` holds only OTHER members, so a DYING MASTER is never in the
	map it hands over. If the spread branch fell back to the centroid for a
	missing master, that master would respawn onto the empty midpoint between two
	teammates who went opposite ways — precisely the outcome the whole spread
	branch exists to avoid.
	"""
	var spread: float = MPManager.GROUP_SPREAD_MAX
	var a := Vector3(0.0, 2.0, 0.0)
	var b := Vector3(10.0, 2.0, 0.0)
	var far := Vector3(spread * 4.0, 2.0, 0.0)

	# Tight group: the plain centroid, master or no master.
	var tight: Vector3 = MPManager._anchor_of({"m": a, "p": b}, "m")
	if tight.distance_to((a + b) * 0.5) > 0.01:
		return "_anchor_of on a tight group answered %s, expected the centroid %s" % [
			str(tight), str((a + b) * 0.5)
		]

	# Spread group WITH the master in the map: the master, not the midpoint.
	var with_master: Vector3 = MPManager._anchor_of({"m": a, "p": far}, "m")
	if with_master.distance_to(a) > 0.01:
		return "_anchor_of on a spread group answered %s, expected the master at %s" % [
			str(with_master), str(a)
		]

	# Spread group WITHOUT the master (a dying master anchoring on its peers):
	# some real peer, never the empty midpoint between them.
	var no_master: Vector3 = MPManager._anchor_of({"p": a, "q": far}, "m")
	var midpoint: Vector3 = (a + far) * 0.5
	if no_master.distance_to(midpoint) < 0.01:
		return ("_anchor_of fell back to the centroid %s for a master absent from the map "
			+ "— a dying master would respawn on empty ground between its teammates") % str(midpoint)
	if no_master.distance_to(a) > 0.01 and no_master.distance_to(far) > 0.01:
		return "_anchor_of answered %s, which is nobody's position" % str(no_master)
	return ""


# =============================================================================
# 14. JOIN-SNAPSHOT WORLD SWEEPS (dead crocodiles, emptied chests)
# =============================================================================

func _check_join_world_sweeps() -> String:
	"""
	The two sweeps that make a joiner's world agree with the room's — measured as
	EFFECTS on real nodes, with a negative control each, never as getter
	read-backs.

	Both failures are silent and cosmetic-looking from the inside: a decoder that
	parses `dead` perfectly and an `_absorb_dead` that walks the wrong group both
	"work", and the only symptom is a crocodile alive on one screen and gone on
	another — which nobody sees on a headless machine and nobody reproduces
	without two browsers and a giant Teibi. So each sweep is given one node it
	MUST take and one node it MUST NOT, and the pair is what the check is:
	asserting only the hit would pass just as well for a sweep that flattens
	every crocodile in the world.

	No socket, no room: `_absorb_collected` / `_absorb_dead` deliberately carry no
	`_state` guard (the room-scoped guard lives on `is_coin_collected` /
	`is_croc_dead`, which are what the world ASKS), so the sweeps are drivable
	exactly as a relayed snapshot drives them.
	"""
	var mp: Node = MPManager.new()
	mp.add_to_group("mp")  # `treasure_chest.setup()` finds the manager by group.
	root.add_child(mp)

	# --- Crocodiles. The kill list names one of the two.
	var doomed: Node = load("res://scenes/characters/piglet_crocodile.tscn").instantiate()
	doomed.name = "Crocodile_9_9_0"
	root.add_child(doomed)
	var spared: Node = load("res://scenes/characters/piglet_crocodile.tscn").instantiate()
	spared.name = "Crocodile_9_9_1"
	root.add_child(spared)
	if not doomed.is_in_group("crocodile") or not spared.is_in_group("crocodile"):
		return "a freshly spawned crocodile is not in the \"crocodile\" group — the sweep check would be vacuous"

	mp._absorb_dead([doomed.croc_id()])

	var doomed_alive: bool = doomed.is_in_group("crocodile")
	var spared_alive: bool = spared.is_in_group("crocodile")
	var dead_recorded: bool = mp._dead_crocs.has(doomed.croc_id())
	doomed.free()
	spared.free()
	if doomed_alive:
		mp.free()
		return "_absorb_dead left a crushed crocodile alive — a joiner sees a crocodile nobody else has"
	if not spared_alive:
		mp.free()
		return "_absorb_dead squashed a crocodile the kill list never named"
	if not dead_recorded:
		mp.free()
		return "_absorb_dead swept the world without recording the id — the croc walks back in on a chunk reload"

	# --- The kill list's AUTHORITY rule, which the coin ids beside it deliberately
	# do not share: a crush is arbitrated by the master, so a stranger's `dead`
	# array is not a contribution, it is a request to delete crocodiles on our
	# machine. Every room code is public over `GET /rooms`, so "a member" means
	# anyone. Driven through `_receive_state` because that is where the sender is
	# known — `_absorb_dead` itself has no business asking who called it.
	var authority_failure: String = _check_kill_list_authority(mp)
	if not authority_failure.is_empty():
		mp.free()
		return authority_failure

	# --- Chests. Same shape one thing over: the collected set names one of two.
	# Two positions well over `Coin.id_at`'s 12.5 cm quantisation apart, so the
	# ids cannot collide and the control is a real control.
	var emptied: Area3D = _spawn_chest(Vector3(20.0, 0.0, 0.0))
	var untouched: Area3D = _spawn_chest(Vector3(-20.0, 0.0, 0.0))
	if emptied.chest_id() == untouched.chest_id():
		emptied.free()
		untouched.free()
		mp.free()
		return "two chests 40 m apart share a chest_id — the negative control below would be meaningless"
	if not emptied.is_in_group("chest") or not untouched.is_in_group("chest"):
		emptied.free()
		untouched.free()
		mp.free()
		return "a chest is not in the \"chest\" group — _absorb_collected can never sweep it"

	mp._absorb_collected([emptied.chest_id()])

	var emptied_spent: bool = emptied.is_queued_for_deletion()
	var untouched_spent: bool = untouched.is_queued_for_deletion()
	if not emptied_spent:
		untouched.free()
		mp.free()
		return "_absorb_collected left an emptied chest standing — opening it pays nothing and plays the shower anyway"
	if untouched_spent:
		mp.free()
		return "_absorb_collected consumed a chest the room never emptied"
	untouched.free()
	mp.free()
	return ""


func _spawn_chest(at: Vector3) -> Area3D:
	"""
	One live chest at `at`, built exactly as `endless_terrain.spawn_chest_in_chunk`
	builds one — position, then add_child, then setup() — because the id is
	latched from `global_position` inside setup() and any other order latches it
	from the origin.
	"""
	var chest := Area3D.new()
	chest.set_script(load("res://scripts/treasure_chest.gd"))
	chest.position = at
	root.add_child(chest)
	chest.setup(8, 0.8)
	return chest


func _check_kill_list_authority(mp: Node) -> String:
	"""
	A snapshot's `dead` array is honoured from the MASTER and nobody else — the
	one asymmetry with the `ids` beside it, because a kill is arbitrated while the
	collected set is a union.

	The positive half matters as much as the negative one: a `from == _master`
	test that never passes would silently take the whole fix back out, and every
	other assertion in this section would still be green, because they drive
	`_absorb_dead` directly and never go through `_receive_state` at all.
	"""
	var snapshot := {
		"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0, "ids": [],
	}
	mp._master = "the-real-master"

	# NEGATIVE: a stranger's kill list must delete nothing. Room codes are public
	# over `GET /rooms`, so "a member of the room" means anybody at all.
	var victim: Node = load("res://scenes/characters/piglet_crocodile.tscn").instantiate()
	victim.name = "Crocodile_11_11_0"
	root.add_child(victim)
	var hostile: Dictionary = snapshot.duplicate()
	hostile["dead"] = [float(victim.croc_id())]
	mp._receive_state("some-other-member", MPManager.decode_state(hostile))
	var survived: bool = victim.is_in_group("crocodile")
	var leaked: bool = mp._dead_crocs.has(victim.croc_id())
	victim.free()
	if not survived:
		return "a NON-MASTER's join snapshot deleted a crocodile — the master-only kill authority is bypassable over the relay"
	if leaked:
		return "a NON-MASTER's join snapshot wrote _dead_crocs — the crocodile stays deleted through every later chunk reload"

	# POSITIVE: the master's must land, or the fix is not there at all.
	var doomed: Node = load("res://scenes/characters/piglet_crocodile.tscn").instantiate()
	doomed.name = "Crocodile_11_11_1"
	root.add_child(doomed)
	var ruling: Dictionary = snapshot.duplicate()
	ruling["dead"] = [float(doomed.croc_id())]
	mp._receive_state("the-real-master", MPManager.decode_state(ruling))
	var still_alive: bool = doomed.is_in_group("crocodile")
	doomed.free()
	if still_alive:
		return "the MASTER's join snapshot did not apply its kill list — a joiner still sees crushed crocodiles alive"
	return ""


# =============================================================================
# 15. THE JUMP HATCH FOR REMOTE MEMBERS (bead godot-test1-s86.15)
# =============================================================================

func _check_remote_scent() -> String:
	"""
	`nearest_member_position()` must not offer a teammate who is off the ground.

	WHY THIS IS A CHECK AND NOT A COMMENT: the bug it replaces was invisible from
	every side. Presence has always carried the on-floor bit (`g`), the decoder has
	always validated it, `RemoteAvatar` has always been handed it — and this one
	function simply never looked. Solo the jump hatch worked, and against your own
	crocodiles it worked; only on the MASTER, which simulates the pack for
	everybody, did a teammate find that jumping did nothing at all. Noticing that
	by hand needs two browsers and somebody willing to jump.

	Every case pins WHO comes back rather than that somebody does, because
	"answered null" is also true of a function that has stopped answering for
	anyone — which is the OTHER way to get this wrong (one airborne peer vetoing
	the scent of a grounded teammate beside it).
	"""
	var mp: Node = MPManager.new()
	mp._state = MPManager.State.IN_ROOM

	var near := Vector3(10.0, 0.0, 0.0)
	var far := Vector3(100.0, 0.0, 0.0)
	var origin := Vector3.ZERO

	# CONTROL: both grounded — the nearer wins. This is the shipped behaviour and
	# the baseline the airborne cases are measured against.
	mp._peer_state = {
		"aaa": {"pos": near, "floor": true},
		"bbb": {"pos": far, "floor": true},
	}
	var both: Variant = mp.nearest_member_position(origin)
	if both == null or (both as Vector3).distance_to(near) > 0.01:
		mp.free()
		return "two grounded members: nearest_member_position answered %s, expected the nearer %s" % [
			str(both), str(near)
		]

	# THE FIX: the nearer one jumps, so the FARTHER one becomes the quarry.
	mp._peer_state = {
		"aaa": {"pos": near, "floor": false},
		"bbb": {"pos": far, "floor": true},
	}
	var jumped: Variant = mp.nearest_member_position(origin)
	if jumped == null:
		mp.free()
		return ("one member jumping made nearest_member_position answer null — a single airborne peer "
			+ "must not veto the scent of a grounded teammate")
	if (jumped as Vector3).distance_to(far) > 0.01:
		mp.free()
		return "a jumping member was still offered as quarry: answered %s, expected the grounded %s" % [
			str(jumped), str(far)
		]

	# Everybody airborne: nothing to smell at all.
	mp._peer_state = {
		"aaa": {"pos": near, "floor": false},
		"bbb": {"pos": far, "floor": false},
	}
	var all_up: Variant = mp.nearest_member_position(origin)
	if all_up != null:
		mp.free()
		return "every member airborne but nearest_member_position still answered %s" % str(all_up)

	# A PEER WHOSE POSE IS UNKNOWN IS GROUNDED. A join snapshot carries no `g`, so
	# an entry with no `floor` key must still be huntable — defaulting the other
	# way would make every incumbent unsmellable until its first presence packet.
	mp._peer_state = {"aaa": {"pos": near}}
	var no_bit: Variant = mp.nearest_member_position(origin)
	if no_bit == null:
		mp.free()
		return ("a peer with no on-floor bit (i.e. a join snapshot) was treated as airborne — every "
			+ "incumbent would be unsmellable to a joiner's crocodiles for its first 66 ms")

	# And the bit must NOT reach `peer_positions()`: that one is the LOD manager's
	# awake set, and the crocodiles a teammate is jumping over have to stay
	# simulated for them to land among.
	mp._master = "me"
	mp._you = "me"
	mp._peer_state = {"aaa": {"pos": near, "floor": false}}
	var awake: Variant = mp.peer_positions()
	mp.free()
	if not (awake is Array) or (awake as Array).size() != 1:
		return ("peer_positions() dropped an airborne member — the crocodiles around a jumping teammate "
			+ "would fall asleep under them")
	return ""


# =============================================================================
# 16. THE ROOM'S HEARTS, OWNED BY THE MASTER (bead godot-test1-s86.15)
# =============================================================================

func _check_room_lives_ordering() -> String:
	"""
	The room's hearts must behave like solo's, and the property that pins that is
	the CAP BURN: solo DROPS an extra life granted while already at `LIVES_CAP`
	(`collect_coin`'s `if lives < LIVES_CAP`), so a death after a long rich spell
	is visible. The stateless `shared_lives_from()` banks the overshoot instead,
	which is what made a fast-banking room effectively unlosable.

	THE NEGATIVE CONTROL IS THE OLD FUNCTION ITSELF. The scenario is built so the
	two answers DIFFER, and the check fails if they agree — because a
	`shared_lives()` that quietly forwarded to the stateless formula would satisfy
	every "the hearts went down" assertion just as well.
	"""
	var per: int = Player.EXTRA_LIFE_COINS
	var cap: int = Player.LIVES_CAP
	var base: int = Player.MAX_LIVES

	var mp: Node = MPManager.new()
	root.add_child(mp)
	mp._state = MPManager.State.IN_ROOM
	mp._you = "me"
	mp._master = "me"
	# Contributing, and the join settled, with no snapshots to wait for.
	mp._first_member = true

	# One remote peer carries the room's whole bank and death count — that is what
	# `shared_bank()` / `shared_lives_spent()` sum, so no player node is needed.
	var peer: Dictionary = {"pos": Vector3.ZERO, "floor": true, "coins": 0, "spent": 0, "dist": 0}
	mp._peer_state = {"aaa": peer}

	mp._tick_room_lives()
	if not mp._room_lives_owned:
		mp.free()
		return "the master did not take ownership of the room's hearts"
	if mp.shared_lives(0, 0) != base:
		var fresh: Variant = mp.shared_lives(0, 0)
		mp.free()
		return "a fresh room started on %s hearts, expected MAX_LIVES (%d)" % [str(fresh), base]

	# TAKING OWNERSHIP MUST NOT REFILL HEARTS THAT ARE ALREADY SPENT. Two ways in
	# and both already have deaths behind them: hosting from a live solo run in
	# which the player has been bitten (a host's own tally IS the room's opening
	# balance), and a promotion where no `rl` ever arrived. Seeding at MAX_LIVES
	# and then marking those deaths already-charged handed the room free lives.
	var wounded: Node = MPManager.new()
	root.add_child(wounded)
	wounded._state = MPManager.State.IN_ROOM
	wounded._you = "me"
	wounded._master = "me"
	wounded._first_member = true
	wounded._peer_state = {}
	wounded._tick_room_lives()  # own_spent is read off the player group: none here...
	# ...so drive the death through this peer's OWN contribution, which is what a
	# host arriving from a solo run actually carries.
	wounded._room_lives_owned = false
	wounded._peer_state = {"aaa": {"pos": Vector3.ZERO, "floor": true, "coins": 0, "spent": 1, "dist": 0}}
	wounded._tick_room_lives()
	var wounded_start: Variant = wounded.shared_lives(0, 0)
	wounded.free()
	if wounded_start == base:
		return ("a room seeded while a life was already spent started on MAX_LIVES (%d) — taking "
			+ "ownership refilled a heart the room had lost") % base
	if wounded_start != base - 1:
		return "a room seeded with one life spent started on %s hearts, expected %d" % [
			str(wounded_start), base - 1
		]

	# Bank far past the cap without dying: every grant beyond LIVES_CAP is BURNT,
	# exactly as solo burns it.
	peer["coins"] = per * 20
	mp._tick_room_lives()
	if mp.shared_lives(0, 0) != cap:
		var pinned: Variant = mp.shared_lives(0, 0)
		mp.free()
		return "a room banking %d coins holds %s hearts, expected the cap (%d)" % [
			int(peer["coins"]), str(pinned), cap
		]

	# NOW DIE. Solo this shows immediately (the overshoot was never kept); the
	# stateless formula still has ~17 unspent grants in hand and shows nothing.
	peer["spent"] = 1
	mp._tick_room_lives()
	var owned: Variant = mp.shared_lives(0, 0)
	var stateless: int = MPManager.shared_lives_from(int(peer["coins"]), 1, base, per, cap)
	if owned != cap - 1:
		mp.free()
		return ("a death after a rich spell left %s hearts, expected %d — the cap overshoot is being "
			+ "banked again") % [str(owned), cap - 1]
	if stateless == owned:
		mp.free()
		return ("the stateless formula agrees with the owned count in the very scenario built to "
			+ "separate them — this check can no longer tell the fix from the bug")

	# A SECOND TICK WITH NOTHING NEW MUST CHANGE NOTHING. The death is charged as a
	# delta against `_room_spent_seen`; charging the absolute total every frame
	# would drain the room in about a second.
	mp._tick_room_lives()
	if mp.shared_lives(0, 0) != cap - 1:
		var redrained: Variant = mp.shared_lives(0, 0)
		mp.free()
		return "re-ticking with no new events moved the hearts to %s — the death delta is re-charged" % str(redrained)

	# Coins banked AFTER a death still buy a heart back — the thing the obvious
	# alternative formula (`mini(base + bank/per, cap) - spent`) would have broken.
	peer["coins"] = int(peer["coins"]) + per
	mp._tick_room_lives()
	if mp.shared_lives(0, 0) != cap:
		var bought: Variant = mp.shared_lives(0, 0)
		mp.free()
		return "banking another %d coins after a death did not buy the heart back (%s)" % [per, str(bought)]

	# MASTER MIGRATION MUST NOT REFILL THE ROOM. Demote, then promote: the new
	# owner adopts what the old one published rather than starting at MAX_LIVES,
	# and must not re-walk thresholds the room has already been paid for.
	# One more death, chosen so the room lands on a count that is NOT MAX_LIVES —
	# otherwise "adopted" and "reset to MAX_LIVES" are the same number and the
	# assertion below would pass for a migration that silently refilled the room.
	peer["spent"] = 2
	mp._tick_room_lives()
	var before_migration: Variant = mp.shared_lives(0, 0)
	mp._master = "someone-else"
	mp._tick_room_lives()  # Demotes: ownership dropped.
	if mp._room_lives_owned:
		mp.free()
		return "a demoted master kept ownership of the room's hearts"
	mp._room_lives_seen = int(before_migration)  # What the new master had been publishing.
	mp._master = "me"
	mp._tick_room_lives()  # Promotes: adopt, do not reset.
	var after_migration: Variant = mp.shared_lives(0, 0)
	mp.free()
	if after_migration == base:
		return ("the promoted master landed on exactly MAX_LIVES, so this check cannot tell adoption "
			+ "from a reset — rebuild the scenario")
	if after_migration != before_migration:
		return "a master migration moved the room from %s hearts to %s — the count must carry over" % [
			str(before_migration), str(after_migration)
		]
	return ""


# =============================================================================
# 17. THE CLAIM'S BASE VALUE ON THE WIRE (bead godot-test1-42n)
# =============================================================================

## A stand-in for `player_controller.bank_awarded()`, so the manager's half of the
## payout can be measured without booting the player scene (which mints a profile
## id into `user://best_run.cfg` — `scripts/progression_selfcheck.gd` owns the
## end-to-end version of this check for exactly that reason, and redirects
## `BestRunStore.config_path` at a throwaway file so it never opens the real
## profile). Built from source at runtime rather than kept as a file: it is four lines
## and a file would be a scene-tree fixture nobody maintains.
const BANK_STUB_SOURCE := """extends Node
var banked: int = -1
var base_seen: int = -1
var calls: int = 0
func bank_awarded(amount: int, base_total: int = 0) -> void:
	banked = amount
	base_seen = base_total
	calls += 1
"""


func _check_claim_base_value() -> String:
	"""
	A pickup won through the claim protocol must reach `bank_awarded()` with its
	PRE-MULTIPLIER worth beside the multiplied award.

	Lifetime coins count what was physically picked up; `a` has a x1..x5 score
	multiplier baked in. Before this bead nothing carried a base value at all, so
	every coin a peer WON in a room credited nothing towards its level — the peer
	that LOST each race was the one that levelled, through `collect_coin`.

	Two assertions, and each exists because the other alone passes for the bug:
	the base must be non-zero (crediting nothing is what shipped) AND it must
	differ from the award (crediting the award is the easy mistake and inflates a
	level 5x). The scenario is a chest burst at a wound-up room streak precisely
	so the two numbers cannot coincide.
	"""
	var stub_script := GDScript.new()
	stub_script.source_code = BANK_STUB_SOURCE
	var compiled: int = stub_script.reload()
	if compiled != OK:
		return "the bank_awarded stub script did not compile (%d)" % compiled
	var stub: Node = Node.new()
	stub.set_script(stub_script)
	stub.add_to_group("player")
	root.add_child(stub)

	var mp: Node = MPManager.new()
	root.add_child(mp)
	mp._state = MPManager.State.IN_ROOM
	mp._you = "0123456789abcdef"
	mp._master = mp._you
	# No `_rtc`, so `_broadcast_reliable` is a no-op — the master applies its own
	# ruling locally, which is the path the winner-is-the-master case takes anyway.

	# Wind the room's streak past a step so the multiplier is genuinely above 1, or
	# the award and the base would be the same number and this proves nothing.
	mp._room_streak = Player.STREAK_COINS_PER_STEP * 2
	mp._room_streak_deadline_msec = Time.get_ticks_msec() + 60000

	var count: int = 3
	var value: int = Coin.GEM_VALUE
	mp._resolve_claim(12345, MPManager.peer_int_id(mp._you), count, value)

	var banked: int = stub.banked
	var base_seen: int = stub.base_seen
	var calls: int = stub.calls
	stub.free()
	mp.free()

	if calls != 1:
		return "_resolve_claim called bank_awarded %d times, expected exactly 1" % calls
	if base_seen == 0:
		return ("no base value reached bank_awarded — a pickup won through the claim protocol still "
			+ "credits no lifetime coins")
	if base_seen != count * value:
		return "the base value was %d, expected %d pickups x %d = %d" % [
			base_seen, count, value, count * value
		]
	if banked == base_seen:
		return ("the awarded amount equals the base value, so the room's multiplier was never applied "
			+ "and this check cannot tell the two apart — rebuild the scenario")
	if banked <= base_seen:
		return "the awarded amount %d is not above the base %d — the multiplier went backwards" % [
			banked, base_seen
		]

	# THE TRUST BOUNDARY, and the reason the base value is not on the wire at all.
	return _check_confirm_base_is_unforgeable()


func _check_confirm_base_is_unforgeable() -> String:
	"""
	A NON-MASTER's base value must come from its own pending claim and from
	nothing a peer sent it — see `_receive_confirm`.

	The confirm names its own winner (`by`), so a hostile master can address one
	to any member. `a` has always been forgeable that way and inflates a
	RUN-SCOPED bank; a forgeable base value would mint LIFETIME coins, which are
	monotone and persisted and therefore outlive the room. So the check is not
	"is the field bounded" but "is there a field to forge": a confirm for a pickup
	this peer never claimed must credit ZERO however generous it looks, and a
	confirm for one it did claim must credit exactly what it asked for.
	"""
	var stub_script := GDScript.new()
	stub_script.source_code = BANK_STUB_SOURCE
	stub_script.reload()
	var stub: Node = Node.new()
	stub.set_script(stub_script)
	stub.add_to_group("player")
	root.add_child(stub)

	var mp: Node = MPManager.new()
	root.add_child(mp)
	mp._state = MPManager.State.IN_ROOM
	mp._you = "0123456789abcdef"
	mp._master = "fedcba9876543210"
	var me: int = MPManager.peer_int_id(mp._you)

	# FORGED: a confirm naming us the winner of a pickup we never claimed, with a
	# `b` a hostile master would love us to believe. The coin is still banked (the
	# run-scoped `a` was always the master's to say), but the level must not move.
	mp._receive_confirm(mp._master, {"t": "cnf", "id": 1, "by": me, "a": 64000, "m": 1, "b": 64000})
	var forged_calls: int = stub.calls
	var forged_base: int = stub.base_seen

	# HONEST: a pickup we really did claim, so our own entry says what it was
	# worth. Two gems, and a `b` on the wire that contradicts it — which must be
	# ignored in favour of what we asked for.
	mp._pending_claims[7] = {"n": 2, "v": Coin.GEM_VALUE, "age": 0.0, "tries": 1}
	mp._receive_confirm(mp._master, {"t": "cnf", "id": 7, "by": me, "a": 40, "m": 2, "b": 99999})
	var honest_calls: int = stub.calls
	var honest_base: int = stub.base_seen

	stub.free()
	mp.free()

	if forged_calls != 1:
		return "a confirm naming us the winner was not applied at all — the coin itself is lost"
	if forged_base != 0:
		return ("a confirm for a pickup we never claimed credited %d lifetime coins — a hostile master "
			+ "can mint PERSISTED progression for any member") % forged_base
	if honest_calls != 2:
		return "the confirm for a pickup we did claim was not applied (%d calls)" % honest_calls
	if honest_base != 2 * Coin.GEM_VALUE:
		return ("a claim of 2 gems credited %d lifetime coins, expected %d — the base must come from "
			+ "our own pending claim, not from the packet") % [honest_base, 2 * Coin.GEM_VALUE]
	return ""


# =============================================================================
# 18. TERRAIN FOCUS POINTS (bead godot-test1-s86.14)
# =============================================================================

func _check_terrain_focus_points() -> String:
	"""
	`endless_terrain.set_focus_points()` must keep chunks loaded around a FAR
	teammate — and must keep the promise it makes about how many.

	The failure it guards is a quiet one. With no pinned chunks the master has no
	crocodiles loaded beside a distant peer, so it publishes none, that peer's
	copies time out after `CROC_SYNC_TIMEOUT` and fall back to local simulation.
	Nothing errors, nothing duplicates, nothing is visible headless — it is a
	divergence between two browsers, which is the class of bug the whole
	multiplayer selfcheck exists for.

	Measured as an EFFECT on a real terrain's chunk field, with a control at each
	step: the far chunk must appear when focused and disappear when released,
	because "chunks exist" is true of every terrain ever built.
	"""
	# A bare terrain: every content spawner off, so it builds ground planes and
	# nothing else. The question is WHICH chunks exist, and generating a thousand
	# crocodiles to answer it would be a minute of nothing.
	var terrain = Terrain.new()
	terrain.spawn_objects = false
	terrain.spawn_crocodiles = false
	terrain.spawn_coins = false
	terrain.spawn_artifacts = false
	terrain.spawn_camps = false
	terrain.spawn_chests = false
	terrain.spawn_biome_content = false
	terrain.render_distance = 1
	terrain.terrain_material = StandardMaterial3D.new()
	root.add_child(terrain)

	# 1 km down the road — far past `render_distance` x `chunk_size`, i.e. exactly
	# the peer this feature exists for.
	var far_peer := Vector3(1000.0, 0.0, 0.0)
	var far_chunk: Vector2i = terrain.world_to_chunk(far_peer)

	# CONTROL FIRST: with no focus points that chunk is nowhere in the field.
	terrain.update_chunks(Vector2i.ZERO)
	if _terrain_holds(terrain, far_chunk):
		terrain.free()
		return "a terrain with no focus points already covers %s — the check below would be vacuous" % str(far_chunk)

	# THE EFFECT.
	terrain.set_focus_points([far_peer])
	if not terrain.focus_dirty:
		terrain.free()
		return "set_focus_points did not raise focus_dirty — _process would never rebuild the field"
	terrain.update_chunks(Vector2i.ZERO)
	if not _terrain_holds(terrain, far_chunk):
		terrain.free()
		return "the chunk a focused teammate stands in (%s) is neither active nor pending" % str(far_chunk)

	# COVERAGE IN METRES, not in chunks — the claim `FOCUS_RING` actually rests on.
	# A 3x3 block guarantees at least `chunk_size` of loaded ground in every
	# direction from the peer, covering the 45 m radius inside which a crocodile is
	# awake at all. Measured from the WORST spot in the chunk: a corner.
	var corner := Vector3(
		float(far_chunk.x) * terrain.chunk_size, 0.0, float(far_chunk.y) * terrain.chunk_size
	)
	terrain.set_focus_points([corner])
	for step: int in 16:
		var angle: float = TAU * float(step) / 16.0
		var probe: Vector3 = corner + Vector3(cos(angle), 0.0, sin(angle)) * 45.0
		if not terrain.focus_chunks.has(terrain.world_to_chunk(probe)):
			terrain.free()
			return ("a point 45 m from a focused peer (%s) falls in an unpinned chunk — the master would "
				+ "lack the crocodiles the LOD manager holds awake for that peer") % str(probe)
	# ...and the other half of the same claim: the ring must not be WIDER than it
	# says, or the memory cap it documents is fiction.
	if terrain.focus_chunks.has(terrain.world_to_chunk(corner + Vector3(200.0, 0.0, 0.0))):
		terrain.free()
		return "a point 200 m from a focused peer is pinned — FOCUS_RING is wider than documented"

	# THE CAP, which is the whole memory argument for shipping this on web.
	var many: Array = []
	for i: int in 10:
		many.append(Vector3(float(i) * 900.0, 0.0, float(i) * 700.0))
	terrain.set_focus_points(many)
	if terrain.focus_chunks.size() > Terrain.MAX_FOCUS_CHUNKS:
		var overflow: int = terrain.focus_chunks.size()
		terrain.free()
		return "ten focus points pinned %d chunks, over the MAX_FOCUS_CHUNKS cap of %d" % [
			overflow, Terrain.MAX_FOCUS_CHUNKS
		]

	# IDEMPOTENT: the same set again must not dirty the field, or the 9 Hz caller
	# would rebuild the whole pending queue nine times a second forever.
	terrain.focus_dirty = false
	terrain.set_focus_points(many)
	if terrain.focus_dirty:
		terrain.free()
		return "set_focus_points dirtied the field for an UNCHANGED set — the chunk queue would rebuild at the caller's tick rate"

	# RELEASE: an empty set (offline, a non-master, a peer that left) must drop
	# every pinned chunk, or a room would leak its chunks into solo play.
	terrain.set_focus_points([])
	terrain.update_chunks(Vector2i.ZERO)
	var still_pinned: bool = _terrain_holds(terrain, far_chunk)
	var leftover: int = terrain.focus_chunks.size()
	terrain.free()
	if leftover != 0:
		return "set_focus_points([]) left %d pinned chunks" % leftover
	if still_pinned:
		return "releasing the focus points left the far chunk %s in the field" % str(far_chunk)
	return ""


func _terrain_holds(terrain, chunk: Vector2i) -> bool:
	"""
	Whether a chunk is in the terrain's field at all — built, or queued to be built.
	Both count: the time-slicing means "pending" is simply "built a few frames from
	now", and a focus chunk is never inside the synchronous safety ring.
	"""
	return terrain.active_chunks.has(chunk) or terrain.pending_chunks.has(chunk)


# =============================================================================
# 19. HUNTER SYNC INHERITANCE (bead godot-test1-9rm.5)
# =============================================================================

func _check_hunter_sync() -> String:
	"""
	The hunter robot rides the crocodile sync WITH NO PROTOCOL OF ITS OWN, and
	this is the check that makes that a fact rather than a hope.

	It is the first species whose deterministic node name does not begin with
	"Crocodile_" (`Hunter_<cx>_<cy>_<i>`, its own index namespace), and the whole
	identity scheme is a hash of that name — so every place the sync could have
	grown a quiet prefix assumption is a place the hunter silently stops syncing,
	on the deliberately SILENT "not my chunk" path. Nobody sees that headless and
	nobody reproduces it without two browsers.

	Three claims, each with the negative control that keeps it from passing
	vacuously:

	  1. IDENTITY. The two namespaces do not collide, and a hunter name survives
	     the packet's PackedInt32Array — the sign-extension trap that once ate
	     43% of the crocodile pack is a property of the hash's RANGE, so a new
	     name scheme re-rolls the dice and has to be swept, not spot-checked.
	  2. LOOKUP. The manager's live id cache resolves a real hunter node to the
	     hunter and a real crocodile to the crocodile. This is the prefix
	     question answered on the actual code path instead of by reading it.
	  3. THE FLAG BYTE. Every combination the encoder can produce round-trips
	     through a real hunter body byte-identically. That is the executable form
	     of this bead's ruling that the hunt states owe no new bit (see
	     CROC_FLAG_BURROWED's note in mp_manager.gd): today five bits, five
	     restored, and the day someone adds a sixth for a pose motion cannot
	     show, this fails until `set_remote_state` learns it too.
	"""
	# --- 1. Identity. Distinct namespaces, and wire-safe over the real scheme.
	var hunter_name: String = "Hunter_3_-4_0"
	var hunter_id: int = CrocAI.croc_id_for(hunter_name)
	if hunter_id == CrocAI.croc_id_for("Crocodile_3_-4_0"):
		return "croc_id_for collided across the Hunter_/Crocodile_ namespaces"
	if hunter_id == CrocAI.croc_id_for("Hunter_3_-4_1"):
		return "croc_id_for collided across the hunter spawn index"
	var wire: PackedInt32Array = PackedInt32Array()
	for cx: int in range(-6, 7):
		for cy: int in range(-6, 7):
			var probe: String = "Hunter_%d_%d_0" % [cx, cy]
			var probe_id: int = CrocAI.croc_id_for(probe)
			wire.clear()
			wire.append(probe_id)
			if wire[0] != probe_id:
				return "croc_id_for(%s) == %d does not survive PackedInt32Array (%d)" % [
					probe, probe_id, wire[0]
				]

	# --- 2. Lookup. Two live bodies, one of each prefix, through the real cache.
	var mp: Node = MPManager.new()
	mp.add_to_group("mp")
	root.add_child(mp)

	var hunter: Node = _spawn_hunter(hunter_name)
	var croc: Node = load("res://scenes/characters/piglet_crocodile.tscn").instantiate()
	croc.name = "Crocodile_3_-4_0"
	root.add_child(croc)

	if not hunter.is_in_group("crocodile"):
		return "the hunter is not in the \"crocodile\" group — it inherits no sync at all"
	if hunter.croc_id() != hunter_id:
		return "a live hunter's croc_id() (%d) does not match croc_id_for(%s) (%d)" % [
			hunter.croc_id(), hunter_name, hunter_id
		]
	if String(hunter.spec.get("behavior", "")) != "hunt":
		return "the spawned hunter did not resolve the hunt row — check 3 would be vacuous"

	mp._rebuild_croc_cache()
	if mp._croc_by_id(hunter_id) != hunter:
		return "the sync id cache does not resolve a Hunter_ node — the sync assumes a prefix"
	if mp._croc_by_id(croc.croc_id()) != croc:
		return "the sync id cache does not resolve a Crocodile_ node beside a hunter"

	# --- 3. The flag byte. Sweep every combination the encoder can produce.
	var sender: Node = _spawn_hunter("Hunter_7_7_0")
	var receiver: Node = _spawn_hunter("Hunter_7_7_1")
	var fields: Array[String] = [
		"is_chasing", "is_fleeing", "is_paused", "is_biting", "is_burrowed"
	]

	# THE SWEEP IS ONLY AS COMPLETE AS THIS LIST, so the list is checked against
	# the protocol rather than trusted. Every CROC_FLAG_* the manager declares is
	# a bit the encoder can put on the wire; if the five fields above cannot
	# between them light all of them, a sixth flag has been added and this sweep
	# would round-trip a byte that never contains it — passing while the exact
	# drift it exists to catch ships. Read off the const map so a new bit needs no
	# edit here to be NOTICED, only to be covered.
	var declared: int = 0
	for key: String in MPManager.get_script_constant_map().keys():
		if key.begins_with("CROC_FLAG_"):
			declared |= int(MPManager.get_script_constant_map()[key])
	for bit: int in range(fields.size()):
		sender.set(fields[bit], true)
	var full: int = MPManager._croc_flags(sender)
	if full != declared:
		return ("the flag sweep drives %d of the declared CROC_FLAG_* mask %d — a bit was added to "
				+ "mp_manager without a field here, so the round-trip below cannot see it") % [full, declared]
	for combo: int in range(1 << fields.size()):
		for bit: int in range(fields.size()):
			sender.set(fields[bit], (combo & (1 << bit)) != 0)
			# The receiver is reset rather than left as the last iteration left it,
			# because BITING is a LATCH by design: the decoder calls _start_bite()
			# when the bit is set and never clears it when it is not (the local
			# animation does that). Carrying it over would fail the sweep for a
			# decoder that is behaving exactly as specified.
			receiver.set(fields[bit], false)
		var sent: int = MPManager._croc_flags(sender)
		receiver.set_remote_state(Vector3(12.0, 0.0, -3.0), 1.25, sent)
		var back: int = MPManager._croc_flags(receiver)
		if back != sent:
			return "hunter state byte %d round-tripped as %d — set_remote_state drops a bit the encoder sends" % [
				sent, back
			]

	# The FIRST sample snaps, and a hunter must be no exception: a body that never
	# takes the master's transform renders a pose the room does not share, which
	# is a failure the byte sweep above cannot see.
	#
	# A VIRGIN BODY AND A SHORT HOP, both load-bearing. `set_remote_state` snaps on
	# two conditions OR'd together — no sample yet, or a jump past
	# CROC_TELEPORT_DISTANCE — so reusing the swept receiver (already sampled) or
	# aiming further than 8 m would let the teleport branch answer for the
	# first-sample branch and the check would pass with that branch deleted.
	var virgin: Node = _spawn_hunter("Hunter_7_7_2")
	var landing := Vector3(2.0, 0.0, -1.0)
	virgin.set_remote_state(landing, 1.25, 0)
	if not virgin.remote_driven:
		return "a hunter given a sample is not remote_driven — it would keep running its own hunt arm"
	if virgin.global_position.distance_to(landing) > 0.01:
		return "a hunter's first remote sample did not snap it to the master's position (%s)" % virgin.global_position

	hunter.free()
	croc.free()
	sender.free()
	receiver.free()
	virgin.free()
	mp.free()
	return ""


# =============================================================================
# 20. THE ACQUISITION CUE FIRES ON EVERY SCREEN, NOT JUST THE MASTER'S
# =============================================================================

## A sound manager that only counts. Group "sound_manager" is how every SFX hook
## in this project finds the real one, so a counter in that group is on the exact
## code path the game uses — no signal, no injection, no hard reference.
const SOUND_STUB_SOURCE := """extends Node
var pings: int = 0
var hisses: int = 0
var growls: int = 0
func play_hunter_lock_on() -> void: pings += 1
func play_viper_hiss() -> void: hisses += 1
func play_boss_growl() -> void: growls += 1
"""


func _check_acquisition_cue() -> String:
	"""
	The lock-on ping fires ONCE PER ENGAGEMENT on BOTH paths — the local one and
	the remote one — and only for the species that owe a warning.

	WHY THIS IS AN MP CHECK AT ALL. The cue is audio, but the bug it guards is a
	multiplayer one and it is invisible in single player: a remote-driven body
	returns from `_tick_remote()` at the top of `_physics_process`, so it never
	reaches `_update_chase_state()`, never reaches the behaviour dispatch, and
	announced nothing. The master heard its hunters lock on; the other one to
	three players in the room heard silence and got no warning at all. Nobody
	reproduces that without two browsers, which is the same reason
	`_check_hunter_sync` above exists.

	Four claims, each with the control that stops it passing vacuously:

	  1. LOCAL PATH. A hunter that acquires a quarry through the ordinary chase
	     logic pings exactly once, and does NOT ping again on the following ticks
	     of the same chase — a per-frame cue would be a klaxon at 60 Hz.
	  2. RE-ENGAGEMENT. Losing the quarry and finding it again is a NEW
	     engagement and pings again. Without this, an implementation that latches
	     "announced" forever and never clears it passes claim 1.
	  3. REMOTE PATH. `set_remote_state()` re-detects the same edge off
	     CROC_FLAG_CHASING — one ping on the false->true sample, none on the
	     repeats that follow at 10 Hz, and another when the flag drops and
	     returns. This is the half the bug was in.
	  4. IT IS KEYED ON THE BEHAVIOUR. A plain crocodile driven through BOTH
	     paths stays silent on all three cues. Without this control, a hook that
	     pings unconditionally on every chase edge in the game passes 1-3.
	"""
	var stub_script := GDScript.new()
	stub_script.source_code = SOUND_STUB_SOURCE
	if stub_script.reload() != OK:
		return "the sound-manager stub did not compile"
	var sound: Node = Node.new()
	sound.set_script(stub_script)
	sound.add_to_group("sound_manager")
	root.add_child(sound)

	# The quarry, in group "player" and in the tree BEFORE either body is spawned:
	# `player_node` is cached once in _ready(), so a quarry added afterwards would
	# leave `_update_chase_state` returning early and claims 1-2 vacuous.
	var quarry := Node3D.new()
	quarry.add_to_group("player")
	root.add_child(quarry)
	quarry.global_position = Vector3.ZERO

	# --- 1 & 2. The local path: acquire, hold, lose, re-acquire.
	var hunter: Node = _spawn_hunter("Hunter_9_9_0")
	# `_ready` defers the quarry lookup to the next idle frame and this check is
	# synchronous, so run the same function by hand rather than await (making one
	# check a coroutine would make `_run_checks` one too, all nineteen of them).
	hunter._find_player()
	if hunter.player_node != quarry:
		return ("the hunter cached a quarry that is not this check's (%s) — an earlier check leaked "
				+ "a node into group \"player\" and claims 1-2 would measure the wrong body") % str(hunter.player_node)
	if float(hunter.detection_radius) < 10.0:
		return "the hunter's detection radius (%f) is under the 5 m probe distance below" % hunter.detection_radius
	hunter.global_position = Vector3(5.0, 0.0, 0.0)   # inside 25 m: smellable
	hunter._update_chase_state()
	if not hunter.is_chasing:
		return "the hunter did not acquire a quarry 5 m away — claims 1 and 2 would be vacuous"
	if sound.pings != 1:
		return "a hunter acquiring its quarry locally rang %d lock-on pings, expected exactly 1" % sound.pings
	hunter._update_chase_state()
	hunter._update_chase_state()
	if sound.pings != 1:
		return "the lock-on ping fires per FRAME, not per engagement (%d pings over 3 chase ticks)" % sound.pings

	hunter.global_position = Vector3(400.0, 0.0, 0.0)  # far outside detection
	hunter._update_chase_state()
	if hunter.is_chasing:
		return "the hunter did not lose a quarry 400 m away — the re-engagement claim would be vacuous"
	hunter.global_position = Vector3(5.0, 0.0, 0.0)
	hunter._update_chase_state()
	if sound.pings != 2:
		return "re-acquiring is a new engagement and must ping again (%d pings, expected 2)" % sound.pings

	# --- 3. The remote path: the same edge, read off the wire instead.
	var remote: Node = _spawn_hunter("Hunter_9_9_1")
	var here := Vector3(3.0, 0.0, 0.0)
	sound.pings = 0
	remote.set_remote_state(here, 0.0, MPManager.CROC_FLAG_CHASING)
	if sound.pings != 1:
		return ("a remote-driven hunter whose first sample says CHASING rang %d pings, expected 1 — "
				+ "the peer is deaf to the master's lock-on") % sound.pings
	remote.set_remote_state(here, 0.0, MPManager.CROC_FLAG_CHASING)
	remote.set_remote_state(here, 0.0, MPManager.CROC_FLAG_CHASING)
	if sound.pings != 1:
		return "the remote ping fires per SAMPLE, not per engagement (%d pings over 3 chasing samples)" % sound.pings
	remote.set_remote_state(here, 0.0, 0)
	if sound.pings != 1:
		return "a sample that drops CHASING rang a ping (%d) — only the false->true edge may" % sound.pings
	remote.set_remote_state(here, 0.0, MPManager.CROC_FLAG_CHASING)
	if sound.pings != 2:
		return "a remote hunter re-acquiring did not ping again (%d pings, expected 2)" % sound.pings

	# --- 4. The control: a plain crocodile is silent down both paths.
	var croc: Node = load("res://scenes/characters/piglet_crocodile.tscn").instantiate()
	croc.name = "Crocodile_9_9_0"
	root.add_child(croc)
	croc._find_player()
	if String(croc.spec.get("behavior", "")) == "hunt":
		return "the control crocodile resolved the hunt row — claim 4 cannot fail"
	sound.pings = 0
	sound.hisses = 0
	sound.growls = 0
	croc.global_position = Vector3(3.0, 0.0, 0.0)
	croc._update_chase_state()
	if not croc.is_chasing:
		return "the control crocodile did not acquire the quarry — claim 4 would be vacuous"
	croc.set_remote_state(here, 0.0, 0)
	croc.set_remote_state(here, 0.0, MPManager.CROC_FLAG_CHASING)
	if sound.pings != 0:
		return "a plain crocodile rang the hunter's lock-on ping %d times — the cue is not keyed on the behaviour" % sound.pings
	if sound.hisses != 0 or sound.growls != 0:
		return "a plain crocodile rang the ambusher's hiss (%d) or the boss growl (%d)" % [sound.hisses, sound.growls]

	hunter.free()
	remote.free()
	croc.free()
	quarry.free()
	sound.free()
	return ""


func _spawn_hunter(node_name: String) -> Node:
	## One hunter, built the way `endless_terrain.spawn_hunters_in_chunk` builds
	## one — name and `species` BOTH set before add_child, because _ready() is
	## where the name is latched into the id and where `species` resolves into
	## `spec`. A hunter added first would be a crocodile wearing a robot mesh.
	var hunter: Node = load("res://scenes/characters/hunter_robot.tscn").instantiate()
	hunter.name = node_name
	hunter.species = "hunter_robot"
	root.add_child(hunter)
	return hunter
