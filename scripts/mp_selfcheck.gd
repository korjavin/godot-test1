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
##   8. THE RETIRED HEART FIELDS. `lv`/`rl`/`ls`/`gs` stopped MEANING anything
##      (bead godot-test1-0bc) and an old peer does not know it — both decoders
##      must accept a packet carrying them, hand none of them back, and validate
##      neither, while the LIVE field beside them is still checked. `lv`/`rl` also
##      stopped being SENT; `ls`/`gs` still go out as inert zeroes for one release,
##      because the previous build's snapshot parser requires `ls` — see case (e).
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
##  17. The claim's BASE VALUE, which is what a room's pickups credit to
##      meta-progression — non-zero, distinct from the multiplied award, and
##      UNFORGEABLE: derived from the winner's own pending claim rather than from
##      the confirm, so a hostile master cannot mint persisted progression.
##  21. THE ROOM'S CAPTIVE SET — the fifth trust boundary and the rules that make
##      one broadcast verb safe: the `cap` parser against hostile packets, THE
##      HOLDER RULE (only the hero's own holder may report him taken) with the
##      reassigned-and-taken-again case that a lifetime cap would have broken, the
##      pool whitelist, the open release direction, the rate budget, the dispatch
##      arm, the picker refusing a captive hero AND being told to repaint, the
##      reassignment candidate, and the MASTER-ONLY join snapshot.
##  22. THE MASTER'S ROOM PUBLISH — one verb for the two values a room may never
##      disagree about: the captive set (repairing the join gap the per-hero verb
##      cannot reach) and the break-out clock and verdict. Master-only, parsed at a
##      trust boundary, converging in BOTH directions without undoing a fresh local
##      assertion, and relayed to peers whose mesh is still negotiating.
##  23. THE HERO PRESS DECISION — what R and 1-4 mean in a room, as the pure
##      function they both route through: the hand switches locally, an UNHELD
##      free hero is CLAIMED through the lobby (nothing moves until the broadcast
##      confirms), and a hero a teammate holds — or one in a cell — stays refused.
##      Plus `hero_holder()`, the query it reads, and the claim actually reaching
##      the lobby.
##  24. THE ABILITY STATE A WATCHER SEES — Teibi's Resize and Windman's Air Rush
##      on the presence packet: absent reads as normal (an older peer stays
##      visible), a byte survives, a hostile value drops the packet whole, and the
##      scale a bit asks for is the player's own constant.
##  18. Terrain FOCUS POINTS — the chunks that stay loaded around a far teammate,
##      so the master has crocodiles there to simulate at all. Measured in metres
##      against SIM_RADIUS, with the memory cap and the release both pinned.

const MPManager: GDScript = preload("res://scripts/mp_manager.gd")
## The codec is reached through the `MpCodec` global class name everywhere it is
## CALLED; this preload exists only for `get_script_constant_map()`, which is a
## Script method and not something a class name resolves to.
const MP_CODEC: GDScript = preload("res://scripts/mp_codec.gd")
const Terrain: GDScript = preload("res://scripts/endless_terrain.gd")
const Coin: GDScript = preload("res://scripts/coin.gd")
const Player: GDScript = preload("res://scripts/player_controller.gd")
const CrocAI: GDScript = preload("res://scripts/piglet_crocodile_ai.gd")


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	Sentinel.isolate_user_state()
	# WAIT ONE FRAME FIRST. At `_initialize` the SceneTree's own root is not yet
	# inside the tree, so a node added to it never gets `_ready()` and reports a
	# zero `global_transform` — which would make the live-coin check below pass
	# vacuously against a coin that was never actually spawned.
	await process_frame
	var failure: String = await _run_checks()
	if failure.is_empty():
		Sentinel.finish(self)
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
	failure = _check_retired_heart_keys_are_tolerated()
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
	failure = _check_claim_base_value()
	if not failure.is_empty():
		return failure
	failure = _check_terrain_focus_points()
	if not failure.is_empty():
		return failure
	failure = _check_hunter_sync()
	if not failure.is_empty():
		return failure
	failure = _check_acquisition_cue()
	if not failure.is_empty():
		return failure
	failure = _check_captive_parser()
	if not failure.is_empty():
		return failure
	failure = _check_captive_set()
	if not failure.is_empty():
		return failure
	failure = _check_pad_parser()
	if not failure.is_empty():
		return failure
	failure = _check_room_publish()
	if not failure.is_empty():
		return failure
	failure = _check_hero_press_decision()
	if not failure.is_empty():
		return failure
	failure = await _check_host_persist_and_joiner_near_master()
	if not failure.is_empty():
		return failure
	failure = _check_ability_visual_state()
	if not failure.is_empty():
		return failure
	failure = _check_herd_parser()
	if not failure.is_empty():
		return failure
	failure = _check_room_pause()
	if not failure.is_empty():
		return failure
	return _check_voice_chat_tx()


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
	Sentinel.done("avatar_isolation")
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
	Sentinel.done("coin_ids")
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
	Sentinel.done("croc_ids")
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
	Sentinel.done("group_anchor")
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
	Sentinel.done("join_world_sweeps")
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
	mp._receive_state("some-other-member", MpCodec.decode_state(hostile))
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
	mp._receive_state("the-real-master", MpCodec.decode_state(ruling))
	var still_alive: bool = doomed.is_in_group("crocodile")
	doomed.free()
	if still_alive:
		return "the MASTER's join snapshot did not apply its kill list — a joiner still sees crushed crocodiles alive"
	Sentinel.done("kill_list_authority")
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
	Sentinel.done("remote_scent")
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
	mp._resolve_claim(12345, MpCodec.peer_int_id(mp._you), count, value)

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
	Sentinel.done("claim_base_value")
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
	var me: int = MpCodec.peer_int_id(mp._you)

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
	Sentinel.done("confirm_base_is_unforgeable")
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
	Sentinel.done("terrain_focus_points")
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
	     CROC_FLAG_BURROWED's note in mp_codec.gd): today five bits, five
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
	# the protocol rather than trusted. Every CROC_FLAG_* the CODEC declares is
	# a bit the encoder can put on the wire; if the five fields above cannot
	# between them light all of them, a sixth flag has been added and this sweep
	# would round-trip a byte that never contains it — passing while the exact
	# drift it exists to catch ships. Read off the const map so a new bit needs no
	# edit here to be NOTICED, only to be covered — and off `mp_codec.gd`'s map,
	# which is where both halves of the flag byte now live (bead godot-test1-ftn.11).
	var declared: int = 0
	for key: String in MP_CODEC.get_script_constant_map().keys():
		if key.begins_with("CROC_FLAG_"):
			declared |= int(MP_CODEC.get_script_constant_map()[key])
	for bit: int in range(fields.size()):
		sender.set(fields[bit], true)
	var full: int = MpCodec._croc_flags(sender)
	if full != declared:
		return ("the flag sweep drives %d of the declared CROC_FLAG_* mask %d — a bit was added to "
				+ "mp_codec without a field here, so the round-trip below cannot see it") % [full, declared]
	for combo: int in range(1 << fields.size()):
		for bit: int in range(fields.size()):
			sender.set(fields[bit], (combo & (1 << bit)) != 0)
			# The receiver is reset rather than left as the last iteration left it,
			# because BITING is a LATCH by design: the decoder calls _start_bite()
			# when the bit is set and never clears it when it is not (the local
			# animation does that). Carrying it over would fail the sweep for a
			# decoder that is behaving exactly as specified.
			receiver.set(fields[bit], false)
		var sent: int = MpCodec._croc_flags(sender)
		receiver.set_remote_state(Vector3(12.0, 0.0, -3.0), 1.25, sent)
		var back: int = MpCodec._croc_flags(receiver)
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
	Sentinel.done("hunter_sync")
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
	remote.set_remote_state(here, 0.0, MpCodec.CROC_FLAG_CHASING)
	if sound.pings != 1:
		return ("a remote-driven hunter whose first sample says CHASING rang %d pings, expected 1 — "
				+ "the peer is deaf to the master's lock-on") % sound.pings
	remote.set_remote_state(here, 0.0, MpCodec.CROC_FLAG_CHASING)
	remote.set_remote_state(here, 0.0, MpCodec.CROC_FLAG_CHASING)
	if sound.pings != 1:
		return "the remote ping fires per SAMPLE, not per engagement (%d pings over 3 chasing samples)" % sound.pings
	remote.set_remote_state(here, 0.0, 0)
	if sound.pings != 1:
		return "a sample that drops CHASING rang a ping (%d) — only the false->true edge may" % sound.pings
	remote.set_remote_state(here, 0.0, MpCodec.CROC_FLAG_CHASING)
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
	croc.set_remote_state(here, 0.0, MpCodec.CROC_FLAG_CHASING)
	if sound.pings != 0:
		return "a plain crocodile rang the hunter's lock-on ping %d times — the cue is not keyed on the behaviour" % sound.pings
	if sound.hisses != 0 or sound.growls != 0:
		return "a plain crocodile rang the ambusher's hiss (%d) or the boss growl (%d)" % [sound.hisses, sound.growls]

	hunter.free()
	remote.free()
	croc.free()
	quarry.free()
	sound.free()
	Sentinel.done("acquisition_cue")
	return ""


