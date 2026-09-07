extends SceneTree
## ============================================================================
## TOWER GATE SYNC SELF-CHECK — THE HQ'S OPENED SET, ROOM-WIDE
## ============================================================================
##
## Run headless:
##     godot --headless --path . --script res://scripts/tower_gate_sync_selfcheck.gd
## Prints "SELFCHECK OK" and exits 0, or prints the first failure and exits 1.
##
## Bead godot-test1-d81: a gate one member works stayed a wall for the rest —
## the opened set was per peer. The shell now publishes one reliable `gate` verb
## per opening, the room repair packet carries the absolute set (`g`) and the
## join snapshot carries it (`go`), and every path lands through the shipped
## `_absorb_opened_gate()`. This file drives peer A's `mark_opened()` into peer
## B's shell through those shipped functions — never around them — with B's
## built interior asserting the mass really retires.
##
## TWO REAL TOWERS, SEQUENTIALLY. A opens and publishes; A is freed; B receives.
## Sequential because group "tower" names the shell the receiver writes through,
## and two live towers would make that lookup ambiguous — the same reason the
## checks free their tower before bailing (see `TowerProbe.clear`).
##
## Probes 0 and 0b need no tower: absorbing with no shell streamed in persists
## through the profile (and publishes from it), and every id the interior can
## open decodes. They run first, while group "tower" is provably empty.
##
## THE PROFILE IS A THROWAWAY. `mark_opened()` writes through to `BestRunStore`
## on the opening AND on a room absorb (the bead's default), so this check goes
## through `Sentinel.isolate_user_state()` first and `TowerProbe.fresh_store()`
## before any shell can exist — `progression_selfcheck.hermetic_stores` audits
## this file for both.
##
## Deliberately NOT localized (a debug surface, per CLAUDE.md).

## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")

const MPManager: GDScript = preload("res://scripts/mp_manager.gd")

## A manager reduced to the one method `tower_shell.mark_opened()` calls: it
## records what the shell publishes, the way the weather stub in mp_selfcheck
## records what the sky publishes.
const PUBLISH_STUB_SOURCE := """extends Node
var published: Array = []
func publish_gate_opened(id: String) -> void:
	published.append(id)
"""

## A built interior reduced to the one seam the absorb calls: it counts
## `_apply_opened()` re-runs, so the no-re-apply guard is measured directly.
const APPLY_STUB_SOURCE := """extends Node
var applies: int = 0
func _apply_opened() -> void:
	applies += 1
"""

## A streamed shell reduced to the absorb's three calls: it records what the
## absorb marks and whether each mark may publish, so the echo suppression is
## measured as arguments, not packets.
const RECORDING_SHELL_SOURCE := """extends Node
var calls: Array = []
func is_opened(id: String) -> bool:
	return false
func mark_opened(id: String, publish: bool = true) -> void:
	calls.append([id, publish])
"""


func _initialize() -> void:
	Sentinel.isolate_user_state()
	# _initialize() cannot await, so the measuring half runs as its own coroutine
	# and reports from in there — reporting here would print a verdict at frame 0.
	_run()


func _run() -> void:
	# THE STORE SEAM FIRST, before any shell can exist — see BestRunStore.config_path.
	TowerProbe.fresh_store()
	await process_frame
	var failure: String = await _check_no_shell()
	if failure.is_empty():
		failure = await _check_openable_ids_decode()
	if failure.is_empty():
		failure = await _check_publish_on_opening()
	if failure.is_empty():
		failure = await _check_live_receive()
	if failure.is_empty():
		failure = await _check_drops()
	if failure.is_empty():
		failure = await _check_hydration_sends_nothing()
	if failure.is_empty():
		failure = await _check_room_repair()
	if failure.is_empty():
		failure = await _check_snapshot_repair()
	if failure.is_empty():
		failure = await _check_join_publish()
	if failure.is_empty():
		failure = await _check_join_publish_pacing()
	if failure.is_empty():
		failure = await _check_opened_ids_sorted()
	if failure.is_empty():
		Sentinel.finish(self)
	else:
		printerr("SELFCHECK FAILED: " + failure)
		quit(1)


