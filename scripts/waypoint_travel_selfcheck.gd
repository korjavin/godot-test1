extends SceneTree
## waypoint_travel_selfcheck — the TRAVEL PRIMITIVE (epic `godot-test1-sc6`, bead
## .3): `PlayerController.travel_to_waypoint()` moves the hero to a found circle
## and bills them for it, refuses every case the epic's rule refuses, and — the
## claim `EndlessTerrain.relocate()` exists for — leaves the seed and the HQ
## building alone while it does.
##
## WHAT IT ASSERTS
##
##   1. THE HOP. Standing on a found circle, travelling to another found one
##      lands the body at the target with that chunk BUILT and not
##      bare, `run_seed` UNCHANGED, transient ability state cleared, the hub
##      latched onto the target, and exactly `TELEPORT_COIN_COST` off the run's
##      coins (never off anything monotone).
##   2. THE REFUSALS. Target not found, the circle UNDER OUR FEET not found,
##      standing on nothing, target == current, and too few coins — each moves
##      nothing and charges nothing, and the last one says so on screen.
##   2b. THE ROOM GATE. A joiner whose body the room has not put down yet is
##      refused even though its bank already reads — the window a hop would be
##      wiped by `_apply_join_placement()`.
##   3. THE HQ SURVIVES A HOP. Road -> HQ -> road, and the tower shell is the
##      SAME OBJECT at the end. This is the whole reason `relocate()` was split
##      out of `new_run()`: a seed write (even to the same value) goes through
##      `set_run_seed()` -> `_tower_reset()`, which frees the shell and throws
##      away the building's per-run interior. A hop must not.
##
## DRIVEN AGAINST THE LIVE `main.tscn` — `debug_teleport_selfcheck`'s prelude,
## and for that check's reason: every claim here is about what the SHIPPED
## function does to a real run in a real streamed world, and a stubbed terrain
## would be a second copy of the wipe list this file exists to pin. The circles
## themselves come from `TerrainWaypoints.waypoint_sites()` off that terrain, so
## the sites are the run's own rather than invented coordinates.
##
## THE ONE PRIVATE REACHED INTO IS `WaypointHub._tick()`. The hub's enter edge is
## throttled to 5 Hz off `_process`, and sleeping a fifth of a second per move
## would make this check a timing test; calling its tick directly runs the
## SHIPPED scan (and therefore the shipped `activate_waypoint()` that sets the
## bits) with the throttle taken out. Nothing else here touches a private.
##
## ITS OWN FILE rather than a fifth function in `waypoint_selfcheck`: CI shards
## by file (`selfcheck_shards.sh`), and this one boots a whole scene where that
## one builds a bare terrain.

const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")

const PlayerScript: GDScript = preload("res://scripts/player_controller.gd")

## How far from the target's centre the body may land: `_place_near()`'s OWN
## outermost ring plus a metre, read off the shipped constant so a retune moves
## this with it.
##
## NOT A TIGHTER NUMBER, and the reason is measured rather than assumed. The
## placement probes `JOIN_RING_RADII` (3, 5, 8, 12 m) outward and takes the first
## ring with a clear candidate, so which ring wins is a function of the RUN SEED —
## which is re-rolled on every boot of `main.tscn`. A tolerance pinned to the
## inner ring passes on most seeds and fails on the ones that put a boulder field
## beside the circle, which is a flaky check rather than a strict one. What this
## assertion is actually for is "the hop arrived AT the circle rather than 200 m
## short of it", and the exact landing spot has its own precise assertion two
## lines down: the hub latch.
const LANDING_SLACK: float = 1.0

var _failures: Array[String] = []


func _initialize() -> void:
	Sentinel.isolate_user_state()
	# ONE FRAME FIRST: a node added to `root` before the main loop answers null to
	# `get_tree()` — `debug_teleport_selfcheck`'s prelude, its lesson.
	await process_frame
	await _boot()

	await _check_hop()
	await _check_refusals()
	await _check_hq_survives()
	# LAST, because it replaces `main.tscn`'s own solo manager with a fake room
	# and frees it again — nothing after it would have an `mp` node to read.
	await _check_room_gate()

	if _failures.is_empty():
		Sentinel.finish(self)
	else:
		for line: String in _failures:
			printerr("FAIL: " + line)
		printerr("SELFCHECK FAILED (%d)" % _failures.size())
		quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


