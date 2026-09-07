extends SceneTree
## Headless self-check for the shared sky (bead godot-test1-vej).
##
##   godot --headless --path . --script res://scripts/weather_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints the first failure and exits 1.
##
## WHAT IT GUARDS — the room's one sky, seven things, each mutation-tested:
##   1. ONE PACKET, ONE SKY — in both peer states. A joiner whose first event
##      is the packet ends with the FULL field (review round 1: the old code
##      left it a 1-4 storm sky forever, and this check used to pin that); a
##      steady-state peer with local storms of its own converges onto exactly
##      the published set at full density. Both draw byte-identical boxes and
##      rain on the same ground — with a point 14 km away dry on both as the
##      negative, without which "always dry" would pass.
##   2. A REPLAY TRACKS THE MASTER. The master moves its storm 200 m and the
##      peer snaps onto the new centre on the next packet; the old ground is
##      dry again.
##   3. A RECYCLED STORM KEEPS ITS SEED CONTRACT. The field is blown through
##      the shipped recycle and every published storm rebuilds byte-identical
##      boxes off its `sd` — review round 1: the recycle kept the old seed.
##   4. THE PROMOTION WINDOW. The silence timeout drops the replay but keeps a
##      newly rolled local storm; the all-clear drops both; every replacement
##      is a real fair cloud (sd=-1), never a dark roll with a forced flag.
##   5. SILENCE FREES IT. The all-clear and REMOTE_WEATHER_TIMEOUT both drop
##      the replay (replaced fair in place, so the rain actually stops), which
##      is the one test that also covers a deposed master, a leave and no MP
##      node at all.
##   6. A NON-MASTER ROLLS NOTHING — with "out of the room it rolls storms" as
##      the positive control, because "rolled nothing" is also what a harness
##      that cannot roll reports.
##   7. SOLO DETERMINISM. With no MP node two managers off one seed roll
##      byte-identical fields — the roll this bead split from the build is
##      still the field solo play always had.
##
## Driven on the SHIPPED functions by hand — no physics frames, no weather
## tick, nothing but the one frame `_ready()` needs. `is_raining_at()` itself
## is untouched by the bead and is READ here, never re-implemented.

const Weather := preload("res://scripts/weather_manager.gd")

## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below
## stamps itself before every return; the report site asks whether every stamp
## was reached. `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")

## A room this peer is not the master of — only the three methods
## `weather_manager._mp_replays_the_weather()` asks for, so a rename there is a
## loudly-missing method here and not a false pass.
const MP_STUB_SOURCE := """extends Node
var online: bool = true
func is_online() -> bool:
	return online
func get_master() -> String:
	return "themaster"
func my_id() -> String:
	return "us"
"""

## Seeded rolls this file was verified against: each one opens with storms, so
## no check below can pass vacuously. Re-verify by running this file if a
## storm constant ever moves.
const MASTER_SEED: int = 7
const CONTROL_SEED: int = 4242
const SOLO_SEED: int = 9001
const ROLL_COUNT: int = 26
const CONTROL_ROLLS: int = 60
const TRACK_SEED: int = 1111
const RECYCLE_SEED: int = 7
const STORM_FIRST_SEED: int = 13
const TRACK_C1: Vector3 = Vector3(120.0, 80.0, -40.0)
const TRACK_C2: Vector3 = Vector3(320.0, 80.0, -40.0)
const FAR_POINT: Vector3 = Vector3(10000.0, 0.0, 10000.0)


func _initialize() -> void:
	Sentinel.isolate_user_state()
	# WAIT ONE FRAME FIRST, the `mp_selfcheck` idiom: at `_initialize` the
	# SceneTree's own root is not yet inside the tree, so a manager added to it
	# never gets `_ready()` and answers with an empty field.
	await process_frame
	var failure: String = _run_checks()
	if failure.is_empty():
		Sentinel.finish(self)
	else:
		printerr("SELFCHECK FAILED: " + failure)
		quit(1)