func _publish_stub() -> Node:
	"""A node in group "mp" recording what the shell publishes — see PUBLISH_STUB_SOURCE."""
	var stub_script := GDScript.new()
	stub_script.source_code = PUBLISH_STUB_SOURCE
	stub_script.reload()
	var stub: Node = stub_script.new()
	stub.add_to_group("mp")
	root.add_child(stub)
	return stub


func _mass_of(interior: Node, gate_id: String) -> MeshInstance3D:
	"""One gate's mass by GATE ID, never by box name — see tower_interior_selfcheck."""
	return interior.find_child("*GateMass_%s" % gate_id, true, false) as MeshInstance3D


func _check_no_shell() -> String:
	"""
	0. NO SHELL STREAMED IN. Every peer starts the run with no HQ in range, so
	absorbing then must still persist (the shell hydrates from the profile when
	it streams in) and the publish side must read the profile (or a master who
	has never visited the HQ repairs nothing). Runs first, while group "tower"
	is provably empty.
	"""
	if get_first_node_in_group("tower") != null:
		return "group 'tower' is not empty — this probe must run before any tower builds"
	var mp: Node = MPManager.new()
	root.add_child(mp)
	mp._absorb_opened_gate(TowerInterior.GATE_IDENTITY)
	if not BestRunStore.tower_opened_ids().has(TowerInterior.GATE_IDENTITY):
		mp.queue_free()
		return "an absorb with no shell dropped the id — nothing will hydrate it later"
	if not (mp._tower_opened_ids() as Array).has(TowerInterior.GATE_IDENTITY):
		mp.queue_free()
		return "the publish side is empty with no shell — a master there repairs nothing"
	# THE DISK STORM (review round 2): the same `g` twice must hit the store
	# ONCE. The file's mtime is the counter — no write, no touch — so the
	# first absorb must move it off zero (the setup proves a write happened)
	# and the second must leave it exactly alone.
	var t1: int = FileAccess.get_modified_time(BestRunStore.config_path)
	if t1 <= 0:
		mp.queue_free()
		return "the first absorb wrote nothing — the storm probe measured no setup"
	mp._absorb_opened_gates([TowerInterior.GATE_IDENTITY])
	var t2: int = FileAccess.get_modified_time(BestRunStore.config_path)
	if t2 != t1:
		mp.queue_free()
		return "re-absorbing the same set touched the profile again — the 2 Hz mirror is missing"
	if not (mp._absorbed_opened as Dictionary).has(TowerInterior.GATE_IDENTITY):
		mp.queue_free()
		return "the absorb never reached the mirror — the steady-state filter has nothing to consult"
	# ZERO OPS, not just zero writes: with the profile file deleted, a
	# steady-state absorb must not even re-read it (a read of the missing file
	# would come back empty and re-merge the id, recreating it).
	DirAccess.remove_absolute(BestRunStore.config_path)
	mp._absorb_opened_gates([TowerInterior.GATE_IDENTITY])
	if FileAccess.file_exists(BestRunStore.config_path):
		mp.queue_free()
		return "a steady-state absorb recreated a deleted profile — the filter re-reads at 2 Hz"
	# Restore what the probe deleted: later probes hydrate from this profile.
	BestRunStore.merge_tower_opened_ids([TowerInterior.GATE_IDENTITY])
	# JOIN SEEDS THE MIRROR: a profile id from before this process publishes
	# with no shell and no absorb — a master who never visits the HQ still
	# repairs the room from a returning profile.
	BestRunStore.merge_tower_opened_ids(["phase_grate"])
	var t2b: int = FileAccess.get_modified_time(BestRunStore.config_path)
	var mp2: Node = MPManager.new()
	root.add_child(mp2)
	# Relay-only: the join stops before the mesh (no STUN, no socket), but the
	# seed above runs identically — this poses the join, not the mesh.
	mp2.set("lobby_only", true)
	mp2._on_lobby_joined("us", "ROOM", "themaster", ["themaster", "us"])
	if not (mp2._tower_opened_ids() as Array).has("phase_grate"):
		mp2.queue_free()
		mp.queue_free()
		return "join did not seed the mirror — a returning profile publishes nothing shell-less"
	# ...and absorbing it after the seed writes nothing either: the seed is
	# the mirror fill, not just the publish read.
	mp2._absorb_opened_gates(["phase_grate"])
	var t3: int = FileAccess.get_modified_time(BestRunStore.config_path)
	if t3 != t2b:
		mp2.queue_free()
		mp.queue_free()
		return "absorbing a seeded id touched the profile — the seed did not fill the mirror"
	mp2.queue_free()
	# THE ECHO SUPPRESSION (review round 2, minor): the absorb marks with
	# publish=false, measured as arguments on a recording shell — a burst of
	# genuinely-new ids must put nothing back on the wire.
	var shell_script := GDScript.new()
	shell_script.source_code = RECORDING_SHELL_SOURCE
	shell_script.reload()
	var recorder: Node = shell_script.new()
	recorder.add_to_group("tower")
	root.add_child(recorder)
	mp._receive_gate("peerA", {"t": "gate", "id": "collapsed_slab"})
	var calls: Array = recorder.get("calls")
	recorder.remove_from_group("tower")
	recorder.queue_free()
	mp.queue_free()
	if calls != [["collapsed_slab", false]]:
		return "the absorb marked %s — it must mark with publish=false" % str(calls)
	Sentinel.done("no_shell")
	return ""