# =============================================================================
# 21. THE ROOM'S CAPTIVE SET (bead godot-test1-3iy.10)
# =============================================================================

## A player that records what the room told it about the captive set, and nothing
## else. In group "player", which is how `MpManager._push_captive_to_player()`
## finds the real one — so this sits on the exact code path the game uses, with no
## signal, no injection and no hard reference.
## A stand-in local player for the captive verb. It is a `Node3D` and not a bare
## `Node` for one reason: it sits in group "player" while later checks drive
## `_on_lobby_peer_joined`, whose join snapshot reads `global_position` off
## whatever answers that group. A bare Node threw there on every run — an error
## that aborted `_send_state_to` and silently sent no snapshot at all (bead
## `godot-test1-llo`). The real player is a `CharacterBody3D`, so this is the
## stub catching up with what it stands in for.
const CAPTIVE_PLAYER_SOURCE := """extends Node3D
var told: Array = []
func set_hero_captive(hero: String, held: bool) -> void:
	told.append([hero, held])
"""

## A lobby that records instead of sending. It SUBCLASSES the real `LobbyClient`
## rather than standing in for it, because `MpManager._lobby` is typed — so this is
## the shipped class with two methods overridden, and a rename on either side is a
## parse error here instead of a silently skipped send.
const LOBBY_STUB_SOURCE := """extends LobbyClient
var relayed: Array = []
var heroes_sent: Array = []
func send_signal_to(to: String, payload: Dictionary) -> void:
	relayed.append([to, payload])
func send_hero(hero: String) -> void:
	heroes_sent.append(hero)
"""


func _lobby_stub() -> Node:
	var script := GDScript.new()
	script.source_code = LOBBY_STUB_SOURCE
	script.reload()
	var node: Node = script.new()
	root.add_child(node)
	return node


func _captive_player() -> Node:
	var script := GDScript.new()
	script.source_code = CAPTIVE_PLAYER_SOURCE
	script.reload()
	var node := Node3D.new()
	node.set_script(script)
	node.add_to_group("player")
	root.add_child(node)
	return node


func _room_manager(you: String) -> Node:
	"""
	An `MpManager` posed as a member of a four-hero room, with no socket and no
	mesh under it.

	THE REAL OBJECT, not a stand-in: every rule under test is enforced inside
	`_apply_captive`, `available_heroes` and `decode_state`, so a stub reproducing
	them would only be testing itself. `_broadcast_reliable()` is a no-op while
	`_rtc` is null, which is what makes this safe to drive without WebRTC.
	"""
	var mp: Node = MPManager.new()
	mp.add_to_group("mp")
	root.add_child(mp)
	mp._state = MPManager.State.IN_ROOM
	mp._you = you
	# THROUGH THE LOBBY CALLBACK, not by writing `_heroes`: the last-holder map a
	# capture is authorized against is written THERE and nowhere else, so a check
	# that posed the room by hand would be testing a state the lobby cannot produce
	# — and would authorize nothing.
	mp._lobby = _lobby_stub()
	mp._on_lobby_heroes({"windman": you, "primm": "bob"},
		["windman", "primm", "teibi", "phoboman"])
	return mp


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


## A fauna manager reduced to the one method `MpManager._receive_herd()` calls,
## in group "fauna" so it is found through the shipped group lookup.
const FAUNA_STUB_SOURCE := """extends Node
var applied: Array = []
func apply_herd_sync(state: Dictionary) -> void:
	applied.append(state)
"""


func _check_herd_parser() -> String:
	"""
	The `herd` verb — the EIGHTH trust boundary (bead godot-test1-6xc), plus the
	authority rule that decides whose giraffes everybody draws.

	THE HONEST PACKETS COME FIRST AND THEY ARE THE POINT: a parser that returned
	`{}` for everything would pass every rejection below while making the buddy's
	screen as empty as it was before this bead.
	"""
	var honest: Dictionary = {
		"t": "herd", "k": 1, "o": Vector3(10.0, 0.0, -4.0), "h": 1.25, "sd": 99,
		"sp": 2.5, "p": Vector3(12.0, 0.0, -4.5), "y": 0.5, "d": 17.5,
	}
	var good: Dictionary = MpCodec.decode_herd(honest)
	if good.is_empty():
		return "decode_herd dropped an honest herd packet"
	for key: String in ["k", "o", "sd", "sp", "p", "d"]:
		if good.get(key, null) != honest[key]:
			return "decode_herd changed %s: %s -> %s" % [key, honest[key], good.get(key, null)]
	if not is_equal_approx(float(good["h"]), 1.25) or not is_equal_approx(float(good["y"]), 0.5):
		return "decode_herd changed an in-range angle (%s)" % str(good)

	# THE ALL-CLEAR must decode to a VALUE and not to the `{}` that means
	# malformed — it is how a master says "my crossing ended" without making every
	# peer wait out its silence timeout.
	var clear: Dictionary = MpCodec.decode_herd({"t": "herd", "k": -1})
	if clear.is_empty() or int(clear.get("k", 0)) != -1:
		return "decode_herd dropped the master's all-clear (%s)" % str(clear)

	# Every kind the fauna manager can build must be accepted, or a species goes
	# permanently invisible to everybody but the master.
	for kind: int in MpCodec.FAUNA_SCRIPT.HERD_BUILDERS.size():
		var packet: Dictionary = honest.duplicate()
		packet["k"] = kind
		if MpCodec.decode_herd(packet).is_empty():
			return "decode_herd refused herd kind %d, which fauna_manager can build" % kind

	# ...and everything a peer that is not speaking this protocol could send.
	var over_kind: int = MpCodec.FAUNA_SCRIPT.HERD_BUILDERS.size()
	var hostile: Array[Dictionary] = [
		{"t": "herd"},                                             # no kind at all
		_herd_with("k", float(over_kind - 1)),                     # kind is a float
		_herd_with("k", over_kind),                                # kind out of range
		_herd_with("k", true),                                     # ...or a bool
		_herd_with("sd", 1.5),                                     # seed is a float
		_herd_with("o", Vector2(1.0, 2.0)),                        # origin is a Vector2
		_herd_with("o", Vector3(NAN, 0.0, 0.0)),                   # NaN origin
		_herd_with("p", Vector3(0.0, INF, 0.0)),                   # infinite centre
		_herd_with("p", Vector3(MpCodec.MAX_PRESENCE_COORD * 2.0, 0.0, 0.0)),
		_herd_with("h", NAN),                                      # NaN heading
		_herd_with("y", "0.5"),                                    # yaw is a string
		_herd_with("sp", -1.0),                                    # walking backwards
		_herd_with("sp", 1.0e30),                                  # ...or at 1e30 m/s
		# JUST OVER THE AMBLE. `sp` is written onto AnimatableBody3D roots every
		# physics tick and Godot derives a RIDER's platform velocity from that
		# delta, so the presence packet's generous 1e4 m/s is not a bound here.
		_herd_with("sp", MpCodec.FAUNA_SCRIPT.WALK_SPEED_MAX + 0.5),
		_herd_with("d", -0.1),                                     # negative distance
		_herd_with("d", 1.0e30),                                   # poisons the stride sine
		_herd_with("d", NAN),
	]
	for packet: Dictionary in hostile:
		if not MpCodec.decode_herd(packet).is_empty():
			return "decode_herd accepted the hostile packet %s" % str(packet)

	# A missing REQUIRED field is malformed here, unlike a presence counter: none
	# of these is a field a later build added, and a half-described herd would be
	# built at the origin facing north on every screen but the master's.
	for key: String in ["o", "h", "sd", "sp", "p", "y", "d"]:
		var truncated: Dictionary = honest.duplicate()
		truncated.erase(key)
		if not MpCodec.decode_herd(truncated).is_empty():
			return "decode_herd accepted a packet with no %s" % key

	# WRAPPED, not bounded: both angles are eased with `lerp_angle` on the far
	# side, where `1e30 + anything small IS 1e30`.
	var spun: Dictionary = MpCodec.decode_herd(_herd_with("y", 1.0e6))
	if spun.is_empty() or float(spun["y"]) < 0.0 or float(spun["y"]) >= TAU:
		return "decode_herd did not wrap a huge yaw into [0, TAU) (%s)" % str(spun)

	# ...and both ends of the amble are ACCEPTED, or the honest herds the fauna
	# manager actually rolls would be refused and the buddy would see nothing.
	for edge: float in [MpCodec.FAUNA_SCRIPT.WALK_SPEED_MIN, MpCodec.FAUNA_SCRIPT.WALK_SPEED_MAX]:
		if MpCodec.decode_herd(_herd_with("sp", edge)).is_empty():
			return "decode_herd refused %.1f m/s, which fauna_manager rolls" % edge

	# The verb has to be budgeted like every other one `_receive_mesh_verb`
	# dispatches — "only the master sends this" is not a rate bound.
	if not MPManager.VERB_BUDGET_PER_SEC.has("herd"):
		return "the herd verb has no VERB_BUDGET_PER_SEC row"

	# AUTHORITY. Only the master's herd is drawn, and a packet arriving while WE
	# are the master is dropped too — otherwise our own herd is driven by an echo.
	var fauna_script := GDScript.new()
	fauna_script.source_code = FAUNA_STUB_SOURCE
	fauna_script.reload()
	var fauna: Node = fauna_script.new()
	fauna.add_to_group("fauna")
	root.add_child(fauna)
	var mp: Node = _room_manager("us")
	mp._master = "themaster"
	mp._receive_herd("someoneelse", honest)
	if not (fauna.get("applied") as Array).is_empty():
		fauna.queue_free()
		mp.queue_free()
		return "a NON-MASTER's herd packet was applied — any member could put a herd on every screen"
	mp._receive_herd("themaster", honest)
	if (fauna.get("applied") as Array).size() != 1:
		fauna.queue_free()
		mp.queue_free()
		return "the master's herd packet was NOT applied — this check measured nothing"
	mp._master = "us"
	mp._receive_herd("us", honest)
	if (fauna.get("applied") as Array).size() != 1:
		fauna.queue_free()
		mp.queue_free()
		return "we applied a herd packet while we were the master — our own herd would be driven by an echo"
	fauna.queue_free()
	mp.queue_free()
	Sentinel.done("herd_parser")
	return ""