func _run_checks() -> String:
	"""Run every check in order. Returns "" on success, else the first failure."""
	var failure: String = _check_sync()
	if not failure.is_empty():
		return failure
	failure = _check_track()
	if not failure.is_empty():
		return failure
	failure = _check_recycle()
	if not failure.is_empty():
		return failure
	failure = _check_promotion()
	if not failure.is_empty():
		return failure
	failure = _check_silence()
	if not failure.is_empty():
		return failure
	failure = _check_nonmaster()
	if not failure.is_empty():
		return failure
	failure = _check_solo()
	if not failure.is_empty():
		return failure
	return ""


func _fresh_manager() -> Node:
	## One real weather manager, `_ready()` run, its own `_process` parked so
	## the engine never ticks it under the checks — every assertion below
	## drives the shipped functions by hand, like `fauna_selfcheck` row 6.
	var m: Node = Weather.new()
	root.add_child(m)
	m.set_process(false)
	return m


func _roll_field(mgr: Node, seed: int, count: int) -> void:
	## Fill a manager the way its own first tick does: rolled clouds placed
	## around the origin. Seeded, so two managers roll one field.
	var rng: RandomNumberGenerator = mgr.get("_rng") as RandomNumberGenerator
	rng.seed = seed
	for i: int in count:
		var cloud: Dictionary = mgr.call("_make_cloud")
		mgr.call("_place_cloud_around", cloud, Vector3.ZERO, Vector3.ZERO)
		(mgr.get("_clouds") as Array).append(cloud)


func _storms_of(mgr: Node, only_remote: bool) -> Array:
	var out: Array = []
	for cloud: Dictionary in (mgr.get("_clouds") as Array):
		if not bool(cloud["is_storm"]):
			continue
		if only_remote and not bool(cloud.get("remote", false)):
			continue
		out.append(cloud)
	return out


func _publish(master: Node) -> Dictionary:
	## What a peer receives: the master's sky through the shipped codec, the
	## same bytes the mesh would carry.
	var wire: Dictionary = master.call("weather_sync_state")
	if wire.is_empty():
		return {}
	wire["t"] = "wx"
	return MpCodec.decode_wx(wire)


func _check_sync() -> String:
	## ONE PACKET, ONE SKY — in both peer states that matter. A joiner whose
	## first event is the packet must end with the FULL field (review round 1:
	## the old code left it a 1-4 storm sky forever, and this check used to pin
	## that); a steady-state peer with its own full field — local storms
	## included — must converge onto exactly the published set at full density.
	## Both end raining on the same ground as the master, and on no other.
	var master: Node = _fresh_manager()
	_roll_field(master, MASTER_SEED, ROLL_COUNT)
	var master_storms: Array = _storms_of(master, false)
	if master_storms.is_empty():
		Sentinel.done("wx_sync")
		return "MASTER_SEED rolled no storm in %d clouds — this check measured nothing" % ROLL_COUNT
	var travel: Dictionary = _publish(master)
	if travel.is_empty():
		Sentinel.done("wx_sync")
		return "weather_sync_state published nothing for a sky with %d storms" % master_storms.size()
	# Phase A: the joiner. Empty sky, packet first — the field must still be
	# CLOUD_COUNT afterwards, storms and all.
	var joiner: Node = _fresh_manager()
	joiner.call("apply_weather_sync", travel)
	if (joiner.get("_clouds") as Array).size() != ROLL_COUNT:
		Sentinel.done("wx_sync")
		return "the joiner holds %d clouds, not the full %d — a packet before the first tick shrank its sky" \
				% [(joiner.get("_clouds") as Array).size(), ROLL_COUNT]
	var failure: String = _assert_same_sky(master_storms, joiner, "joiner")
	if not failure.is_empty():
		Sentinel.done("wx_sync")
		return failure
	# Phase B: the steady-state peer. Full field of its own — including local
	# storms the drop phase must take out — converged onto the published set.
	var full: Node = _fresh_manager()
	_roll_field(full, CONTROL_SEED, ROLL_COUNT)
	if _storms_of(full, false).is_empty():
		Sentinel.done("wx_sync")
		return "CONTROL_SEED rolled no local storm — phase B would converge nothing"
	full.call("apply_weather_sync", travel)
	if (full.get("_clouds") as Array).size() != ROLL_COUNT:
		Sentinel.done("wx_sync")
		return "the steady peer holds %d clouds, not %d — the wholesale apply grew or shrank the field" \
				% [(full.get("_clouds") as Array).size(), ROLL_COUNT]
	failure = _assert_same_sky(master_storms, full, "steady peer")
	if not failure.is_empty():
		Sentinel.done("wx_sync")
		return failure
	for cloud: Dictionary in (full.get("_clouds") as Array):
		if bool(cloud["is_storm"]) and not bool(cloud.get("remote", false)):
			Sentinel.done("wx_sync")
			return "the steady peer kept local storm sd=%d the packet never named — it rains where the master is clear" \
					% int(cloud["sd"])
	var first: Dictionary = master_storms[0]
	var inside := Vector3((first["center"] as Vector3).x, 0.0, (first["center"] as Vector3).z)
	if not bool(master.call("is_raining_at", inside)):
		Sentinel.done("wx_sync")
		return "the master is dry under its own storm — this check measured nothing"
	for peer: Node in [joiner, full]:
		if not bool(peer.call("is_raining_at", inside)):
			Sentinel.done("wx_sync")
			return "a peer is dry under the replayed storm at %s — one sky was the whole point" % str(inside)
		if bool(peer.call("is_raining_at", FAR_POINT)):
			Sentinel.done("wx_sync")
			return "a peer rains 14 km from every storm — the negative control failed, so the positive proves nothing"
	if bool(master.call("is_raining_at", FAR_POINT)):
		Sentinel.done("wx_sync")
		return "the master rains 14 km from every storm — the negative control failed"
	Sentinel.done("wx_sync")
	return ""


