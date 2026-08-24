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

const MPManager: GDScript = preload("res://scripts/mp_manager.gd")
const Terrain: GDScript = preload("res://scripts/endless_terrain.gd")
const Coin: GDScript = preload("res://scripts/coin.gd")
const Player: GDScript = preload("res://scripts/player_controller.gd")


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
	return _check_hero_index()


# =============================================================================
# 1. ISOLATION CONTRACT
# =============================================================================

func _check_avatar_isolation() -> String:
	var avatar := RemoteAvatar.new()
	avatar.setup("selfcheck-peer")
	avatar.set_character(0)

	# `set_character` has four SILENT early-return paths (bad index, same index,
	# the swap cooldown, a load() that returned null). Any of them would leave an
	# empty subtree here and the walk below would pass by covering nothing —
	# a green run that guards precisely zero of the contract. Assert it loaded.
	if avatar.character_node == null:
		avatar.free()
		return "set_character(0) instanced no model — the isolation walk would be vacuous"

	var failure: String = _walk_isolation(avatar, avatar)
	avatar.free()
	return failure


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
	terrain.free()

	if first != second:
		return "same seed gave different biome offsets: %s vs %s" % [first, second]
	if first == Vector2.ZERO:
		return "set_run_seed did not derive a biome offset"
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