func _herd_with(key: String, value: Variant) -> Dictionary:
	"""One honest herd packet with a single field replaced — see _check_herd_parser."""
	var packet: Dictionary = {
		"t": "herd", "k": 1, "o": Vector3(10.0, 0.0, -4.0), "h": 1.25, "sd": 99,
		"sp": 2.5, "p": Vector3(12.0, 0.0, -4.5), "y": 0.5, "d": 17.5,
	}
	packet[key] = value
	return packet


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


func _check_captive_set() -> String:
	"""
	The room's captive set, driven through the real manager.

	WHAT MAKES ONE BROADCAST VERB SAFE, claim by claim — every one of them is a
	line a well-meaning simplification would delete, and every one of them is the
	difference between "a hostile member can bench itself" and "a hostile member
	can end everyone's run with one packet":

	  1. THE HOLDER RULE. A capture is a fact about the hero the sender was WALKING
	     AS, so the lobby's own `_heroes` map is the authorization: a member naming
	     somebody else's hero is naming a body it cannot have lost, and is refused.
	  2. ...AND IT IS NOT A LIFETIME CAP. A peer that was reassigned after losing
	     one hero may lose the NEXT one too — the ordinary path in a two- or
	     three-player room — and every peer must record it, or the room's sets
	     diverge and the ending never arrives for anybody.
	  3. THE POOL IS THE WHITELIST, and an assertion cannot be re-made.
	  4. RELEASE IS OPEN, deliberately: liberation is performed by whoever walked
	     into the cell, which is never the captive's holder.
	  5. THE MIRROR REACHES THE PLAYER, which is the half that makes the set mean
	     anything: the roster, the picker and the world-level game over all read
	     the player's copy.
	  6. THE PICKER IS TOLD. `mp_ui` repaints on `heroes_changed` and on nothing
	     else, and captivity changes what may be pressed without changing the
	     lobby's assignment map.
	  7. THE VERB IS DISPATCHED AND METERED. A decoder nothing routes to is dead
	     code, and a state-mutating verb with no budget is an amplifier.
	  8. THE PICKER NEVER OFFERS A CAPTIVE HERO, our own included.
	  9. `claimable_hero()` skips captives, which is what "reassign first" asks.
	 10. THE JOIN SNAPSHOT is the MASTER's whole set and nobody else's — a replay
	     cannot be authorized by claim 1, because the peer who lost that hero has
	     usually been reassigned and holds something else by then.
	 11. A LIBERATION THAT OVERTOOK ITS CAPTURE still wins — the two verbs come from
	     different senders and nothing orders them.
	 12. ENTERING A ROOM RESETS the local mirror: a room's roster is the room's.
	"""
	var player: Node = _captive_player()
	var mp: Node = _room_manager("me")
	var repaints: Array[int] = [0]
	mp.heroes_changed.connect(func(_h: Dictionary, _p: Array) -> void: repaints[0] += 1)

	# --- 1/5/6. bob holds primm and reports him taken - AND THE LOBBY HAS ALREADY
	# TAKEN PRIMM OFF HIM. That is the ordering the two transports make possible:
	# `SetHero` releases the captured hero as it grants the replacement, and the
	# `heroes` frame carrying that can beat the `cap` packet to any peer. Authorized
	# against the LAST holder, this is still bob's capture to report; authorized
	# against the live map it is dropped, and that peer's captive set is wrong for
	# the rest of the run.
	mp._on_lobby_heroes({"windman": "me", "teibi": "bob"},
		["windman", "primm", "teibi", "phoboman"])
	# Counted from HERE, because a `heroes` frame legitimately repaints too — what
	# is measured is that the CAPTURE adds one of its own.
	var before_first: int = repaints[0]
	mp._receive_captive("bob", {"t": "cap", "h": "primm", "c": true})
	if not mp.is_hero_captive("primm"):
		return "a capture whose reassignment broadcast arrived FIRST was dropped — the two "\
			+ "transports cannot be ordered, so this peer's set is now permanently wrong"
	if player.told != [["primm", true]]:
		return "the room's capture did not reach the player's own set (%s)" % str(player.told)
	if repaints[0] != before_first + 1:
		return "a capture emitted no heroes_changed — the picker repaints on that signal and "\
			+ "on nothing else, so it would keep offering a hero who is in a cell"

	# --- 1 (the refusal). carl holds nothing, and may not name teibi.
	mp._receive_captive("carl", {"t": "cap", "h": "teibi", "c": true})
	if mp.is_hero_captive("teibi"):
		return "a member who does not hold teibi reported him taken and was believed — one "\
			+ "packet then benches any teammate, or four end every run in the room"

	# --- 3. the pool is the whitelist, and an assertion cannot be re-made.
	#
	# CARL REALLY IS THE HOLDER of this name, so the holder rule does not answer for
	# the whitelist and the two are measured separately: the lobby is trusted about
	# WHO holds a hero, and this is the room's own list of which heroes exist.
	mp._on_lobby_heroes({"windman": "me", "teibi": "bob", "nobody_by_that_name": "carl"},
		["windman", "primm", "teibi", "phoboman"])
	mp._receive_captive("carl", {"t": "cap", "h": "nobody_by_that_name", "c": true})
	if mp.is_hero_captive("nobody_by_that_name"):
		return "a hero outside the lobby's pool was written into the captive set"

	# --- 2. bob was reassigned to teibi, and loses that one too.
	#
	# THE CASE A ONE-PER-PEER BOUND GETS WRONG, and it is the ordinary path rather
	# than an exotic one: bob was reassigned to teibi above, and losing THAT hero
	# too is what a two- or three-player room does all evening.
	mp._receive_captive("bob", {"t": "cap", "h": "teibi", "c": true})
	if not mp.is_hero_captive("teibi"):
		return "a peer that was reassigned after one capture could not report losing the "\
			+ "hero it was reassigned TO — the room's sets diverge from that grab onward"

	# --- 4. release is open to anybody, because liberation is.
	player.told.clear()
	mp._receive_captive("dave", {"t": "cap", "h": "primm", "c": false})
	if mp.is_hero_captive("primm"):
		return "a liberation by somebody other than the captive's holder was refused — no "\
			+ "hero could ever be freed, since a cell is walked into by a rescuer"
	if player.told != [["primm", false]]:
		return "the liberation did not reach the player's own set (%s)" % str(player.told)

	# --- 7. the dispatch arm, both transports, and the budget on both.
	if not MPManager.VERB_BUDGET_PER_SEC.has("cap"):
		return "the cap verb has no rate budget — a state-mutating verb with none is an amplifier"
	var budget: int = int(MPManager.VERB_BUDGET_PER_SEC["cap"])
	for spend: int in budget:
		if not mp._verb_rate_ok("eve", "cap"):
			return "the cap budget refused spend %d of its own %d" % [spend, budget]
	if mp._verb_rate_ok("eve", "cap"):
		return "the cap budget of %d let a peer spend %d in one second" % [budget, budget + 1]
	if MpCodec.packet_kind({"t": "cap", "h": "primm", "c": true}) != "cap":
		return "a cap packet does not identify itself as a verb — it would decode as presence"
	# THE RELEASE TOMBSTONE IS CLEARED BETWEEN THESE SUB-CLAIMS, deliberately and
	# with its own claim (11) to itself. It refuses a capture that arrives within
	# RELEASE_GRACE_MSEC of a liberation of the same hero — which every re-capture
	# below is, because a check runs in microseconds and the honest gap is a lobby
	# round trip plus a whole hunter beat. Leaving it armed would make claims 7 and
	# 10 measure the clock instead of the rule they are about.
	mp._released_msec.clear()
	mp._receive_mesh_verb("carl", "cap", {"t": "cap", "h": "primm", "c": true})
	if mp.is_hero_captive("primm"):
		return "the dispatch skipped the holder rule — carl has never held primm"
	mp._receive_mesh_verb("bob", "cap", {"t": "cap", "h": "primm", "c": true})
	if not mp.is_hero_captive("primm"):
		return "the cap verb is decoded but `_receive_mesh_verb` routes it nowhere"

	# ...and the SECOND TRANSPORT, which exists because `_broadcast_reliable()`
	# writes only to peers whose data channel is open and ICE takes seconds. Same
	# parser, same rule, same function — only the wire differs.
	mp._receive_captive("bob", {"t": "cap", "h": "primm", "c": false})
	mp._released_msec.clear()  # ...see above.
	mp._on_lobby_relay("bob", {"mp": "cap", "h": "primm", "c": true})
	if not mp.is_hero_captive("primm"):
		return "a cap relayed over the LOBBY was dropped — a peer still negotiating ICE "\
			+ "when a hero is taken never learns it, and offers a body that is in a cell"
	# ...and the relay is metered on the same budget, because a relayed packet is
	# peer input like any other. Driven with a sender that holds nothing, so every
	# one of these is refused on its merits and only the SPEND is being measured.
	for spend: int in budget:
		mp._on_lobby_relay("gary", {"mp": "cap", "h": "primm", "c": true})
	if mp._verb_rate_ok("gary", "cap"):
		return "the relayed cap spent none of the verb budget — the second transport is an "\
			+ "unmetered door into a state-mutating verb"
	# --- 8. the picker never offers a captive hero, ours included.
	#
	# OUR OWN IS THE SHARP CASE and it is the one measured: `available_heroes()`
	# lists the hero we already hold unconditionally ("re-picking what you have is a
	# no-op"), so a captive filter that only looked at the unclaimed heroes would
	# still offer the body that was just taken off us.
	# DRIVEN THROUGH `report_hero_captured()`, the local entry point, so the SENDER
	# is held to the same gate every receiver is: same whitelist, same holder rule,
	# same mirror, same repaint. A local path that wrote `_captives` directly would
	# be a second copy of the rules, and the copy is where they drift.
	player.told.clear()
	var before: int = repaints[0]
	mp.report_hero_captured("windman")
	if not mp.is_hero_captive("windman"):
		return "we could not report our own hero taken"
	if player.told != [["windman", true]] or repaints[0] == before:
		return "our own capture skipped the shared gate — it reached the player as %s and "\
			% str(player.told) + "repainted the picker %d times" % (repaints[0] - before)
	mp.report_hero_captured("phoboman")
	if mp.is_hero_captive("phoboman"):
		return "we reported a hero we do not hold as taken and believed ourselves — the "\
			+ "sender must go through the same holder rule the receivers do"
	if mp.available_heroes().has("windman"):
		return "the picker offered windman, who is in a cell and is the hero we hold"
	if not mp.available_heroes().has("phoboman"):
		return "the picker offers nothing at all — claim 8 would pass with the roster empty"

	# --- 9. the reassignment candidate.
	#
	# THE STATE A REASSIGNMENT LEAVES BEHIND is already in place and it is the only
	# one in which the captive filter here matters at all: `SetHero` released bob's
	# claim on primm when it moved him to teibi, so primm is IN A CELL AND UNCLAIMED
	# — the one shape that looks free to a filter that only asks the lobby, and pool
	# order would offer him before phoboman.
	#
	# Only phoboman is genuinely free, so that is what a bench asks for; two peers
	# racing therefore ask the lobby for the SAME hero, which is what makes
	# `server/room.go`'s room lock the thing that decides between them.
	if mp.claimable_hero() != "phoboman":
		return "claimable_hero() answered '%s', expected the one free unclaimed hero" \
			% mp.claimable_hero()
	mp._on_lobby_heroes({"windman": "me", "teibi": "bob", "phoboman": "frank"},
		["windman", "primm", "teibi", "phoboman"])
	mp._receive_captive("frank", {"t": "cap", "h": "phoboman", "c": true})
	if mp.claimable_hero() != "":
		return "claimable_hero() answered '%s' with every hero held or in a cell — the "\
			% mp.claimable_hero() + "prison role would never be reached"
	if mp.request_reassignment():
		return "request_reassignment() claimed a hero out of an empty room"

	# --- 10. the join snapshot: absolute values, master only, hostile input.
	if mp.captive_heroes() != ["windman", "primm", "teibi", "phoboman"]:
		return "the snapshot asserts %s, expected the room's whole set in pool order" \
			% str(mp.captive_heroes())
	var base: Dictionary = {
		"cc": 0.0, "ls": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0, "ids": [],
	}
	var honest: Dictionary = base.duplicate()
	honest["cap"] = ["primm"]
	var parsed: Dictionary = MpCodec.decode_state(honest)
	if parsed.is_empty() or parsed.get("cap", []) != ["primm"]:
		return "decode_state dropped an honest captive list (%s)" % str(parsed)
	# MISSING IS NOT MALFORMED — an older peer is still worth its position.
	if MpCodec.decode_state(base).is_empty():
		return "decode_state now requires the cap field, so an older peer's snapshot is lost"
	var bad_caps: Array = [
		"primm",                                          # not an array
		[42],                                             # not a string
		[""],                                             # an empty name
		["x".repeat(MpCodec.MAX_HERO_NAME + 1)],        # an unbounded name
	]
	var too_long: Array[String] = []
	for i: int in MpCodec.MAX_STATE_CAPTIVES + 1:
		too_long.append("primm")
	bad_caps.append(too_long)
	for cap: Variant in bad_caps:
		var hostile: Dictionary = base.duplicate()
		hostile["cap"] = cap
		if not MpCodec.decode_state(hostile).is_empty():
			return "decode_state accepted the hostile captive list %s" % str(cap)

	# ...and the replay is the MASTER's alone. Driven through `_receive_state`, the
	# real merge, so a path that wrote the set straight into `_captives` would not
	# satisfy this by accident.
	var fresh: Node = _room_manager("me")
	fresh._master = "themaster"
	var snapshot: Dictionary = MpCodec.decode_state(honest)
	fresh._receive_state("stranger", snapshot)
	if fresh.is_hero_captive("primm"):
		return "a non-master's join snapshot wrote the room's captive set — every member "\
			+ "could then bench the whole roster for a joiner"
	fresh._receive_state("themaster", snapshot)
	if not fresh.is_hero_captive("primm"):
		return "the master's join snapshot was ignored — a joiner walks into a room whose "\
			+ "cells it cannot see"

	# --- 11. a liberation that OVERTOOK its capture still wins.
	#
	# The two verbs come from different senders — the peer who lost the hero, and
	# whoever walked into his cell — and reliable delivery orders one sender's
	# packets, not two. A third peer that saw the rescue first used to drop it (that
	# hero was not in its set yet) and then accept the capture behind it, locking a
	# hero up on one screen for the rest of the run with nobody able to free him a
	# second time. Driven in exactly that order.
	# TEIBI, WHOM THIS PEER HAS NEVER HEARD OF, and that is the whole case: the
	# release arrives for a hero that is not in our set, so the branch that has to
	# remember it is the one that is about to return "nothing changed". Run against
	# a hero we already hold captive, the release lands the ordinary way and proves
	# nothing about the ordering at all.
	fresh._on_lobby_heroes({"teibi": "bob"}, ["windman", "primm", "teibi", "phoboman"])
	fresh._receive_captive("carl", {"t": "cap", "h": "teibi", "c": false})
	fresh._receive_captive("bob", {"t": "cap", "h": "teibi", "c": true})
	if fresh.is_hero_captive("teibi"):
		return "a liberation that arrived BEFORE the capture it undoes was dropped, and the "\
			+ "stale capture behind it stuck — teibi is now in a cell nobody can open"

	# ...and the SNAPSHOT honours the same guard. A joiner can hear the rescuer's
	# release before the master's picture of the room reaches it, and importing over
	# that would resurrect a capture every incumbent has already forgotten — on the
	# one peer with no way to notice.
	var stale: Dictionary = base.duplicate()
	stale["cap"] = ["teibi"]
	fresh._receive_state("themaster", MpCodec.decode_state(stale))
	if fresh.is_hero_captive("teibi"):
		return "the master's snapshot resurrected a hero the room had already freed — the "\
			+ "replay path skips the release guard the live verb goes through"

	# --- 12. entering a room resets the local mirror to the ROOM's.
	#
	# `join()` unwinds through `leave()`, which deliberately leaves the player's own
	# captive set alone (a leave is not a liberation), so without this a host walks
	# into a shared world holding a solo run's captures that its manager knows
	# nothing about. Driven through the real `welcome` callback.
	player.told.clear()
	# `lobby_only` BEFORE the callback: `welcome` normally ends in `_setup_mesh()`,
	# which asks the lobby socket for /ice — and this manager has no socket. The
	# real relay-only mode stops exactly there, so this is the shipped path and not
	# a hole poked for the check. (Without it the run still printed SELFCHECK OK
	# while throwing on a null `_lobby` — a runtime error nothing reads.)
	fresh.lobby_only = true
	fresh._on_lobby_joined("me", "ROOM01", "me", [{"id": "me", "name": "me"}])
	var cleared: Dictionary = {}
	for entry: Variant in player.told:
		var pair: Array = entry as Array
		if bool(pair[1]):
			return "entering a room MARKED %s captive" % str(pair[0])
		cleared[String(pair[0])] = true
	if cleared.size() != Player.CHARACTERS.size():
		return "entering a room cleared %d of the player's %d heroes — a solo run's captures "\
			% [cleared.size(), Player.CHARACTERS.size()] + "follow the player into a room the "\
			+ "manager knows nothing about"

	fresh.free()
	player.free()
	mp.free()
	Sentinel.done("captive_set")
	return ""