func _check_openable_ids_decode() -> String:
	"""
	0b. EVERY ID THE INTERIOR CAN OPEN DECODES. The range list is derived
	(checkpoint was omitted once: opened by const, published, dropped by every
	receiver), so this binds the open sites to the parser — a future id
	written into the set without a graph row fails here, not room-wide.
	"""
	var want: Array[String] = [
		TowerInterior.GATE_DEMAND, TowerInterior.GATE_IDENTITY,
		TowerInterior.GATE_CHECKPOINT, TowerInterior.RESCUE_DONE,
	]
	for door: Dictionary in TowerInterior.SPINE_DOORS:
		want.append(String(door["gate"]))
	for gid: String in TowerInterior.riddle_ids():
		want.append(gid)
	for sid: String in TowerGraph.scar_ids():
		want.append(sid)
	for row: Dictionary in TowerGraph.TOWER_GRAPH["entries"]:
		want.append(String(row.get("id", "")))
	for mut: Dictionary in TowerGraph.TOWER_GRAPH["mutations"]:
		want.append(String(mut.get("id", "")))
	for id: String in want:
		if id.is_empty():
			return "an open site produced an empty id — the enumeration above drifted"
		if not TowerGraph.opened_ids().has(id):
			return "id '%s' can be opened but is not in opened_ids() — receivers will drop it" % id
		if MpCodec.decode_gate({"t": "gate", "id": id}).is_empty():
			return "id '%s' is ranged but does not decode — the parser disagrees with the list" % id
	Sentinel.done("openable_ids_decode")
	return ""


func _check_publish_on_opening() -> String:
	"""
	1. THE SEND SITE. Peer A's shell publishes one `gate` verb per OPENING —
	and nothing on a re-mark.

	Hydration is probe 4's subject, not this one's: it writes `opened` directly
	and never comes through here.
	"""
	var shell := await TowerProbe.make_tower(self)
	var stub: Node = _publish_stub()
	shell.mark_opened(TowerInterior.GATE_DEMAND)
	if (stub.get("published") as Array) != [TowerInterior.GATE_DEMAND]:
		await TowerProbe.clear(self, null, shell)
		stub.queue_free()
		return "mark_opened published %s, expected exactly one gate verb" \
				% str(stub.get("published"))
	# Idempotent send: re-marking an open gate touches no disk AND no wire.
	shell.mark_opened(TowerInterior.GATE_DEMAND)
	shell.mark_opened(TowerInterior.GATE_CHECKPOINT)
	if (stub.get("published") as Array) \
			!= [TowerInterior.GATE_DEMAND, TowerInterior.GATE_CHECKPOINT]:
		await TowerProbe.clear(self, null, shell)
		stub.queue_free()
		return "a re-mark published again — the send site is not on the opening only"
	# The publish flag (review round 2): an absorbed opening suppresses the
	# re-broadcast while a local one still sends.
	shell.mark_opened("maintenance_crawl", false)
	if (stub.get("published") as Array) \
			!= [TowerInterior.GATE_DEMAND, TowerInterior.GATE_CHECKPOINT]:
		await TowerProbe.clear(self, null, shell)
		stub.queue_free()
		return "mark_opened(id, false) published — the shell ignores the absorb flag"
	shell.mark_opened("updraft_shaft")
	if (stub.get("published") as Array) \
			!= [TowerInterior.GATE_DEMAND, TowerInterior.GATE_CHECKPOINT, "updraft_shaft"]:
		await TowerProbe.clear(self, null, shell)
		stub.queue_free()
		return "a local opening stopped publishing — the flag's default flipped"
	stub.queue_free()
	await TowerProbe.clear(self, null, shell)
	Sentinel.done("publish_on_opening")
	return ""


