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
	mp.queue_free()
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