# =============================================================================
# 22. THE MASTER'S ROOM PUBLISH (bead godot-test1-3iy.10)
# =============================================================================

func _relayed_rooms(mp: Node) -> int:
	"""How many `room` publishes the stub lobby has been handed. See claim 7b."""
	var count: int = 0
	for entry: Variant in (mp._lobby.relayed as Array):
		var payload: Dictionary = (entry as Array)[1] as Dictionary
		if String(payload.get("mp", "")) == "room":
			count += 1
	return count


func _check_room_publish() -> String:
	"""
	The one verb that carries the two values a room may never disagree about.

	  1. THE PARSER, against hostile packets — the sixth trust boundary, and the
	     first one whose payload drives a COUNTDOWN the player is watching.
	  2. MASTER ONLY. It is applied WHOLESALE, so a stranger's copy would let any
	     member rewrite the room's cells and end its break-out.
	  3. CONVERGENCE BOTH WAYS. A capture the master has and we do not is the join
	     gap this verb exists for; a release the master has and we do not is the
	     same gap with the packets the other way round.
	  4. ...WITHOUT UNDOING A FRESH LOCAL ASSERTION. The master's picture is up to
	     ROOM_SYNC_HZ old, so adopting it flat would erase a capture we applied a
	     moment ago and the master would put it back on its next publish — a flap
	     at the publish rate.
	  5. THE JOIN GAP ITSELF, measured: a member whose mesh is not up is sent the
	     set over the LOBBY RELAY. That is the hole the per-hero verb cannot reach,
	     because the captor does not know that member exists yet.
	  6. THE CLOCK AND THE VERDICT reach the player.
	  7. Dispatched, metered, and published on the tick.
	"""
	# --- 1. the parser.
	var honest: Dictionary = {"t": "room", "cap": ["primm"], "cd": 12.5, "co": 0}
	var parsed: Dictionary = MpCodec.decode_room(honest)
	if parsed.get("cap", []) != ["primm"] or absf(float(parsed.get("cd", -1.0)) - 12.5) > 0.001 \
			or int(parsed.get("co", -1)) != 0:
		return "decode_room dropped an honest publish (%s)" % str(parsed)
	# EVERY `co` AN OLDER MASTER CAN PRODUCE, swept rather than spot-checked. This
	# build always sends 0 and reads none of them (owner veto 2026-09-01, bead
	# `godot-test1-ueg`), but `build_version` refuses to reload a peer that is in a
	# room, so a master on the pre-veto build is a state that really happens and its
	# three verdicts must still decode — the packet is the captive-set repair
	# channel and a drop costs the room its cells.
	for outcome: int in 3:
		var probe: Dictionary = {"t": "room", "cap": [], "cd": 1.0, "co": outcome}
		if int(MpCodec.decode_room(probe).get("co", -1)) != outcome:
			return "decode_room dropped the verdict %d, which an older master can send" % outcome
	var over_long: Array[String] = []
	for i: int in MpCodec.MAX_STATE_CAPTIVES + 1:
		over_long.append("primm")
	var hostile: Array[Dictionary] = [
		{"t": "room", "cd": 1.0, "co": 0},                                  # no set
		{"t": "room", "cap": "primm", "cd": 1.0, "co": 0},                  # set is a string
		{"t": "room", "cap": [7], "cd": 1.0, "co": 0},                      # entry is a number
		{"t": "room", "cap": [""], "cd": 1.0, "co": 0},                     # empty name
		{"t": "room", "cap": ["x".repeat(MpCodec.MAX_HERO_NAME + 1)], "cd": 1.0, "co": 0},
		{"t": "room", "cap": over_long, "cd": 1.0, "co": 0},
		{"t": "room", "cap": [], "co": 0},                                  # no clock
		{"t": "room", "cap": [], "cd": "soon", "co": 0},                    # clock is a string
		{"t": "room", "cap": [], "cd": NAN, "co": 0},
		{"t": "room", "cap": [], "cd": INF, "co": 0},
		{"t": "room", "cap": [], "cd": -1.0, "co": 0},
		{"t": "room", "cap": [], "cd": MpCodec.MAX_CUSTODY_SECONDS + 1.0, "co": 0},
		{"t": "room", "cap": [], "cd": 1.0},                                # no verdict
		# NOTE: `co: 3` is NOT here. An unreadable verdict is folded to
		# `CUSTODY_VERDICT_MAX` (FAILED) rather than dropped, so an older master's
		# retired OVERTAKEN does not cost the room the captive-set repair this
		# packet also carries — check 8 (e) owns that assertion in both directions.
		{"t": "room", "cap": [], "cd": 1.0, "co": -1},
		{"t": "room", "cap": [], "cd": 1.0, "co": NAN},
	]
	for packet: Dictionary in hostile:
		if not MpCodec.decode_room(packet).is_empty():
			return "decode_room accepted the hostile publish %s" % str(packet)

	var player: Node = _captive_player()
	var mp: Node = _room_manager("me")
	mp._master = "themaster"

	# --- 2. master only.
	mp._receive_mesh_verb("stranger", "room", {"t": "room", "cap": ["teibi"], "cd": 5.0, "co": 0})
	if mp.is_hero_captive("teibi"):
		return "a non-master's room publish rewrote the captive set — any member could then "\
			+ "put the whole roster in cells, which is every peer's game over"

	# --- 3. convergence, forwards.
	mp._receive_mesh_verb("themaster", "room", {"t": "room", "cap": ["teibi"], "cd": 5.0, "co": 0})
	if not mp.is_hero_captive("teibi"):
		return "the master's publish did not repair a capture we never heard — that is the "\
			+ "join gap this verb exists for, and nothing else in the protocol closes it"
	if player.told.is_empty() or player.told[-1] != ["teibi", true]:
		return "the repaired capture did not reach the player's own set (%s)" % str(player.told)

	# --- 3b. ...and backwards, once the local capture is no longer fresh.
	mp._captured_msec["teibi"] = Time.get_ticks_msec() - MPManager.RELEASE_GRACE_MSEC - 1
	mp._receive_mesh_verb("themaster", "room", {"t": "room", "cap": [], "cd": 5.0, "co": 0})
	if mp.is_hero_captive("teibi"):
		return "the master's publish did not repair a liberation we never heard — a freed "\
			+ "hero stays in a cell on this screen for the room's life"

	# --- 4. a FRESH local assertion survives a stale publish, both directions.
	mp._on_lobby_heroes({"windman": "me", "phoboman": "carl"},
		["windman", "primm", "teibi", "phoboman"])
	mp._receive_captive("carl", {"t": "cap", "h": "phoboman", "c": true})
	if not mp.is_hero_captive("phoboman"):
		return "the fresh-capture setup failed, so claim 4 proves nothing"
	mp._receive_mesh_verb("themaster", "room", {"t": "room", "cap": [], "cd": 5.0, "co": 0})
	if not mp.is_hero_captive("phoboman"):
		return "a publish older than our own capture undid it — the master puts it back on "\
			+ "its next publish, so the cell frame flaps at the publish rate"
	mp._receive_captive("carl", {"t": "cap", "h": "phoboman", "c": false})
	mp._receive_mesh_verb("themaster", "room",
		{"t": "room", "cap": ["phoboman"], "cd": 5.0, "co": 0})
	if mp.is_hero_captive("phoboman"):
		return "a publish older than our own liberation resurrected it — the same flap, the "\
			+ "other way round"

	# --- 5. THE JOIN GAP. A master, a member whose mesh is not up, and the relay.
	var host: Node = _room_manager("me")
	host._master = "me"
	host._members = [{"id": "me", "name": "me"}, {"id": "joiner", "name": "joiner"}]
	host._receive_captive("bob", {"t": "cap", "h": "primm", "c": true})
	var lobby: Node = host._lobby
	lobby.relayed.clear()
	host._send_room_state()
	var reached: bool = false
	for entry: Variant in lobby.relayed:
		var pair: Array = entry as Array
		var payload: Dictionary = pair[1] as Dictionary
		if String(pair[0]) == "joiner" and String(payload.get("mp", "")) == "room" \
				and (payload.get("cap", []) as Array).has("primm"):
			reached = true
	if not reached:
		return "the master's publish never reached a peer whose mesh is still negotiating — "\
			+ "a capture landing in the join gap reaches neither the snapshot nor the `cap` "\
			+ "packet, and nothing else would ever correct it"

	# --- 6. THE RETIRED HALF IS A SHAPE AND NOTHING ELSE (owner veto 2026-09-01,
	# bead `godot-test1-ueg`). The master publishes `cd`/`co` as zeros, and a packet
	# carrying an OLDER master's real clock and verdict must still land its captive
	# set rather than being read as an instruction. Both directions asserted here,
	# because "we ignore it" is only true if the encoder stopped sending it too.
	host._lobby.relayed.clear()
	host._room_accum = 0.0
	host._process(1.0 / MPManager.ROOM_SYNC_HZ + 0.01)
	for entry: Variant in host._lobby.relayed:
		var sent: Dictionary = (entry as Array)[1] as Dictionary
		if String(sent.get("mp", "")) != "room":
			continue
		if not sent.has("cd") or not sent.has("co"):
			return "the master dropped `cd`/`co` off the wire — `decode_room()` drops a "\
				+ "packet missing either, so a mixed-build room stops repairing its cells"
		if absf(float(sent["cd"])) > 0.0 or int(sent["co"]) != 0:
			return "the master published a live clock/verdict (%s) — the break-out is gone"\
				% str(sent)
	mp._receive_mesh_verb("themaster", "room", {"t": "room", "cap": ["teibi"], "cd": 7.25, "co": 2})
	if not mp.is_hero_captive("teibi"):
		return "an older master's publish carrying a real clock and verdict lost its "\
			+ "captive set — the retired fields must cost the packet nothing"
	mp._captured_msec["teibi"] = Time.get_ticks_msec() - MPManager.RELEASE_GRACE_MSEC - 1
	mp._receive_mesh_verb("themaster", "room", {"t": "room", "cap": [], "cd": 0.0, "co": 0})

	# --- 7. dispatched on both transports, metered, and actually published.
	if MpCodec.packet_kind({"t": "room", "cap": [], "cd": 1.0, "co": 0}) != "room":
		return "a room packet does not identify itself as a verb"
	if not MPManager.VERB_BUDGET_PER_SEC.has("room"):
		return "the room verb has no rate budget — it is applied wholesale, which is the "\
			+ "most amplified verb in the file"
	var before: int = player.told.size()
	mp._on_lobby_relay("themaster", {"mp": "room", "cap": ["primm"], "cd": 3.5, "co": 0})
	if player.told.size() == before or player.told[-1] != ["primm", true]:
		return "a room publish relayed over the LOBBY was dropped — that is the only wire "\
			+ "that reaches a peer whose mesh is still negotiating"
	var budget: int = int(MPManager.VERB_BUDGET_PER_SEC["room"])
	for spend: int in budget:
		mp._on_lobby_relay("themaster", {"mp": "room", "cap": [], "cd": 3.5, "co": 0})
	if mp._verb_rate_ok("themaster", "room"):
		return "the relayed room publish spent none of the verb budget"

	# --- 7b. it goes out ON THE TICK, and the relay leg goes out ONLY ON A CHANGE.
	#
	# THE SECOND HALF IS THE LOBBY'S STALL RULE, not tidiness. `server/room.go` will
	# not act on a quorum of stall votes while the lobby has heard anything from the
	# master inside `stallMasterSilence` — so a master relaying this twice a second
	# looks alive to the LOBBY however dead its heartbeat is, and a throttled tab can
	# never be deposed. `mp_e2e.sh`'s stall phase found that; this is the same claim
	# in one process.
	host._lobby.relayed.clear()
	host._room_accum = 0.0
	host._receive_captive("bob", {"t": "cap", "h": "primm", "c": false})
	host._process(1.0 / MPManager.ROOM_SYNC_HZ + 0.01)
	if _relayed_rooms(host) == 0:
		return "the master published nothing on its own tick — the repair channel only "\
			+ "exists if something drives it"
	host._lobby.relayed.clear()
	for tick: int in 4:
		host._room_accum = 0.0
		host._process(1.0 / MPManager.ROOM_SYNC_HZ + 0.01)
	# COUNTED BY VERB, because the heartbeat rides this same socket and is SUPPOSED
	# to: it is the one frame a stalled tab stops sending, which is what makes the
	# vote possible at all. What must go quiet is this publish.
	if _relayed_rooms(host) != 0:
		return "an unchanged room state kept relaying over the LOBBY (%d frames) — the "\
			% _relayed_rooms(host) + "lobby then hears from the master constantly and a "\
			+ "stalled host can never be voted out"

	# --- 7c. A NEW MEMBER RE-OPENS THE RELAY, even with nothing changed.
	#
	# The digest is one string for the whole room, so a peer that joins after the
	# last change is skipped by every unchanged publish afterwards.
	host._lobby.relayed.clear()
	host._on_lobby_peer_joined("latecomer", "latecomer")
	host._room_accum = 0.0
	host._process(1.0 / MPManager.ROOM_SYNC_HZ + 0.01)
	if _relayed_rooms(host) == 0:
		return "a peer that joined after the last change was never sent the room state — "\
			+ "the digest is global, so every later publish skips it too"

	# --- 8. the auto-claim waits for the join to settle.
	var joiner: Node = _room_manager("me")
	joiner._first_member = false
	joiner._join_applied = false
	joiner._expected_snapshots = 1
	joiner._join_wait = 0.0
	joiner._heroes = {}
	joiner._lobby.heroes_sent.clear()
	joiner._auto_claim_hero()
	if not joiner._lobby.heroes_sent.is_empty():
		return "a joiner claimed '%s' before any snapshot arrived — `_captives` is empty on "\
			% str(joiner._lobby.heroes_sent) + "the `welcome` frame, so that can be a hero the "\
			+ "room has in a cell, played in the field on one screen and locked up on the rest"
	# ...and the snapshot's ARRIVAL is what releases it. Driven through
	# `_on_lobby_relay`, the real wire, because the re-drive is the half that can be
	# missing: the gate above is worthless if nothing calls the claim afterwards.
	joiner._on_lobby_relay("bob", {
		"mp": "state", "cc": 0.0, "ls": 0.0, "dd": 0.0,
		"px": 0.0, "py": 0.0, "pz": 0.0, "ids": [],
	})
	if joiner._lobby.heroes_sent.is_empty():
		return "the snapshot landed and the auto-claim was never re-driven — the joiner "\
			+ "waits for a settle nothing acts on and ends up with no hero at all"
	# ...and so is the deadline, for a room whose snapshots never come.
	var stranded: Node = _room_manager("me")
	stranded._first_member = false
	stranded._expected_snapshots = 1
	stranded._join_wait = 0.0
	stranded._heroes = {}
	stranded._lobby.heroes_sent.clear()
	stranded._tick_join_wait(MPManager.JOIN_SNAPSHOT_WAIT + 0.1)
	if stranded._lobby.heroes_sent.is_empty():
		return "the join deadline passed and the auto-claim never fired — a room whose "\
			+ "snapshots never arrive must still hand this player a hero"
	stranded.free()

	joiner.free()
	host.free()
	player.free()
	mp.free()
	Sentinel.done("room_publish")
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