func _check_live_receive() -> String:
	"""
	2. THE LIVE VERB, END TO END. Peer B's manager takes A's opening through the
	shipped `_receive_gate()` — the shell opens, the built interior re-runs
	`_apply_opened()` so the mass retires HERE, and the profile gains the id.

	B already holds one local opening: the union keeps it, because entering a
	room resets nothing.
	"""
	TowerProbe.fresh_store()
	var shell := await TowerProbe.make_tower(self)
	var interior := shell.get_node_or_null("TowerInterior")
	if interior == null:
		await TowerProbe.clear(self, null, shell)
		return "the tower has no TowerInterior child — the re-apply has no subject"
	var mass := _mass_of(interior, TowerInterior.GATE_IDENTITY)
	if mass == null:
		await TowerProbe.clear(self, null, shell)
		return "the tower built no identity mass — the geometry assertion has no subject"
	var rest_y: float = mass.position.y
	# One local opening first: the union is what the ruling asks for, so a room
	# absorb must ADD, never replace.
	shell.mark_opened(TowerInterior.GATE_CHECKPOINT)
	var mp: Node = MPManager.new()
	root.add_child(mp)
	mp._receive_gate("peerA", {"t": "gate", "id": TowerInterior.GATE_IDENTITY})
	if not shell.is_opened(TowerInterior.GATE_IDENTITY):
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "the room's opening never reached B's shell"
	if not shell.is_opened(TowerInterior.GATE_CHECKPOINT):
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "absorbing the room's set dropped B's own opening — the union replaced"
	if float(interior.get("_mass_open")) != 1.0:
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "B's interior never re-ran _apply_opened — the mass is retired on A only"
	if mass.position.y <= rest_y:
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "B's mass state is open but its mesh never rose — state did not become geometry"
	if not BestRunStore.tower_opened_ids().has(TowerInterior.GATE_IDENTITY):
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "the room's opening was drawn but never persisted — a relaunch re-locks it"
	# AN ALREADY-OPEN ID RE-APPLIES NOTHING (review round 1): the master's 2 Hz
	# repair would otherwise reset riddle progress twice a second and republish
	# the id. Three poses, from coarse to precise: a counting stub proves the
	# call never happens; a mid-entry combination proves the progress survives;
	# a NEW id proves a genuine opening still re-applies without clobbering an
	# unrelated in-progress lock (the scoped reset).
	var meshes: Dictionary = interior.get("_riddle_meshes")
	if meshes.is_empty():
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "the tower built no riddle locks — the re-apply guard has no subject"
	var lock: String = String((meshes.keys() as Array)[0])
	(interior.get("_riddle_step") as Dictionary)[lock] = 2
	var counter_script := GDScript.new()
	counter_script.source_code = APPLY_STUB_SOURCE
	counter_script.reload()
	var counter: Node = counter_script.new()
	interior.remove_from_group("tower_interior")
	counter.add_to_group("tower_interior")
	root.add_child(counter)
	mp._receive_gate("peerA", {"t": "gate", "id": TowerInterior.GATE_IDENTITY})
	if int(counter.get("applies")) != 0:
		counter.queue_free()
		interior.add_to_group("tower_interior")
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "absorbing an already-open id re-ran _apply_opened — the guard is missing"
	counter.queue_free()
	interior.add_to_group("tower_interior")
	if int((interior.get("_riddle_step") as Dictionary).get(lock, 0)) != 2:
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "absorbing an already-open id reset a mid-entry combination"
	mp._receive_gate("peerA", {"t": "gate", "id": "maintenance_crawl"})
	if int((interior.get("_riddle_step") as Dictionary).get(lock, 0)) != 2:
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "a genuine opening reset an unrelated in-progress combination — the reset is not scoped"
	if not shell.is_opened("maintenance_crawl"):
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "a genuine opening stopped being absorbed — the guard over-fires"
	mp.queue_free()
	await TowerProbe.clear(self, null, shell)
	Sentinel.done("live_receive")
	return ""