func _assert_same_sky(master_storms: Array, peer: Node, who: String) -> String:
	## Every published storm stands on the peer with byte-identical boxes and
	## the remote flag set — the whole of what "one sky" means below the rain.
	for storm: Dictionary in master_storms:
		var twin: Dictionary = {}
		for cloud: Dictionary in (peer.get("_clouds") as Array):
			if int(cloud.get("sd", -2)) == int(storm["sd"]):
				twin = cloud
				break
		if twin.is_empty():
			return "the %s never built storm sd=%d — the replay dropped a named storm" \
					% [who, int(storm["sd"])]
		if var_to_bytes(twin["boxes"]) != var_to_bytes(storm["boxes"]):
			return "the %s drew different boxes for storm sd=%d — two builds off one seed disagree" \
					% [who, int(storm["sd"])]
		if not bool(twin.get("remote", false)):
			return "the %s's storm sd=%d is not flagged remote — it would be re-published on promotion" \
					% [who, int(storm["sd"])]
	return ""


func _check_track() -> String:
	## A REPLAY TRACKS THE MASTER: one storm wanders 200 m and the next packet
	## snaps the peer onto it — the old ground drying behind it.
	var master: Node = _fresh_manager()
	var peer: Node = _fresh_manager()
	var storm: Dictionary = master.call("_build_storm_cloud", TRACK_SEED)
	storm["center"] = TRACK_C1
	(master.get("_clouds") as Array).append(storm)
	peer.call("apply_weather_sync", _publish(master))
	var twin: Array = _storms_of(peer, true)
	if twin.size() != 1:
		Sentinel.done("wx_track")
		return "the joiner holds %d replayed storms for 1 published — catch-up failed" % twin.size()
	var at: Vector3 = twin[0]["center"]
	if at.distance_to(TRACK_C1) > 1e-6:
		Sentinel.done("wx_track")
		return "the joiner started %.2f m from the live storm — it was eased, not snapped" \
				% at.distance_to(TRACK_C1)
	storm["center"] = TRACK_C2
	peer.call("apply_weather_sync", _publish(master))
	twin = _storms_of(peer, true)
	if twin.size() != 1:
		Sentinel.done("wx_track")
		return "the peer holds %d replayed storms after the move — the wholesale apply duplicated it" \
				% twin.size()
	at = twin[0]["center"]
	if at.distance_to(TRACK_C2) > 1e-6:
		Sentinel.done("wx_track")
		return "the replayed centre is %.2f m from the master's — the packet's live state is not applied" \
				% at.distance_to(TRACK_C2)
	var wet := Vector3(TRACK_C2.x, 0.0, TRACK_C2.z)
	var dry := Vector3(TRACK_C1.x, 0.0, TRACK_C1.z)
	if not bool(peer.call("is_raining_at", wet)):
		Sentinel.done("wx_track")
		return "the peer is dry under the storm's new centre — the snap did not reach `is_raining_at()`"
	if bool(peer.call("is_raining_at", dry)):
		Sentinel.done("wx_track")
		return "the peer still rains at the storm's old centre — the move left a ghost behind"
	Sentinel.done("wx_track")
	return ""