# =============================================================================
# 23. THE HERO PRESS DECISION (bead godot-test1-4zw)
# =============================================================================

func _check_hero_press_decision() -> String:
	"""
	R and 1-4 both route through `player_controller.decide_switch()`, and in a
	room the distance between its three verdicts is the distance between taking a
	teammate's body, asking the lobby politely, and a dead key. It is static and
	pure precisely so it can be pinned here, with no room, no lobby and no player
	in a tree.
	"""
	var all_four: Array = [0, 1, 2, 3]
	var cases: Array = [
		# [index, current, available, claimable, holder, expected, what it pins]
		[2, 0, all_four, all_four, "", Player.SWITCH_LOCAL,
			"solo, every free hero is in the hand and switches on the spot"],
		[0, 0, all_four, all_four, "", Player.SWITCH_REFUSE,
			"the hero we already are is refused, never re-claimed"],
		[99, 0, all_four, all_four, "", Player.SWITCH_REFUSE,
			"an out-of-range index is refused before it indexes CHARACTERS"],
		[-1, 0, all_four, all_four, "", Player.SWITCH_REFUSE,
			"a negative index is refused"],
		[2, 0, [0], all_four, "", Player.SWITCH_CLAIM,
			"in a room, a free hero NOBODY holds is claimed through the lobby"],
		[1, 0, [0], all_four, "somebody-else", Player.SWITCH_REFUSE,
			"a hero a teammate holds stays refused — nothing is ever stolen"],
		[3, 0, [0], [0, 1, 2], "", Player.SWITCH_REFUSE,
			"a CAPTIVE hero is unreachable even though nobody holds him"],
		[2, 0, [0], [], "", Player.SWITCH_REFUSE,
			"with no lobby to ask, a hero outside the hand is simply refused"],
	]
	for case in cases:
		var got: int = Player.decide_switch(case[0], case[1], case[2], case[3], case[4])
		if got != case[5]:
			return "decide_switch(%d, %d, %s, %s, \"%s\") == %d, expected %d — %s" % [
				case[0], case[1], str(case[2]), str(case[3]), case[4],
				got, case[5], case[6]
			]

	# `hero_holder()` — the query the decision reads, against the acceptance
	# criterion's own room: we hold windman, "bob" holds primm, teibi and
	# phoboman are unheld. Posed through the lobby callback, like every other
	# room check here, so it is the state the lobby can actually produce.
	var mp: Node = _room_manager("me")
	if mp.hero_holder("windman") != "me" or mp.hero_holder("primm") != "bob":
		return "hero_holder() did not name the two holders the room has"
	if not mp.hero_holder("teibi").is_empty() \
			or not mp.hero_holder("phoboman").is_empty():
		return "hero_holder() named a holder for a hero nobody holds"
	if not mp.hero_holder("gandalf").is_empty():
		return "hero_holder() named a holder for a hero the room has never heard of"

	# ...and the claim the CLAIM verdict makes reaches the lobby as a hero
	# request, changing NOTHING locally: the body moves when the `heroes`
	# broadcast comes back, which is what makes two peers pressing 4 in one frame
	# serialize on the room lock instead of both swapping.
	var before: String = mp.my_hero()
	mp.claim_hero("teibi")
	if mp.my_hero() != before:
		return "claim_hero() moved the local player before the lobby confirmed"
	if mp._lobby.heroes_sent != ["teibi"]:
		return "claim_hero() did not ask the lobby for the hero: %s" \
			% str(mp._lobby.heroes_sent)
	mp.free()

	# An offline manager holds nobody, so `hero_holder()` answers "" for every
	# hero — which is what keeps a claim from ever being the verdict solo (the
	# claimable set is empty there too, and either alone is enough).
	# Never added to the tree, for the reason `_check_forced_seed` gives: this is
	# a pure read of the state field, and `_ready()` would build a whole manager.
	var offline: Node = MPManager.new()
	var lonely: bool = offline.hero_holder("windman").is_empty()
	offline.free()
	if not lonely:
		return "an offline manager claimed to know who holds a hero"
	Sentinel.done("hero_press_decision")
	return ""