func _check_drops() -> String:
	"""
	3. MALFORMED AND UNKNOWN IDS ARE DROPPED — through the shipped receive path,
	so a stranger cannot open (or persist) anything, and a build that authors a
	gate this one never heard of honours nothing.
	"""
	TowerProbe.fresh_store()
	var shell := await TowerProbe.make_tower(self)
	var interior := shell.get_node_or_null("TowerInterior")
	var mp: Node = MPManager.new()
	root.add_child(mp)
	var hostile: Array[Dictionary] = [
		{"t": "gate"},
		{"t": "gate", "id": 7},
		{"t": "gate", "id": ""},
		{"t": "gate", "id": "tower_monthly_special"},
		{"t": "gate", "id": "x".repeat(MpCodec.MAX_GATE_ID + 1)},
	]
	for packet: Dictionary in hostile:
		mp._receive_gate("peerA", packet)
		if not shell.opened_ids().is_empty():
			mp.queue_free()
			await TowerProbe.clear(self, null, shell)
			return "the hostile packet %s opened something" % str(packet)
		if not BestRunStore.tower_opened_ids().is_empty():
			mp.queue_free()
			await TowerProbe.clear(self, null, shell)
			return "the hostile packet %s persisted something" % str(packet)
	if interior != null and float(interior.get("_mass_open")) != 0.0:
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "a hostile packet moved B's interior — the re-apply ran on a drop"
	mp.queue_free()
	await TowerProbe.clear(self, null, shell)
	Sentinel.done("drops")
	return ""


func _check_hydration_sends_nothing() -> String:
	"""
	4. HYDRATION IS SILENT. A tower built over a profile that already holds
	openings comes up open — and publishes nothing: hydration writes `opened`
	directly and never comes through `mark_opened()`.

	The profile is seeded through the shipped store merge — the same write a
	local opening performs — so what the tower builds over is earned state.
	"""
	BestRunStore.merge_tower_opened_ids([TowerInterior.GATE_IDENTITY])
	# The stub predates the build: hydration runs inside `make_tower`, so a stub
	# added after it could never hear a hydration publish.
	var stub: Node = _publish_stub()
	var shell := await TowerProbe.make_tower(self)
	if not shell.is_opened(TowerInterior.GATE_IDENTITY):
		await TowerProbe.clear(self, null, shell)
		stub.queue_free()
		return "the tower did not hydrate the profile's openings — the union forgot"
	await process_frame
	if not (stub.get("published") as Array).is_empty():
		await TowerProbe.clear(self, null, shell)
		stub.queue_free()
		return "building over stored openings published %s — hydration reached the wire" \
				% str(stub.get("published"))
	stub.queue_free()
	await TowerProbe.clear(self, null, shell)
	Sentinel.done("hydration_sends_nothing")
	return ""