func _boot() -> void:
	"""main.tscn running with the start overlay dismissed — the teleport check's."""
	root.add_child(load("res://scenes/main.tscn").instantiate())
	await process_frame
	var overlay: Node = root.get_node_or_null("Main/HUD/StartOverlay")
	if overlay != null and overlay.has_method("_dismiss"):
		overlay._dismiss()
	await process_frame


func _world() -> Array:
	"""
	`[player, terrain, hub, sites]`, or an empty array when the scene is not whole.

	Re-fetched per check by GROUP rather than cached, which is the project's
	discovery convention and also the honest thing here: the hop frees and
	rebuilds every chunk, so nothing held across one may be assumed alive.
	"""
	var player: Node = get_first_node_in_group("player")
	var terrain: Node = get_first_node_in_group("terrain")
	var hub: Node = get_first_node_in_group("waypoint_hub")
	if player == null or terrain == null or hub == null:
		return []
	var sites: Array[Dictionary] = TerrainWaypoints.waypoint_sites(terrain)
	# Sites 1 and 2 are the approach and the spawn, and site 0 the HQ door — the
	# three this file travels between. A table shorter than that is a broken
	# world, not a passing check.
	if sites.size() < 3:
		return []
	return [player, terrain, hub, sites]


func _stand_on(player: Node, hub: Node, sites: Array, index: int) -> void:
	"""
	Put the body on circle `index` and run the hub's scan once.

	The scan is the shipped one, so this ALSO finds the circle the first time
	(`_arrive` -> `activate_waypoint`) — which is how the bits under test get set:
	through the discovery path a player really walks, never by writing the mask.

	One tick is enough to leave AND arrive: `_scan()` re-arms first (the body is
	hundreds of metres from wherever it last latched) and latches the nearest in
	range in the same pass.
	"""
	var pos: Vector3 = sites[index]["pos"]
	player.global_position = Vector3(pos.x, 1.0, pos.z)
	hub._tick()


func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _lifetime_coins() -> int:
	"""Meta-progression's persisted coin total, or -1 when there is no progression."""
	var progression: Node = get_first_node_in_group("progression")
	if progression == null or not ("lifetime_coins" in progression):
		return -1
	return int(progression.lifetime_coins)