# =============================================================================
# 23. HOST PERSIST & JOINER NEAR MASTER (bead godot-test1-ank)
# =============================================================================

func _check_host_persist_and_joiner_near_master() -> String:
	"""
	Host same-seed is no-op (pure seed equality, rejoin case) and joiner lands
	near master on a clear spot via the shipped new_run/join_at seam, with
	no-presence fallback to origin. Same-seed A/B is covered by host no-op
	(no new_run → world byte-identical); the old tautology (33333==33333) is
	removed per review. All asserts drive shipped seam, not mock re-implementation.
	"""
	if not MPManager._should_noop_on_seed(12345, 12345):
		return "_should_noop_on_seed true case failed (same seed must noop)"
	if MPManager._should_noop_on_seed(12345, 54321):
		return "_should_noop_on_seed false case failed (different seed must not noop)"
	# Rejoin same-seed no-op: leave-and-rejoin same room keeps world, so adopt
	# must not rebuild, teleport or wipe mask/coins. This is the reachable case
	# (leave clears _has_seed but keeps _room_seed). Host never reaches here
	# today (welcome latch), but the guard is for rejoin.
	var host_terrain: Node = _mock_terrain(77777)
	var host_player: Node = _mock_player(Vector3(1234.0, 0.0, 567.0), 42, 3.14)
	host_player.set("explored_mask", 3)
	root.add_child(host_terrain)
	root.add_child(host_player)
	var host_mp: Node = MPManager.new()
	host_mp.add_to_group("mp")
	root.add_child(host_mp)
	# Simulate rejoin: already in room 77777, left (clears _has_seed) but terrain stays
	host_mp._has_seed = false
	host_mp._room_seed = 77777
	host_mp._receive_seed({"seed": float(77777)})
	if (host_terrain as Object).get("new_run_called"):
		host_terrain.remove_from_group("terrain"); host_player.remove_from_group("player")
		host_terrain.free(); host_player.free(); host_mp.free()
		return "rejoin same-seed: terrain.new_run was called (must be no-op)"
	if (host_player as Object).get("reset_called"):
		host_terrain.remove_from_group("terrain"); host_player.remove_from_group("player")
		host_terrain.free(); host_player.free(); host_mp.free()
		return "rejoin same-seed: player.reset_position was called (must be no-op)"
	if (host_player as Object).get("explored_mask") != 3:
		host_terrain.remove_from_group("terrain"); host_player.remove_from_group("player")
		host_terrain.free(); host_player.free(); host_mp.free()
		return "rejoin same-seed: explored_mask was wiped (must stay)"
	if int(host_player.get("own_coins")) != 42 or absf(float(host_player.get("run_distance")) - 3.14) > 0.001:
		host_terrain.remove_from_group("terrain"); host_player.remove_from_group("player")
		host_terrain.free(); host_player.free(); host_mp.free()
		return "rejoin same-seed: coins/distance changed (must stay)"
	# Different seed must rebuild (proves guard is load-bearing, not always-noop)
	host_terrain.set("new_run_called", false)
	host_terrain.set("run_seed", 77777)
	host_player.set("reset_called", false)
	host_player.set("explored_mask", 0)
	host_player.global_position = Vector3.ZERO
	host_mp._has_seed = false
	host_mp._room_seed = 77777
	host_mp._receive_seed({"seed": float(99999)})
	if not (host_terrain as Object).get("new_run_called"):
		host_terrain.remove_from_group("terrain"); host_player.remove_from_group("player")
		host_terrain.free(); host_player.free(); host_mp.free()
		return "rejoin different-seed: terrain.new_run was NOT called (must rebuild on foreign seed)"
	host_terrain.remove_from_group("terrain"); host_player.remove_from_group("player")
	host_terrain.free(); host_player.free(); host_mp.free()

	# Joiner near master: with master's pos, must call new_run around master's chunk and join_at, not reset
	var join_terrain: Node = _mock_terrain(11111)
	var join_player: Node = _mock_player(Vector3(0.0, 0.0, 0.0), 0, 0.0)
	root.add_child(join_terrain)
	root.add_child(join_player)
	var join_mp: Node = MPManager.new()
	join_mp.add_to_group("mp")
	root.add_child(join_mp)
	join_mp._has_seed = false
	join_mp._master = "master1"
	join_mp._peer_state = {"master1": {"pos": Vector3(500.0, 0.0, 500.0)}}
	join_mp._join_msec = Time.get_ticks_msec()
	join_mp._state = MPManager.State.IN_ROOM
	join_mp._receive_seed({"seed": float(22222)})
	# Wait one physics frame for the await in _receive_seed to place
	await root.get_tree().physics_frame
	if not (join_terrain as Object).get("new_run_called"):
		join_terrain.remove_from_group("terrain"); join_player.remove_from_group("player")
		join_terrain.free(); join_player.free(); join_mp.free()
		return "joiner near-master: new_run not called"
	var expected_around: Vector2i = join_terrain.call("world_to_chunk", Vector3(500.0, 0.0, 500.0)) as Vector2i
	var got_around: Vector2i = (join_terrain as Object).get("new_run_around") as Vector2i
	if got_around != expected_around:
		join_terrain.remove_from_group("terrain"); join_player.remove_from_group("player")
		join_terrain.free(); join_player.free(); join_mp.free()
		return "joiner near-master: new_run_around %s != expected %s" % [str(got_around), str(expected_around)]
	if not (join_player as Object).get("join_called"):
		join_terrain.remove_from_group("terrain"); join_player.remove_from_group("player")
		join_terrain.free(); join_player.free(); join_mp.free()
		return "joiner near-master: join_at not called (must be join, not reset)"
	if (join_player as Object).get("reset_called"):
		join_terrain.remove_from_group("terrain"); join_player.remove_from_group("player")
		join_terrain.free(); join_player.free(); join_mp.free()
		return "joiner near-master: reset_position called (must be join)"
	var janchor: Vector3 = (join_player as Object).get("join_anchor") as Vector3
	if janchor != Vector3(500.0, 0.0, 500.0):
		join_terrain.remove_from_group("terrain"); join_player.remove_from_group("player")
		join_terrain.free(); join_player.free(); join_mp.free()
		return "joiner near-master: join_anchor %s != master pos" % str(janchor)
	join_terrain.remove_from_group("terrain"); join_player.remove_from_group("player")
	join_terrain.free(); join_player.free(); join_mp.free()

	# Degrade honestly: no master pos yet → fallback to origin (reset, not join)
	var join_terrain2: Node = _mock_terrain(11111)
	var join_player2: Node = _mock_player(Vector3.ZERO, 0, 0.0)
	root.add_child(join_terrain2)
	root.add_child(join_player2)
	var join_mp2: Node = MPManager.new()
	join_mp2.add_to_group("mp")
	root.add_child(join_mp2)
	join_mp2._has_seed = false
	join_mp2._master = "master1"
	join_mp2._peer_state = {}
	join_mp2._join_msec = Time.get_ticks_msec()
	join_mp2._state = MPManager.State.IN_ROOM
	join_mp2._receive_seed({"seed": float(22222)})
	if not (join_terrain2 as Object).get("new_run_called"):
		join_terrain2.remove_from_group("terrain"); join_player2.remove_from_group("player")
		join_terrain2.free(); join_player2.free(); join_mp2.free()
		return "joiner no-master: new_run not called"
	if not (join_player2 as Object).get("reset_called"):
		join_terrain2.remove_from_group("terrain"); join_player2.remove_from_group("player")
		join_terrain2.free(); join_player2.free(); join_mp2.free()
		return "joiner no-master fallback: reset_position not called (expected origin fallback)"
	if (join_player2 as Object).get("join_called"):
		join_terrain2.remove_from_group("terrain"); join_player2.remove_from_group("player")
		join_terrain2.free(); join_player2.free(); join_mp2.free()
		return "joiner no-master: join_at called (must be reset when no presence)"
	join_terrain2.remove_from_group("terrain"); join_player2.remove_from_group("player")
	join_terrain2.free(); join_player2.free(); join_mp2.free()
	Sentinel.done("host_persist_and_joiner_near_master")
	return ""