func _check_recycle() -> String:
	## A RECYCLED STORM KEEPS ITS SEED CONTRACT: the whole field is blown past
	## the disc through the shipped `_update_clouds()`, and every storm the
	## master publishes afterwards rebuilds byte-identical boxes off its `sd`
	## on a peer — with the same rain on the same ground. Review round 1: the
	## recycle used to copy six keys and keep the old seed, so peers drew
	## different storms (and several `-1`s collapsed into one).
	var master: Node = _fresh_manager()
	_roll_field(master, RECYCLE_SEED, ROLL_COUNT)
	if _storms_of(master, false).is_empty():
		Sentinel.done("wx_recycle")
		return "RECYCLE_SEED rolled no storm — this check measured nothing"
	# Teleport the disc: every cloud is suddenly out of range and recycles.
	master.call("_update_clouds", Vector3(10000.0, 0.0, 0.0), 60.0)
	var recycled: Array = _storms_of(master, false)
	if recycled.is_empty():
		Sentinel.done("wx_recycle")
		return "no storm survived the recycle — this check measured nothing"
	for storm: Dictionary in recycled:
		if int(storm["sd"]) == -1:
			Sentinel.done("wx_recycle")
			return "a recycled storm carries sd=-1 — the publish names a build that never was"
		if bool(storm.get("remote", false)):
			Sentinel.done("wx_recycle")
			return "a recycled storm is flagged remote — the master would never publish it"
	var travel: Dictionary = _publish(master)
	if travel.is_empty():
		Sentinel.done("wx_recycle")
		return "the master published nothing after the recycle — this check measured nothing"
	var peer: Node = _fresh_manager()
	peer.call("apply_weather_sync", travel)
	var failure: String = _assert_same_sky(recycled, peer, "recycle peer")
	if not failure.is_empty():
		Sentinel.done("wx_recycle")
		return failure
	var first: Dictionary = recycled[0]
	var inside := Vector3((first["center"] as Vector3).x, 0.0, (first["center"] as Vector3).z)
	if not bool(master.call("is_raining_at", inside)) \
			or not bool(peer.call("is_raining_at", inside)):
		Sentinel.done("wx_recycle")
		return "master and peer disagree about the rain under a recycled storm at %s" % str(inside)
	Sentinel.done("wx_recycle")
	return ""