func _check_hop() -> void:
	"""Check 1 — the hop lands, costs 15 coins, and changes nothing it must not."""
	var world: Array = _world()
	if world.is_empty():
		_fail("no player / terrain / waypoint hub / site table after boot")
		Sentinel.done("hop")
		return
	var player: Node = world[0]
	var terrain: Node = world[1]
	var hub: Node = world[2]
	var sites: Array = world[3]

	player.own_coins = 100
	player.coins_collected = 100
	player.record_coins = 0

	# Find both circles by walking onto them, then come back to the first.
	_stand_on(player, hub, sites, 2)
	if int(hub.standing_on()) != 2 or player.waypoint_mask & (1 << 2) == 0:
		_fail("standing on circle 2 did not find it (standing_on=%d mask=%d)"
			% [int(hub.standing_on()), player.waypoint_mask])
		Sentinel.done("hop")
		return
	_stand_on(player, hub, sites, 1)
	if int(hub.standing_on()) != 1 or player.waypoint_mask & (1 << 1) == 0:
		_fail("standing on circle 1 did not find it (standing_on=%d mask=%d)"
			% [int(hub.standing_on()), player.waypoint_mask])
		Sentinel.done("hop")
		return

	# Transient ability state a teleport must clear (CLAUDE.md, Player and camera).
	player.windman_boost_timer = 5.0
	player.is_giant = true
	var seed_before: int = terrain.run_seed
	var lifetime_before: int = _lifetime_coins()

	var moved: bool = await player.travel_to_waypoint(2)
	if not moved:
		_fail("travel_to_waypoint(2) refused while standing on found circle 1 with 100 coins")
		Sentinel.done("hop")
		return

	var target: Vector3 = sites[2]["pos"]
	var landed: float = _xz(player.global_position, target)
	var tolerance: float = float(PlayerScript.JOIN_RING_RADII[-1]) + LANDING_SLACK
	if landed > tolerance:
		_fail("the hop landed %.1f m from circle 2 — outside _place_near()'s own %.0f m reach"
			% [landed, tolerance])
	# THE WORLD CAME WITH IT. `active_chunks` alone is satisfied by HALF the
	# sequence (`relocate` floors the ring); a debt note in `bare_chunks` is the
	# only thing that can see `build_ring_now()` missing — the half that stops
	# `_place_near()` probing a bare ring and landing inside a block that appears
	# two frames later. `debug_teleport_selfcheck`'s pair of assertions, its words.
	var chunk: Vector2i = terrain.world_to_chunk(player.global_position)
	if not terrain.active_chunks.has(chunk):
		_fail("no built chunk under the player after the hop")
	elif terrain.bare_chunks.has(chunk):
		_fail("the chunk under the player is BARE — build_ring_now() did not buy its content before _place_near() probed it")
	# THE SEED. `relocate()` must not write it: a hop that re-seeded would hand a
	# multiplayer joiner a different world and reprint "New run started".
	if terrain.run_seed != seed_before:
		_fail("the hop changed run_seed (%d -> %d) — relocate() must never write the seed"
			% [seed_before, terrain.run_seed])
	if player.windman_boost_timer != 0.0 or player.is_giant:
		_fail("the hop left transient ability state behind (boost=%.1f giant=%s)"
			% [player.windman_boost_timer, player.is_giant])
	if int(hub.standing_on()) != 2:
		_fail("the hub says the hero is on circle %d after landing on 2 — arrived_at() did not latch"
			% int(hub.standing_on()))
	# THE FARE — owner ruling 2026-09-12: 15 coins off the RUN's coins, and off
	# NOTHING MONOTONE. Lifetime coins are the one persisted total a fare could
	# plausibly reach (`collect_coin` credits them on the way up), so it is read
	# across the hop: CLAUDE.md's "coins are never deducted from lifetime totals".
	var cost: int = int(PlayerScript.TELEPORT_COIN_COST)
	if lifetime_before >= 0 and _lifetime_coins() < lifetime_before:
		_fail("the fare took %d off LIFETIME coins (%d -> %d) — persistence is monotone"
			% [lifetime_before - _lifetime_coins(), lifetime_before, _lifetime_coins()])
	if player.own_coins != 100 - cost:
		_fail("the hop billed %d coins, not TELEPORT_COIN_COST (%d)"
			% [100 - player.own_coins, cost])
	if player.coins_collected != 100 - cost:
		_fail("the displayed coin total did not move with the fare (%d)" % player.coins_collected)
	# ...and the run's PEAK was snapshotted before the bill, or a record read off
	# the live balance is one fare short of what the HUD showed.
	if player.record_coins < 100:
		_fail("the fare lost the run's coin peak (record_coins=%d, balance before the bill was 100)"
			% player.record_coins)
	Sentinel.done("hop")