func _mock_terrain(seed: int) -> Node:
	var n: Node = Node.new()
	n.add_to_group("terrain")
	n.set_script(_MockTerrainScript)
	n.set("run_seed", seed)
	n.set("new_run_called", false)
	n.set("new_run_seed", 0)
	n.set("new_run_around", Vector2i.ZERO)
	return n


func _mock_player(pos: Vector3, coins: int, dist: float) -> Node:
	var n: Node3D = Node3D.new()
	n.add_to_group("player")
	n.set_script(_MockPlayerScript)
	# Defer global_position set until after add_child to avoid !is_inside_tree warning
	n.set("own_coins", coins)
	n.set("run_distance", dist)
	n.set("explored_mask", 0)
	n.set("reset_called", false)
	n.set("join_called", false)
	n.set("blocked_center", Vector3.ZERO)
	# Store desired pos in a temp var, caller will set after add_child
	n.set("initial_pos", pos)
	return n


var _MockTerrainScript: GDScript = _make_mock_terrain_script()
var _MockPlayerScript: GDScript = _make_mock_player_script()

func _make_mock_terrain_script() -> GDScript:
	var s: GDScript = GDScript.new()
	s.source_code = """
extends Node
var run_seed: int = 0
var new_run_called: bool = false
var new_run_seed: int = 0
var new_run_around: Vector2i = Vector2i.ZERO
func _init() -> void:
	pass
func new_run(seed: int, around: Vector2i = Vector2i.ZERO) -> void:
	new_run_called = true
	new_run_seed = seed
	new_run_around = around
	run_seed = seed
func world_to_chunk(pos: Vector3) -> Vector2i:
	return Vector2i(int(pos.x / 50.0), int(pos.z / 50.0))
func build_ring_now(_around: Vector2i) -> void:
	pass
"""
	s.reload()
	return s

