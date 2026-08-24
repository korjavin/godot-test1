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
## export. It touches no network, no WebRTC and no scene — only the pure parts.
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

const MPManager: GDScript = preload("res://scripts/mp_manager.gd")
const Terrain: GDScript = preload("res://scripts/endless_terrain.gd")


func _initialize() -> void:
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
	return _check_peer_ids()


# =============================================================================
# 1. ISOLATION CONTRACT
# =============================================================================

func _check_avatar_isolation() -> String:
	var avatar := RemoteAvatar.new()
	avatar.setup("selfcheck-peer")
	avatar.set_character(0)

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
		if value != MPManager.peer_int_id(id):
			return "peer_int_id(%s) is not stable across calls" % id
		if seen.has(value):
			return "peer_int_id collision: %s and %s both give %d" % [seen[value], id, value]
		seen[value] = id
	return ""