func _check_refusals() -> void:
	"""Check 2 — every refusal the epic's rule requires, each a no-op.

	Runs after check 1, so the hero is standing on found circle 2 with circles 1
	and 2 in the mask and nothing else — which is exactly the state the first
	three cases need.
	"""
	var world: Array = _world()
	if world.is_empty():
		_fail("no world for the refusal checks")
		Sentinel.done("refusals")
		return
	var player: Node = world[0]
	var hub: Node = world[2]
	var sites: Array = world[3]
	var cost: int = int(PlayerScript.TELEPORT_COIN_COST)

	# a. THE TARGET IS NOT FOUND. Circle 0 (the HQ door) has never been walked on.
	player.own_coins = 100
	player.coins_collected = 100
	await _refuses(player, hub, sites, 0, "the target circle is not found")
	# a2. THE CIRCLE UNDER OUR FEET IS NOT FOUND. `standing_on()` is a POSITION
	# AND NOT A PERMISSION (its docstring), so the hub latches a circle nobody has
	# found and the mask is what refuses. Reachable in the shipped game:
	# `restart_game()` and `join_at()` both zero `waypoint_mask` while the latch
	# survives for up to one 200 ms tick. Dropping the source half of the AND and
	# leaving the target half must fail HERE, or only half the rule is tested.
	var kept_mask: int = player.waypoint_mask
	player.waypoint_mask = 1 << 1  # ...the TARGET found, the circle we stand on not.
	await _refuses(player, hub, sites, 1, "the circle under the hero's feet is not found")
	player.waypoint_mask = kept_mask
	# b. STANDING ON NOTHING. Park the body well clear of every circle and let the
	# shipped scan re-arm — `standing_on()` must be -1 before this proves anything.
	player.global_position = Vector3(sites[1]["pos"].x, 1.0, float(sites[1]["pos"].z) + 400.0)
	hub._tick()
	if int(hub.standing_on()) != -1:
		_fail("the hub still reports circle %d 400 m away — the off-circle case is untested"
			% int(hub.standing_on()))
	await _refuses(player, hub, sites, 1, "the hero is standing on no circle at all")
	# c. THE TARGET IS THE CIRCLE UNDER OUR FEET.
	_stand_on(player, hub, sites, 1)
	await _refuses(player, hub, sites, 1, "the target is the circle already stood on")
	# d. TOO FEW COINS — the owner's refusal, and the only one that SPEAKS. The
	# card is asserted as well as the no-op: without this, deleting the announce
	# call is a silent pass and the ruling's "refuse with a caption" is unmeasured.
	var toast: Node = get_first_node_in_group("landmark_toast")
	if toast != null and "name_label" in toast and toast.name_label != null:
		toast.name_label.text = ""
	player.own_coins = cost - 1
	player.coins_collected = cost - 1
	await _refuses(player, hub, sites, 2, "the hero cannot afford the fare")
	if toast == null or not ("name_label" in toast) or toast.name_label == null:
		_fail("no landmark toast in main.tscn — the spoken refusal cannot be checked")
	elif String(toast.name_label.text) != "Not enough coins":
		_fail("the unaffordable hop raised no card (the toast reads \"%s\")"
			% String(toast.name_label.text))
	elif not toast.visible:
		_fail("the too-poor card was written but the toast is not visible")
	Sentinel.done("refusals")


func _refuses(player: Node, hub: Node, sites: Array, index: int, why: String) -> void:
	"""One refusal: `travel_to_waypoint(index)` returns false and moves/charges nothing."""
	var where: Vector3 = player.global_position
	var coins: int = player.own_coins
	var latched: int = int(hub.standing_on())
	var moved: bool = await player.travel_to_waypoint(index)
	if moved:
		_fail("travel_to_waypoint(%d) FIRED when %s" % [index, why])
	if player.global_position.distance_to(where) > 0.01:
		_fail("the refused hop (%s) moved the player %.2f m"
			% [why, player.global_position.distance_to(where)])
	if player.own_coins != coins:
		_fail("the refused hop (%s) charged %d coins" % [why, coins - player.own_coins])
	if int(hub.standing_on()) != latched:
		_fail("the refused hop (%s) relatched the hub onto circle %d"
			% [why, int(hub.standing_on())])