func _check_room_repair() -> String:
	"""
	5. THE `room` REPAIR SET. The master's absolute `g` opens through the shipped
	`_receive_room()`; an id no build authored is skipped, not fatal.
	"""
	TowerProbe.fresh_store()
	var shell := await TowerProbe.make_tower(self)
	var mp: Node = MPManager.new()
	root.add_child(mp)
	mp._master = "themaster"
	mp._receive_room("themaster", {"t": "room", "cap": [], "cd": 0.0, "co": 0,
		"g": ["maintenance_crawl", "tower_monthly_special"]})
	if not shell.is_opened("maintenance_crawl"):
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "the master's repair set never reached the shell"
	if shell.is_opened("tower_monthly_special"):
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "the repair set opened an id no build authored — the whitelist is not applied"
	mp.queue_free()
	await TowerProbe.clear(self, null, shell)
	Sentinel.done("room_repair")
	return ""


func _check_snapshot_repair() -> String:
	"""
	6. THE JOIN SNAPSHOT'S ABSOLUTE SET. The master's `go` opens through the
	shipped `_receive_state()`; a stranger's is not a contribution; a snapshot
	without `go` leaves the set exactly as it found it.
	"""
	TowerProbe.fresh_store()
	var shell := await TowerProbe.make_tower(self)
	shell.mark_opened(TowerInterior.GATE_CHECKPOINT)
	var mp: Node = MPManager.new()
	root.add_child(mp)
	mp._master = "themaster"
	var base := {"cc": 0.0, "dd": 0.0, "px": 0.0, "py": 0.0, "pz": 0.0, "ids": []}
	var stranger: Dictionary = base.duplicate()
	stranger["go"] = ["phase_grate"]
	mp._receive_state("someoneelse", MpCodec.decode_state(stranger))
	if shell.is_opened("phase_grate"):
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "a stranger's snapshot opened a gate — the master-only repair is bypassable"
	var ruling: Dictionary = base.duplicate()
	ruling["go"] = ["updraft_shaft"]
	mp._receive_state("themaster", MpCodec.decode_state(ruling))
	if not shell.is_opened("updraft_shaft"):
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "the master's snapshot did not hand the joiner the opened set"
	var bare: Dictionary = MpCodec.decode_state(base)
	mp._receive_state("themaster", bare)
	if not shell.is_opened("updraft_shaft") \
			or not shell.is_opened(TowerInterior.GATE_CHECKPOINT):
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "a snapshot without go reset the set — joining is not a wipe"
	mp.queue_free()
	await TowerProbe.clear(self, null, shell)
	Sentinel.done("snapshot_repair")
	return ""


func _check_join_publish() -> String:
	"""
	7. THE JOINER'S OWN SET, ONCE PER JOIN (review round 3). A veteran
	joiner's persisted gates reach the room through the paced `gate` drain —
	a joiner holding one id the master has never seen puts it on the master's
	shell, and the master's next `g` carries it.

	Transport is a loopback: the joiner's sends have no live mesh or relay
	headless (both legs null-guard to silence), so each id the drain pops is
	fed to the master's shipped `_receive_gate()` by hand — every line either
	side of the wire is shipped code, only the air between them is the test's.
	"""
	TowerProbe.fresh_store()
	# The veteran's past: one id no room has ever seen.
	BestRunStore.merge_tower_opened_ids(["maintenance_crawl"])
	var joiner: Node = MPManager.new()
	root.add_child(joiner)
	joiner.set("lobby_only", true)
	joiner._on_lobby_joined("us", "ROOM", "themaster", ["themaster", "us"])
	# Unsettled: no snapshots, no deadline — priming must wait for the join.
	joiner._tick_join_gate_publish(10.0)
	if bool(joiner.get("_join_gate_primed")):
		joiner.queue_free()
		return "the join publish primed before the join settled — it races the master's snapshot"
	# The deadline-spent settle, the honest snapshots-never-arrived path.
	joiner.set("_join_wait", MPManager.JOIN_SNAPSHOT_WAIT)
	# A sub-pace tick primes but sends nothing: the queue is the whole own
	# set, exactly once.
	joiner._tick_join_gate_publish(0.1)
	if not bool(joiner.get("_join_gate_primed")):
		joiner.queue_free()
		return "a settled join never primed its publish — the veteran's set stays one-sided"
	var queue: Array = (joiner.get("_join_gate_queue") as Array).duplicate()
	if queue != ["maintenance_crawl"]:
		joiner.queue_free()
		return "priming queued %s — the joiner's own set, once, is the whole contribution" % str(queue)
	# Past the pace the id drains; the loopback hands it to the master.
	joiner._tick_join_gate_publish(0.2)
	if not (joiner.get("_join_gate_queue") as Array).is_empty():
		joiner.queue_free()
		return "a paced tick drained nothing — the queue never reaches the wire"
	joiner.queue_free()
	# The master's room has never seen the id: fresh profile, real tower.
	TowerProbe.fresh_store()
	var shell := await TowerProbe.make_tower(self)
	var master: Node = MPManager.new()
	root.add_child(master)
	master._receive_gate("us", {"t": "gate", "id": "maintenance_crawl"})
	if not shell.is_opened("maintenance_crawl"):
		master.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "the joiner's persisted id never reached the master's shell"
	# ...and the master's next `g` carries it: the repair payload IS
	# `_tower_opened_ids()`, so membership there is membership on the wire.
	if not (master._tower_opened_ids() as Array).has("maintenance_crawl"):
		master.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "the master absorbed the id but its publish side lacks it — the next `g` would not carry the union"
	master.queue_free()
	await TowerProbe.clear(self, null, shell)
	Sentinel.done("join_publish")
	return ""