func _check_promotion() -> String:
	## THE PROMOTION WINDOW: a peer holding a replay is elected master and
	## rolls a LOCAL storm before the silence lease runs out. The timeout must
	## drop the replay and KEEP the local sky; the all-clear must drop both.
	## And every replacement is a real fair cloud (sd=-1), never a dark roll
	## with its flag forced — that storm-sized white cloud.
	var mgr: Node = _fresh_manager()
	var timeout: float = float(mgr.get("REMOTE_WEATHER_TIMEOUT"))
	var replay: Dictionary = mgr.call("_build_storm_cloud", TRACK_SEED)
	replay["center"] = TRACK_C1
	replay["remote"] = true
	(mgr.get("_clouds") as Array).append(replay)
	var local: Dictionary = mgr.call("_build_storm_cloud", TRACK_SEED + 1)
	local["center"] = TRACK_C1 + Vector3(300.0, 0.0, 300.0)
	(mgr.get("_clouds") as Array).append(local)
	mgr.call("_tick_remote_weather", timeout + 1.0)
	var remote_left: Array = _storms_of(mgr, true)
	var all_left: Array = _storms_of(mgr, false)
	if not remote_left.is_empty():
		Sentinel.done("wx_promotion")
		return "the timeout left %d replayed storms standing" % remote_left.size()
	if all_left.size() != 1 or int(all_left[0]["sd"]) != int(local["sd"]):
		Sentinel.done("wx_promotion")
		return "the timeout wiped the promoted master's own storm — the new sky died with the old"
	# ...while the all-clear takes the local one too: a non-master's pre-join
	# storm must never survive it, or it rains where the master is clear.
	mgr.call("apply_weather_sync", {"k": -1})
	if not _storms_of(mgr, false).is_empty():
		Sentinel.done("wx_promotion")
		return "the all-clear left a local storm standing — gating the drop on `remote` alone diverges"
	# The replacement artifact, on a manager OUTSIDE any room: the first roll
	# off STORM_FIRST_SEED is dark, so the old `_make_cloud()` path left a
	# storm-sized white cloud here with a real seed. It must be fair-shaped
	# with sd=-1 instead.
	var solo: Node = _fresh_manager()
	var solo_rng: RandomNumberGenerator = solo.get("_rng") as RandomNumberGenerator
	solo_rng.seed = STORM_FIRST_SEED
	var doomed: Dictionary = solo.call("_build_storm_cloud", TRACK_SEED)
	doomed["center"] = TRACK_C1
	doomed["remote"] = true
	(solo.get("_clouds") as Array).append(doomed)
	solo.call("_tick_remote_weather", timeout + 1.0)
	var rest: Array = solo.get("_clouds") as Array
	if rest.size() != 1 or bool((rest[0] as Dictionary)["is_storm"]) \
			or int((rest[0] as Dictionary)["sd"]) != -1:
		Sentinel.done("wx_promotion")
		return "the freed replay came back as %s — not a real fair cloud" % str(rest)
	Sentinel.done("wx_promotion")
	return ""


func _check_silence() -> String:
	## SILENCE FREES IT: the all-clear and then the timeout both drop the
	## replay — replaced fair in place, so the rain actually stops. Run as a
	## non-master throughout, which is the only manager that ever holds a
	## replay: every replacement roll is then fair by construction and the
	## dryness below is deterministic, not a 6-in-7.
	var mp_script := GDScript.new()
	mp_script.source_code = MP_STUB_SOURCE
	mp_script.reload()
	var mp: Node = mp_script.new()
	mp.add_to_group("mp")
	root.add_child(mp)
	var master: Node = _fresh_manager()
	var peer: Node = _fresh_manager()
	var storm: Dictionary = master.call("_build_storm_cloud", TRACK_SEED)
	storm["center"] = TRACK_C1
	(master.get("_clouds") as Array).append(storm)
	var packet: Dictionary = _publish(master)
	if packet.is_empty():
		mp.remove_from_group("mp")
		mp.queue_free()
		Sentinel.done("wx_silence")
		return "the master published nothing — this check measured nothing"
	peer.call("apply_weather_sync", packet)
	if _storms_of(peer, true).size() != 1:
		mp.remove_from_group("mp")
		mp.queue_free()
		Sentinel.done("wx_silence")
		return "the peer holds no replay — the silence below would free nothing"
	# The all-clear frees it promptly, without waiting out the timeout.
	peer.call("apply_weather_sync", {"k": -1})
	if not _storms_of(peer, true).is_empty():
		mp.remove_from_group("mp")
		mp.queue_free()
		Sentinel.done("wx_silence")
		return "the all-clear left a replayed storm standing — peers wait out the timeout for nothing"
	# ...and the timeout frees what no all-clear reached.
	peer.call("apply_weather_sync", packet)
	var timeout: float = float(peer.get("REMOTE_WEATHER_TIMEOUT"))
	peer.call("_tick_remote_weather", 1.0)
	if _storms_of(peer, true).size() != 1:
		mp.remove_from_group("mp")
		mp.queue_free()
		Sentinel.done("wx_silence")
		return "one second of silence already freed the replay — the lease is %.1f s, not %.1f" \
				% [1.0, timeout]
	peer.call("_tick_remote_weather", timeout)
	if not _storms_of(peer, true).is_empty():
		mp.remove_from_group("mp")
		mp.queue_free()
		Sentinel.done("wx_silence")
		return "a replayed storm survived %.1f s of silence — a dead master's rain is immortal" \
				% (1.0 + timeout)
	var was_wet := Vector3(TRACK_C1.x, 0.0, TRACK_C1.z)
	if bool(peer.call("is_raining_at", was_wet)):
		mp.remove_from_group("mp")
		mp.queue_free()
		Sentinel.done("wx_silence")
		return "the peer still rains where the freed storm stood — the drop did not reach the sky"
	mp.remove_from_group("mp")
	mp.queue_free()
	Sentinel.done("wx_silence")
	return ""


