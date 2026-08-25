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
	return _check_room_multiplier()


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
	# below are a perfectly valid presence packet, so only the dispatch stops it.
	# Drive the dispatcher directly (never added to the tree — nothing here opens
	# a socket) and assert it recorded no contribution for that peer.
	var manager := MPManager.new() as Node
	manager._receive_mesh_verb("selfcheck-peer", "zzz_a_verb_from_a_later_build", {
		"t": "zzz_a_verb_from_a_later_build",
		"p": Vector3.ZERO, "y": 0.0, "c": 0, "s": 0.0, "g": true, "cc": 99,
	})
	var leaked: bool = not (manager._peer_state as Dictionary).is_empty()
	manager.free()
	if leaked:
		return "an unknown mesh verb was applied as a presence packet"
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