func _check_join_publish_pacing() -> String:
	"""
	8. PACED UNDER 4/s. The drain spaces sends at one per 0.25 s and never
	puts more than the window max inside a trailing second — a 5th `gate`
	inside one window is dropped by every receiver and never re-sent.

	No wall clock: twenty 5 s ticks run inside one millisecond, so the pace
	clock says yes to all of them and only the trailing-second cap may say
	no. Eight ids go in; exactly four may come out in the burst.
	"""
	TowerProbe.fresh_store()
	var ids: Array = (TowerGraph.opened_ids() as Array).slice(0, 8)
	if ids.size() != 8:
		return "the build authors fewer than 8 gate ids — the pacing probe has no burst to shape"
	BestRunStore.merge_tower_opened_ids(ids)
	var joiner: Node = MPManager.new()
	root.add_child(joiner)
	joiner.set("lobby_only", true)
	joiner._on_lobby_joined("us", "ROOM", "themaster", ["themaster", "us"])
	joiner.set("_join_wait", MPManager.JOIN_SNAPSHOT_WAIT)
	joiner._tick_join_gate_publish(0.1)
	if (joiner.get("_join_gate_queue") as Array).size() != 8:
		joiner.queue_free()
		return "priming queued %d of 8 — the drain does not carry the whole set" \
				% (joiner.get("_join_gate_queue") as Array).size()
	for i in range(20):
		joiner._tick_join_gate_publish(5.0)
	var left: int = (joiner.get("_join_gate_queue") as Array).size()
	joiner.queue_free()
	if left != 4:
		return "a same-second burst drained %d of 8 — the trailing-second cap is missing" % (8 - left)
	Sentinel.done("join_publish_pacing")
	return ""


func _check_opened_ids_sorted() -> String:
	"""
	9. SORTED WITH NO SHELL (review round 3, minor). `_tower_opened_ids()`
	promises the whole sorted set; the mirror fills in absorb order — a
	sorted profile prefix with an arbitrary tail — so the no-shell branch
	must sort before returning, like `tower_shell.opened_ids()` does.
	"""
	TowerProbe.fresh_store()
	BestRunStore.merge_tower_opened_ids(["maintenance_crawl"])
	var mp: Node = MPManager.new()
	root.add_child(mp)
	mp.set("lobby_only", true)
	mp._on_lobby_joined("us", "ROOM", "themaster", ["themaster", "us"])
	# Sorts BEFORE the seeded id but absorbs AFTER it: the mirror holds
	# insertion order, the getter must not.
	mp._absorb_opened_gate("collapsed_slab")
	var got: Array = mp._tower_opened_ids()
	mp.queue_free()
	if got != ["collapsed_slab", "maintenance_crawl"]:
		return "no-shell opened ids came back %s — the sorted-set promise is broken" % str(got)
	Sentinel.done("opened_ids_sorted")
	return ""