func _check_nonmaster() -> String:
	## A NON-MASTER ROLLS NOTHING — and the same manager rolls storms the
	## moment the room is gone, the positive control without which "rolled
	## nothing" would pass on a harness that simply cannot roll.
	var mp_script := GDScript.new()
	mp_script.source_code = MP_STUB_SOURCE
	mp_script.reload()
	var mp: Node = mp_script.new()
	mp.add_to_group("mp")
	root.add_child(mp)
	var mgr: Node = _fresh_manager()
	var rng: RandomNumberGenerator = mgr.get("_rng") as RandomNumberGenerator
	rng.seed = CONTROL_SEED
	var rolled := 0
	for i: int in CONTROL_ROLLS:
		if bool((mgr.call("_make_cloud") as Dictionary)["is_storm"]):
			rolled += 1
	if rolled > 0:
		mp.remove_from_group("mp")
		mp.queue_free()
		Sentinel.done("wx_nonmaster")
		return "a room NON-MASTER rolled %d storms of its own — two skies in one room" % rolled
	mp.set("online", false)
	rng.seed = CONTROL_SEED
	rolled = 0
	for i: int in CONTROL_ROLLS:
		if bool((mgr.call("_make_cloud") as Dictionary)["is_storm"]):
			rolled += 1
	if rolled == 0:
		mp.remove_from_group("mp")
		mp.queue_free()
		Sentinel.done("wx_nonmaster")
		return "out of the room the manager still rolled nothing — the non-master assertion above measured nothing"
	mp.remove_from_group("mp")
	mp.queue_free()
	Sentinel.done("wx_nonmaster")
	return ""


func _check_solo() -> String:
	## SOLO DETERMINISM: with no MP node the roll is still the roll — two
	## managers off one seed lay byte-identical fields, storms included.
	if get_first_node_in_group("mp") != null:
		Sentinel.done("wx_solo")
		return "an \"mp\" node leaked in from an earlier check — solo means solo"
	var a: Node = _fresh_manager()
	var b: Node = _fresh_manager()
	if bool(a.call("_mp_replays_the_weather")):
		Sentinel.done("wx_solo")
		return "a manager with no MP node thinks it replays somebody's weather"
	_roll_field(a, SOLO_SEED, ROLL_COUNT)
	_roll_field(b, SOLO_SEED, ROLL_COUNT)
	if var_to_bytes(a.get("_clouds")) != var_to_bytes(b.get("_clouds")):
		Sentinel.done("wx_solo")
		return "two managers off seed %d rolled different fields — the split changed the solo roll" % SOLO_SEED
	if _storms_of(a, false).is_empty():
		Sentinel.done("wx_solo")
		return "SOLO_SEED rolled no storm in %d clouds — this check measured nothing" % ROLL_COUNT
	Sentinel.done("wx_solo")
	return ""