func _check_hq_survives() -> void:
	"""Check 3 — road -> HQ -> road leaves the SAME tower shell standing.

	The claim `relocate()` was split out of `new_run()` to make true. A seed write
	resets the tower even to the same value (`set_run_seed` -> `_tower_reset`),
	which frees the shell and with it the building's per-run interior: the guards
	where they stood, the dossiers already taken, the LOD scent trails. Comparing
	the INSTANCE ID rather than "is there a tower" is what makes the assertion
	sharp — a reset rebuilds one immediately, and only its identity gives it away.

	The HQ's bit is set through the shipped `activate_waypoint()` rather than by
	walking: the hub's enter edge is check 1's subject and this one is about what
	survives the hop, not about how the bit got set.
	"""
	var world: Array = _world()
	if world.is_empty():
		_fail("no world for the HQ check")
		Sentinel.done("hq_survives")
		return
	var player: Node = world[0]
	var terrain: Node = world[1]
	var hub: Node = world[2]
	var sites: Array = world[3]

	player.own_coins = 1000
	player.coins_collected = 1000
	player.activate_waypoint(0)
	_stand_on(player, hub, sites, 1)
	if not await player.travel_to_waypoint(0):
		_fail("the hop to the HQ door was refused")
		Sentinel.done("hq_survives")
		return
	var shell: Node3D = terrain.tower_shell()
	if shell == null:
		_fail("no tower shell after landing on the HQ door circle — _tower_stream did not run")
		Sentinel.done("hq_survives")
		return
	var shell_id: int = shell.get_instance_id()

	if not await player.travel_to_waypoint(1):
		_fail("the hop back to the road was refused")
		Sentinel.done("hq_survives")
		return
	var after: Node3D = terrain.tower_shell()
	if after == null:
		_fail("the hop away from the HQ FREED the tower shell — relocate() must not reset the tower")
	elif after.get_instance_id() != shell_id:
		_fail("the hop rebuilt the tower shell (instance %d -> %d) — the HQ's per-run interior was thrown away"
			% [shell_id, after.get_instance_id()])
	Sentinel.done("hq_survives")


func _check_room_gate() -> void:
	"""Check 4 — a joiner the room has not placed yet may not travel.

	THE TRAP THIS EXISTS FOR (review, 2026-09-12). `shared_bank()` is readable as
	soon as the incumbents' snapshots are in OR their 1.5 s deadline is spent,
	whether or not a world has arrived to place into — so a gate written on
	"is the bank readable" lets a hop fire in the window before
	`_apply_join_placement()` runs, and that placement then rebuilds the world
	around the group and puts the body somewhere else. The fare was real; the hop
	was not. The gate is `MpManager.join_placed()` and this drives BOTH of its
	answers on a real manager, flipped the way `mp_selfcheck` and
	`debug_teleport_selfcheck` flip one.
	"""
	var world: Array = _world()
	if world.is_empty():
		_fail("no world for the room gate check")
		Sentinel.done("room_gate")
		return
	var player: Node = world[0]
	var hub: Node = world[2]
	var sites: Array = world[3]

	# main.tscn carries its own solo manager first in the "mp" group and `_mp()`
	# answers the FIRST, so displace it — `debug_teleport_selfcheck`'s line.
	for old: Node in get_nodes_in_group("mp"):
		old.free()
	var mp: Node = MpManager.new()
	mp.add_to_group("mp")
	root.add_child(mp)
	mp._state = MpManager.State.IN_ROOM
	# A JOINER, not a host, whose placement is still owed — and whose bank already
	# reads, which is the whole point: `_join_settled()` is satisfied by the
	# snapshot deadline alone.
	mp._first_member = false
	mp._join_applied = false
	mp._join_wait = MpManager.JOIN_SNAPSHOT_WAIT
	if mp.shared_bank(player.own_coins) == null:
		_fail("the fake unplaced joiner's bank does not read — the gate's trap is not being driven")
	if player._travel_room_ready():
		_fail("travel allowed while the room still owes this body a placement")
	player.own_coins = 100
	player.coins_collected = 100
	_stand_on(player, hub, sites, 1)
	await _refuses(player, hub, sites, 2, "the room has not placed this body yet")

	# ...and once the placement has run, travel is an ordinary room-legal move.
	mp._join_applied = true
	if not player._travel_room_ready():
		_fail("travel still refused after the room placed this body — the gate is the room, not the join")
	mp.free()
	Sentinel.done("room_gate")