func _make_mock_player_script() -> GDScript:
	var s: GDScript = GDScript.new()
	s.source_code = """
extends Node3D
var own_coins: int = 0
var run_distance: float = 0.0
var explored_mask: int = 0
var reset_called: bool = false
var join_called: bool = false
var join_anchor: Vector3 = Vector3.ZERO
var blocked_center: Vector3 = Vector3.ZERO
var initial_pos: Vector3 = Vector3.ZERO
var is_game_over: bool = false
func _ready() -> void:
	if initial_pos != Vector3.ZERO:
		global_position = initial_pos
func reset_position() -> void:
	reset_called = true
	global_position = Vector3.ZERO
	own_coins = 0
	run_distance = 0.0
func join_at(anchor: Vector3) -> void:
	join_called = true
	join_anchor = anchor
	global_position = Vector3(anchor.x, 2.0, anchor.z)
	own_coins = 0
	run_distance = 0.0
func _is_body_blocked_at(pos: Vector3) -> bool:
	if blocked_center != Vector3.ZERO and pos.distance_to(blocked_center) < 1.0:
		return true
	return false
"""
	s.reload()
	return s

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
	# to scale, and check 1 above is what keeps it that way.
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


# =============================================================================
# 25. THE ROOM-WIDE PAUSE (bead godot-test1-3a2)
# =============================================================================

func _check_room_pause() -> String:
	"""
	The MANAGER half of the presence `pz` bit — the codec half rides check 7.

	Everything here is driven on `_peer_state` plus the shipped
	`_apply_remote_pause()`, because that pair IS the design: the pause has no
	dictionary of its own precisely so that every way a peer leaves the table
	drops its claim with it, and a check that maintained its own set would be
	asserting against a copy of the bug.
	"""
	if PauseHub.holder_count() != 0:
		return "check 25 started with %d pause holders — an earlier check leaked one" \
			% PauseHub.holder_count()

	var mp: Node = MPManager.new()
	mp.add_to_group("mp")
	root.add_child(mp)
	mp._members = [{"id": "aaa", "name": "Ada"}, {"id": "bbb", "name": "Bo"}]

	var fail: String = ""
	# --- A pauses: exactly ONE claim ------------------------------------------
	mp._peer_state = {"aaa": {"pz": true}}
	mp._apply_remote_pause()
	if PauseHub.holder_count() != 1 or not paused:
		fail = "one pausing peer took %d claims (paused=%s)" \
			% [PauseHub.holder_count(), paused]
	# --- B pauses too: STILL one claim ----------------------------------------
	if fail.is_empty():
		mp._peer_state["bbb"] = {"pz": true}
		mp._apply_remote_pause()
		if PauseHub.holder_count() != 1:
			fail = "a second pausing peer added a claim (%d) — the hub counts by node" \
				% PauseHub.holder_count()
	# --- A resumes with B still pausing: the world stays frozen ---------------
	if fail.is_empty():
		mp._peer_state["aaa"] = {"pz": false}
		mp._apply_remote_pause()
		if not paused:
			fail = "one of two pausers resumed and the world started under the other"
		elif mp.remote_pauser_name() != "Bo":
			fail = "the card named \"%s\", expected the peer still pausing" \
				% mp.remote_pauser_name()
	# --- B goes stale (a dead mesh link): released with no erase site ---------
	if fail.is_empty():
		mp._peer_state["bbb"]["stale"] = true
		mp._apply_remote_pause()
		if paused or PauseHub.holder_count() != 0:
			fail = "a stale peer kept the room frozen (holders=%d)" % PauseHub.holder_count()
		elif mp.remote_pauser_name() != "":
			fail = "remote_pauser_name() named somebody with nothing held"
	# --- ...and erasing it outright is the same answer ------------------------
	if fail.is_empty():
		mp._peer_state = {"bbb": {"pz": true}}
		mp._apply_remote_pause()
		if not paused:
			fail = "the positive control failed — a live pausing peer did not freeze the world"
		else:
			mp._peer_state.erase("bbb")
			mp._apply_remote_pause()
			if paused or PauseHub.holder_count() != 0:
				fail = "erasing the last pauser left the world frozen for good"
	# --- OVER GAME OVER NOTHING IS TAKEN --------------------------------------
	# `GameOverUI` is PAUSABLE, so a remote pause there kills Play Again and
	# `ui_accept` and the screen has no way out. `pause_controller` and
	# `mp_ui._apply_pause` refuse for the same reason; this is the third.
	var player: Node = null
	if fail.is_empty():
		player = _mock_player(Vector3.ZERO, 0, 0.0)
		root.add_child(player)
		player.set("is_game_over", true)
		mp._peer_state = {"aaa": {"pz": true}}
		mp._apply_remote_pause()
		if paused or PauseHub.holder_count() != 0:
			fail = "a remote pause froze the local game-over screen (holders=%d)" \
				% PauseHub.holder_count()
		else:
			# THE CONTROL: the same peer, the same bit, game over cleared.
			player.set("is_game_over", false)
			mp._apply_remote_pause()
			if not paused:
				fail = "the game-over control failed — the pause never applied at all"
			mp._peer_state = {}
			mp._apply_remote_pause()

	if player != null:
		player.remove_from_group("player")
		player.free()
	mp.free()
	if paused or PauseHub.holder_count() != 0:
		return "check 25 leaked a pause claim (holders=%d)" % PauseHub.holder_count()
	if not fail.is_empty():
		return fail
	Sentinel.done("room_pause")
	return ""


func _check_voice_chat_tx() -> String:
	var VoiceChat := load("res://scripts/voice_chat.gd")
	if VoiceChat == null:
		return "could not load voice_chat.gd"
	var vc: Node = VoiceChat.new()
	root.add_child(vc)

	# Initial state: mic is not transmitting
	if vc.is_tx():
		vc.free()
		return "VoiceChat initial tx should be false"

	# Simulate user toggling mic on
	vc._set_tx(true)
	if not vc.is_tx():
		vc.free()
		return "VoiceChat _set_tx(true) failed to activate tx"

	# Entering a room resets tx to false
	vc._on_room_changed("ROOM_A", [])
	if vc.is_tx():
		vc.free()
		return "VoiceChat entering a room must reset tx to false"

	# User turns mic on in ROOM_A
	vc._set_tx(true)
	if not vc.is_tx():
		vc.free()
		return "VoiceChat failed to set tx to true in room"

	# A teammate joins or leaves: roster-only room_changed with same room code
	vc._on_room_changed("ROOM_A", [{"id": "peer2", "name": "teammate"}])
	if not vc.is_tx():
		vc.free()
		return "roster-only room_changed must not clear _tx"

	# Leaving the room (code == "") resets tx to false
	vc._on_room_changed("", [])
	if vc.is_tx():
		vc.free()
		return "leaving room must reset tx to false"

	# Joining a different room resets tx
	vc._set_tx(true)
	vc._on_room_changed("ROOM_B", [])
	if vc.is_tx():
		vc.free()
		return "entering new room must reset tx to false"

	vc.free()
	Sentinel.done("voice_chat_tx")
	return ""
