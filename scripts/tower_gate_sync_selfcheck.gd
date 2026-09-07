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
## Bead godot-test1-crk (owner ruling 2026-09-07 10:47, reversing d81's
## write-through default): a teammate's opening is ROOM-ONLY — open for the
## session, never written to this peer's profile. Absorb paths mark with
## `persist = false` and the no-shell branch writes nothing; the mirror is
## the one home of room-opened ids, a late shell pulls it in `_enter_tree`,
## and `leave()` re-hydrates the shell from the profile alone so room ids
## fall closed. Only a LOCAL opening persists (earned here).
##
## TWO REAL TOWERS, SEQUENTIALLY. A opens and publishes; A is freed; B receives.
## Sequential because group "tower" names the shell the receiver writes through,
## and two live towers would make that lookup ambiguous — the same reason the
## checks free their tower before bailing (see `TowerProbe.clear`).
##
## Probes 0 and 0b need no tower: absorbing with no shell streamed in holds
## the id in the mirror only (and publishes from it), and every id the
## interior can open decodes. They run first, while group "tower" is
## provably empty.
##
## THE PROFILE IS A THROWAWAY. A LOCAL `mark_opened()` writes through to
## `BestRunStore` on the opening, so this check goes through
## `Sentinel.isolate_user_state()` first and `TowerProbe.fresh_store()`
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
const LiftMenu: GDScript = preload("res://scripts/tower_lift_menu.gd")

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
## absorb marks and whether each mark may publish or persist, so the echo
## suppression AND the batch write-silence are measured as arguments, not
## packets.
const RECORDING_SHELL_SOURCE := """extends Node
var calls: Array = []
func is_opened(id: String) -> bool:
	return false
func mark_opened(id: String, publish: bool = true, persist: bool = true) -> void:
	calls.append([id, publish, persist])
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
		failure = await _check_live_opening_beats_drain()
	if failure.is_empty():
		failure = await _check_publish_filters_poison()
	if failure.is_empty():
		failure = await _check_batch_persists_once()
	if failure.is_empty():
		failure = await _check_leave_closes_room_gates()
	if failure.is_empty():
		failure = await _check_leave_inside_defers_close()
	if failure.is_empty():
		failure = await _check_earn_while_room_open()
	if failure.is_empty():
		failure = await _check_rescan_refires_triggers()
	if failure.is_empty():
		failure = await _check_join_cancels_deferred_close()
	if failure.is_empty():
		failure = await _check_absorbed_never_persists()
	if failure.is_empty():
		failure = await _check_drain_publishes_own_only()
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
	absorbing then must hold the id in the MIRROR (a shell that streams in
	later pulls it in `_enter_tree`) and the publish side must read the
	mirror (or a master who has never visited the HQ repairs nothing). The
	profile is NOT touched: a teammate's opening is session state (bead
	godot-test1-crk). Runs first, while group "tower" is provably empty.
	"""
	if get_first_node_in_group("tower") != null:
		return "group 'tower' is not empty — this probe must run before any tower builds"
	var mp: Node = MPManager.new()
	root.add_child(mp)
	mp._absorb_opened_gate(TowerInterior.GATE_IDENTITY)
	if BestRunStore.tower_opened_ids().has(TowerInterior.GATE_IDENTITY):
		mp.queue_free()
		return "an absorb with no shell reached the profile — a teammate's opening is room-only, not saved"
	if not (mp._absorbed_opened as Dictionary).has(TowerInterior.GATE_IDENTITY):
		mp.queue_free()
		return "an absorb with no shell dropped the id — nothing will hydrate it later"
	if not (mp._tower_opened_ids() as Array).has(TowerInterior.GATE_IDENTITY):
		mp.queue_free()
		return "the publish side is empty with no shell — a master there repairs nothing"
	# NO DISK AT ALL (bead godot-test1-crk, stronger than review round 2's
	# once): the same `g` twice must not touch the store, ever. The file's
	# mtime is the counter — no write, no touch. The profile starts DELETED
	# (fresh store), so any write would create it.
	mp._absorb_opened_gates([TowerInterior.GATE_IDENTITY])
	if FileAccess.file_exists(BestRunStore.config_path):
		mp.queue_free()
		return "absorbing the room's set created a profile — the 2 Hz path persists room state"
	# ZERO OPS on the steady state: absorbing again touches nothing — no
	# store read, no store write, no shell call.
	mp._absorb_opened_gates([TowerInterior.GATE_IDENTITY])
	if FileAccess.file_exists(BestRunStore.config_path):
		mp.queue_free()
		return "a steady-state absorb recreated a deleted profile — the filter re-reads at 2 Hz"
	# Restore an OWNED id for later probes: they hydrate from this profile.
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
	# publish=false (the echo suppression) AND persist=false (the room-only
	# rule, bead godot-test1-crk): no absorb path may grow the profile.
	if calls != [["collapsed_slab", false, false]]:
		return "the absorb marked %s — it must mark with publish=false, persist=false" % str(calls)
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
	`_apply_opened()` so the mass retires HERE, and the profile does NOT gain
	the id (room-only, bead godot-test1-crk).

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
	if BestRunStore.tower_opened_ids().has(TowerInterior.GATE_IDENTITY):
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "the room's opening reached B's profile — a teammate's gate is room-only, never saved"
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
	# Past the pace (0.5 s) the id drains; the loopback hands it to the master.
	joiner._tick_join_gate_publish(0.5)
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
	8. PACED UNDER HALF THE BUDGET. The drain spaces sends at one per 0.5 s
	and never puts more than the window max (2) inside a trailing second —
	a live opening fired mid-drain is the 3rd send in the window, not the
	5th, so every receiver keeps it (review round 4, major).

	No wall clock: twenty 5 s ticks run inside one millisecond, so the pace
	clock says yes to all of them and only the trailing-second cap may say
	no. Eight ids go in; exactly two may come out in the burst.
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
	if left != 6:
		return "a same-second burst drained %d of 8 — the window cap is not holding at 2" % (8 - left)
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


func _check_live_opening_beats_drain() -> String:
	"""
	10. A LIVE OPENING FIRED MID-DRAIN ARRIVES (review round 4, major). The
	drain spends half the receiver's `gate` budget; a live opening is the
	3rd send in the window, and the drain yields after it instead of
	starving it.

	Seven persisted ids prime the drain; two paced ticks move two; a live
	`publish_gate_opened` fires; three more paced ticks must move NOTHING
	(the live send filled the window — latency for the queued five, never a
	lost opening). A stub receiver running the REAL `_verb_rate_ok` votes on
	the three sends in order: all three must be admitted.
	"""
	TowerProbe.fresh_store()
	var ids: Array = (TowerGraph.opened_ids() as Array).slice(0, 8)
	if ids.size() != 8:
		return "the build authors fewer than 8 gate ids — the live-mid-drain probe has no burst to shape"
	BestRunStore.merge_tower_opened_ids(ids.slice(0, 7))
	var live_id := String(ids[7])
	# The queue drains in SORTED order (the no-shell branch sorts), so the
	# two moved ids are the sorted-first two, whatever the store did.
	var ordered: Array = ids.slice(0, 7).duplicate()
	ordered.sort()
	var joiner: Node = MPManager.new()
	root.add_child(joiner)
	joiner.set("lobby_only", true)
	joiner._on_lobby_joined("us", "ROOM", "themaster", ["themaster", "us"])
	joiner.set("_join_wait", MPManager.JOIN_SNAPSHOT_WAIT)
	# Prime and move two: the window holds exactly two.
	joiner._tick_join_gate_publish(0.5)
	joiner._tick_join_gate_publish(0.5)
	if (joiner.get("_join_gate_queue") as Array).size() != 5:
		joiner.queue_free()
		return "two paced ticks moved %d of 7 — the pace clock is not spacing at 0.5 s" \
				% (7 - (joiner.get("_join_gate_queue") as Array).size())
	# The live opening: always sent, always tracked.
	joiner.publish_gate_opened(live_id)
	# Three paced ticks past a full window must yield, not drop: the five
	# stay queued, every one of them, in order.
	for i in range(3):
		joiner._tick_join_gate_publish(0.5)
	var queue: Array = joiner.get("_join_gate_queue")
	joiner.queue_free()
	if queue != ordered.slice(2, 7):
		return "the drain moved %s past a live opening — it starves instead of yielding" % str(queue)
	# ...and the receiver's REAL budget admits all three sends: the live one
	# is spent 2, not spent 4.
	var receiver: Node = MPManager.new()
	root.add_child(receiver)
	var votes: Array = []
	# One vote per arrival, in arrival order: two drain sends, then live.
	for arrival: String in [String(ordered[0]), String(ordered[1]), live_id]:
		votes.append(receiver._verb_rate_ok("peerJ", "gate") and not arrival.is_empty())
	receiver.queue_free()
	if votes != [true, true, true]:
		return "a stub receiver dropped a mid-drain send %s — the live opening dies room-wide" % str(votes)
	Sentinel.done("live_opening_beats_drain")
	return ""


func _check_publish_filters_poison() -> String:
	"""
	11. THE PUBLISH SIDE FILTERS A POISONED PROFILE (review round 4, minor).
	An over-long and a foreign row in the store must not reach `g`/`go` —
	the receivers' parsers drop the WHOLE repair packet on one bad entry,
	which would kill the room's captive and explored repairs with it.
	"""
	TowerProbe.fresh_store()
	BestRunStore.merge_tower_opened_ids(["maintenance_crawl", "x".repeat(100), "tower_monthly_special"])
	var mp: Node = MPManager.new()
	root.add_child(mp)
	mp.set("lobby_only", true)
	mp._on_lobby_joined("us", "ROOM", "themaster", ["themaster", "us"])
	# No shell: the mirror holds the mess (seed validates nothing), the
	# getter must not.
	if (mp._tower_opened_ids() as Array) != ["maintenance_crawl"]:
		mp.queue_free()
		return "no-shell publish ids came back %s — a poisoned row rides g/go" \
				% str(mp._tower_opened_ids())
	mp.queue_free()
	# Streamed shell: hydration holds the same mess, same filter.
	var shell := await TowerProbe.make_tower(self)
	var mp2: Node = MPManager.new()
	root.add_child(mp2)
	var got: Array = mp2._tower_opened_ids()
	mp2.queue_free()
	await TowerProbe.clear(self, null, shell)
	if got != ["maintenance_crawl"]:
		return "shelled publish ids came back %s — hydration poison rides g/go" % str(got)
	Sentinel.done("publish_filters_poison")
	return ""


func _check_batch_persists_once() -> String:
	"""
	12. ONE REPAIR, ZERO STORE WRITES (bead godot-test1-crk, replacing review
	round 4's one-write rule). The batch absorb folds the packet into the
	mirror only; the shell tail marks with `persist = false`, so three fresh
	ids cost nothing on disk however many arrive.

	Write-count reasoning, stated plainly: the profile starts DELETED, so any
	write would create it — and none may. The tails are pinned by ARGUMENTS
	on a recording shell (`persist = false` on every mark). A revert of
	either half fails below.
	"""
	TowerProbe.fresh_store()
	var ids: Array = (TowerGraph.opened_ids() as Array).slice(0, 3)
	# Six: three for the recording shell's argument assert, three more the
	# recorder never saw for the real shell's geometry assert.
	if (TowerGraph.opened_ids() as Array).size() < 6:
		return "the build authors fewer than 6 gate ids — the batch probe has no packet to fold"
	var mp: Node = MPManager.new()
	root.add_child(mp)
	var shell_script := GDScript.new()
	shell_script.source_code = RECORDING_SHELL_SOURCE
	shell_script.reload()
	var recorder: Node = shell_script.new()
	recorder.add_to_group("tower")
	root.add_child(recorder)
	mp._absorb_opened_gates(ids)
	var calls: Array = recorder.get("calls")
	recorder.remove_from_group("tower")
	recorder.queue_free()
	var want: Array = []
	for gid: String in ids:
		want.append([gid, false, false])
	if calls != want:
		mp.queue_free()
		return "the batch tail marked %s — every mark must carry publish=false, persist=false" % str(calls)
	# Zero writes: the profile did not exist before the packet (fresh store)
	# and must not exist after it — the room's set lives in the mirror.
	if FileAccess.file_exists(BestRunStore.config_path):
		mp.queue_free()
		return "absorbing three fresh ids created a profile — the batch merge persists room state"
	# ...while the mirror holds all three: silencing the disk must not
	# silence the packet.
	for gid: String in ids:
		if not (mp._absorbed_opened as Dictionary).has(gid):
			mp.queue_free()
			return "the batch absorb lost %s — the mirror did not cover the packet" % gid
	mp.queue_free()
	# The real shell opens all three off the same path (no recorder this time).
	var shell := await TowerProbe.make_tower(self)
	var mp2: Node = MPManager.new()
	root.add_child(mp2)
	mp2._absorb_opened_gates((TowerGraph.opened_ids() as Array).slice(3, 6))
	var ok := true
	for gid: String in (TowerGraph.opened_ids() as Array).slice(3, 6):
		ok = ok and shell.is_opened(gid)
	mp2.queue_free()
	await TowerProbe.clear(self, null, shell)
	if not ok:
		return "a batch absorb with persist=false left a real shell closed — the flag gates geometry"
	Sentinel.done("batch_persists_once")
	return ""


func _check_leave_closes_room_gates() -> String:
	"""
	13. LEAVE OUTSIDE FALLS THE ROOM'S GATES CLOSED (bead godot-test1-crk).
	While in the room a teammate's ids open this shell — the mass retires,
	the lift offers the stop. The shipped `leave()` re-hydrates the shell
	from the profile alone and re-runs `_apply_opened()`: the teammate's ids
	close (mass BACK, stop no longer offered) while this peer's own earned
	opening stays open, lit and persisted. No player node exists in this
	probe, which reads as outside — the inside case is probe 13b.
	"""
	TowerProbe.fresh_store()
	var shell := await TowerProbe.make_tower(self)
	var interior := shell.get_node_or_null("TowerInterior")
	if interior == null:
		await TowerProbe.clear(self, null, shell)
		return "the tower has no TowerInterior child — the leave probe has no subject"
	var mass := _mass_of(interior, TowerInterior.GATE_IDENTITY)
	if mass == null:
		await TowerProbe.clear(self, null, shell)
		return "the tower built no identity mass — the leave probe has no geometry"
	var rest_y: float = mass.position.y
	# Own first: earned here, persisted, must survive the leave.
	shell.mark_opened(TowerInterior.GATE_CHECKPOINT)
	var mp: Node = MPManager.new()
	root.add_child(mp)
	mp.set("lobby_only", true)
	mp._on_lobby_joined("us", "ROOM", "themaster", ["themaster", "us"])
	# Teammate's: mass plus a lift stop, through the shipped receive path.
	mp._receive_gate("peerA", {"t": "gate", "id": TowerInterior.GATE_IDENTITY})
	mp._receive_gate("peerA", {"t": "gate", "id": TowerGraph.ENTRY_LIFT_MAZE})
	if float(interior.get("_mass_open")) != 1.0 or mass.position.y <= rest_y:
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "the room's opening never retired B's mass — the leave probe measured no setup"
	var maze_floor: int = TowerInterior.landing_floor(
		String(TowerGraph.entry(TowerGraph.ENTRY_LIFT_MAZE).get("room", "")))
	var panel: Control = Control.new()
	panel.set_script(LiftMenu)
	root.add_child(panel)
	await process_frame
	if not (panel.stop_floors() as Array).has(maze_floor):
		panel.queue_free()
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "the room's entry opened but the lift offers no stop — the leave probe measured no setup"
	# LEAVE, through the shipped teardown — not around it.
	mp.leave()
	if shell.is_opened(TowerInterior.GATE_IDENTITY) \
			or shell.is_opened(TowerGraph.ENTRY_LIFT_MAZE):
		panel.queue_free()
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "leave kept a teammate's gate open — the room's set outlived the room"
	if not shell.is_opened(TowerInterior.GATE_CHECKPOINT):
		panel.queue_free()
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "leave closed B's own checkpoint — the re-hydrate is a wipe, not a union with the profile"
	if float(interior.get("_mass_open")) != 0.0 or mass.position.y != rest_y:
		panel.queue_free()
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "leave dropped the id but the mass never came back — _apply_opened only opens"
	if (panel.stop_floors() as Array).has(maze_floor):
		panel.queue_free()
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "leave closed the entry but the lift still offers its stop — the offer reads stale state"
	var stored: Array = BestRunStore.tower_opened_ids()
	if stored.has(TowerInterior.GATE_IDENTITY) \
			or stored.has(TowerGraph.ENTRY_LIFT_MAZE):
		panel.queue_free()
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "a teammate's id reached the profile %s — the room wrote through" % str(stored)
	if not stored.has(TowerInterior.GATE_CHECKPOINT):
		panel.queue_free()
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "B's own opening never persisted — earned state was lost with the room"
	panel.queue_free()
	mp.queue_free()
	await TowerProbe.clear(self, null, shell)
	Sentinel.done("leave_closes_room_gates")
	return ""


func _check_leave_inside_defers_close() -> String:
	"""
	13b. LEAVE INSIDE HOLDS THE GATES OPEN (review round 1, critical): snapping
	gates shut under a player standing in the HQ seals rooms whose pads sit on
	the far side of their own doors — a softlock, and `leave()` is also reached
	involuntarily from `_on_lobby_closed`. So `leave()` with the local player
	inside the walls only parks the close on the shell: the teammate's ids stay
	OPEN (and unsaved), and the interior's per-frame tick runs the re-hydrate +
	close-snap the moment the player is outside. Exiting the walls is driven
	here by moving the body and calling the shipped `_tick_room_close()`
	directly — the tick is the transition, not the frame that carries it.
	"""
	TowerProbe.fresh_store()
	var shell := await TowerProbe.make_tower(self)
	var interior := shell.get_node_or_null("TowerInterior")
	if interior == null:
		await TowerProbe.clear(self, null, shell)
		return "the tower has no TowerInterior child — the deferral probe has no subject"
	# The local player, standing in the building's middle.
	var player := Node3D.new()
	player.add_to_group("player")
	root.add_child(player)
	player.global_position = interior.global_position
	await process_frame
	var mp: Node = MPManager.new()
	root.add_child(mp)
	mp.set("lobby_only", true)
	mp._on_lobby_joined("us", "ROOM", "themaster", ["themaster", "us"])
	mp._receive_gate("peerA", {"t": "gate", "id": TowerInterior.GATE_IDENTITY})
	if not shell.is_opened(TowerInterior.GATE_IDENTITY):
		player.queue_free()
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "the room's opening never reached the shell — the deferral probe measured no setup"
	# LEAVE WHILE INSIDE, through the shipped teardown.
	mp.leave()
	if not shell.is_opened(TowerInterior.GATE_IDENTITY):
		player.queue_free()
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "leave snapped a teammate's gate shut under a player inside the HQ — sealed rooms softlock"
	if float(interior.get("_mass_open")) != 1.0:
		player.queue_free()
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "leave retired the mass with the player inside — the deferral held the set but not the geometry"
	if BestRunStore.tower_opened_ids().has(TowerInterior.GATE_IDENTITY):
		player.queue_free()
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "the deferred close persisted the room's id — the deferral holds geometry open, never persistence"
	# OUT THROUGH THE DOOR: the shipped tick fires the close on the first
	# frame outside.
	player.global_position = interior.global_position + Vector3(5000.0, 0.0, 0.0)
	await process_frame
	interior._tick_room_close()
	if shell.is_opened(TowerInterior.GATE_IDENTITY):
		player.queue_free()
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "exiting the walls left the teammate's gate open — the deferred close never fired"
	if float(interior.get("_mass_open")) != 0.0:
		player.queue_free()
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "exiting the walls dropped the id but the mass never came back — the deferred snap opens only"
	if BestRunStore.tower_opened_ids().has(TowerInterior.GATE_IDENTITY):
		player.queue_free()
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "the deferred close wrote the room's id to the profile — it must fall closed unsaved"
	player.queue_free()
	mp.queue_free()
	await TowerProbe.clear(self, null, shell)
	Sentinel.done("leave_inside_defers_close")
	return ""


func _check_earn_while_room_open() -> String:
	"""
	13c. A GATE THE ROOM OPENED CAN STILL BE EARNED (review round 1, minor).
	The shell keeps `earned` beside `opened`, and the earn sites gate on it:
	working a pad (or trigger) the room already opened persists the id all
	the same. Driven two ways — the one-shot enter handlers directly, with a
	player body, and the polled pad sites by text-scan in the suite's
	voice_selfcheck idiom (their pad-overlap state is not drivable headless).
	"""
	TowerProbe.fresh_store()
	var shell := await TowerProbe.make_tower(self)
	var interior := shell.get_node_or_null("TowerInterior")
	if interior == null:
		await TowerProbe.clear(self, null, shell)
		return "the tower has no TowerInterior child — the earn probe has no subject"
	var mp: Node = MPManager.new()
	root.add_child(mp)
	# Teammate opens the checkpoint and the maze stop; neither is earned here.
	mp._receive_gate("peerA", {"t": "gate", "id": TowerInterior.GATE_CHECKPOINT})
	mp._receive_gate("peerA", {"t": "gate", "id": TowerGraph.ENTRY_LIFT_MAZE})
	if not shell.is_opened(TowerInterior.GATE_CHECKPOINT):
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "the room's opening never reached the shell — the earn probe measured no setup"
	if bool(shell.call("is_earned", TowerInterior.GATE_CHECKPOINT)):
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "a room-opened id reads as earned — the two sets are not distinguished"
	var body := Node3D.new()
	body.add_to_group("player")
	root.add_child(body)
	# Standing on the open checkpoint earns it: the store gains exactly it.
	interior._on_checkpoint_enter(body)
	if not BestRunStore.tower_opened_ids().has(TowerInterior.GATE_CHECKPOINT):
		body.queue_free()
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "working an open checkpoint persisted nothing — the earn site gates on room-open"
	# ...and the maze stop the same way.
	interior._on_lift_stop_enter(body)
	if not BestRunStore.tower_opened_ids().has(TowerGraph.ENTRY_LIFT_MAZE):
		body.queue_free()
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "working an open lift stop persisted nothing — the earn site gates on room-open"
	# Earning twice writes once: with the profile deleted, a second visit that
	# wrote anything would recreate it — mtime cannot count within one second.
	DirAccess.remove_absolute(BestRunStore.config_path)
	interior._on_checkpoint_enter(body)
	if FileAccess.file_exists(BestRunStore.config_path):
		body.queue_free()
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "re-entering an earned checkpoint recreated a deleted profile — the earn is not exactly-once"
	# The polled sites cannot be driven headless (pad-overlap state), so they
	# are pinned by scan: every earn site must read `is_earned`, never bare
	# open state.
	var interior_source: String = FileAccess.get_file_as_string("res://scripts/tower_interior.gd")
	if interior_source.is_empty():
		body.queue_free()
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "could not read res://scripts/tower_interior.gd to pin the earn gates"
	for anchor: String in ["_is_earned(GATE_IDENTITY)", "_is_earned(GATE_DEMAND)"]:
		if not interior_source.contains(anchor):
			body.queue_free()
			mp.queue_free()
			await TowerProbe.clear(self, null, shell)
			return "no earn site gates on %s — a pad the room opened earns nothing" % anchor
	# `_is_earned(gid)` occurs at BOTH polled sites (riddle and spine), so a
	# whole-file `contains` passes when either one reverts (review round 2,
	# minor). Slice each function's body — from its `func ` line to the next
	# — and require the anchor in EACH.
	for tick: String in ["func _tick_riddle_pads", "func _tick_spine_pads"]:
		var begin: int = interior_source.find(tick)
		if begin < 0:
			body.queue_free()
			mp.queue_free()
			await TowerProbe.clear(self, null, shell)
			return "could not find %s to pin its earn gate" % tick
		var tail: String = interior_source.substr(begin + tick.length())
		var close: int = tail.find("\nfunc ")
		var site: String = tail.substr(0, close) if close >= 0 else tail
		if not site.contains("_is_earned(gid)"):
			body.queue_free()
			mp.queue_free()
			await TowerProbe.clear(self, null, shell)
			return "%s never reads is_earned — a pad the room opened earns nothing" % tick
	body.queue_free()
	mp.queue_free()
	await TowerProbe.clear(self, null, shell)
	Sentinel.done("earn_while_room_open")
	return ""


func _check_rescan_refires_triggers() -> String:
	"""
	13d. THE TRIGGER RE-SCAN (review round 1, minor). `body_entered` fires on
	crossing only, so a close-snap that un-lights a checkpoint under a
	standing player would leave a dark plate no re-entry can light — the
	enter already fired. `_rescan_triggers()` re-runs the enter handlers for
	the player standing inside, located by pure geometry (position against
	the trigger's own AABB — overlap lists read empty headless); the
	handlers' own earned-gates keep it safe. A body 500 m away must earn
	nothing; a body on the shut plate earns and lights it.
	"""
	TowerProbe.fresh_store()
	var shell := await TowerProbe.make_tower(self)
	var interior := shell.get_node_or_null("TowerInterior")
	if interior == null:
		await TowerProbe.clear(self, null, shell)
		return "the tower has no TowerInterior child — the rescan probe has no subject"
	var trigger := interior.find_child("CheckpointTrigger", true, false) as Area3D
	if trigger == null:
		await TowerProbe.clear(self, null, shell)
		return "the tower built no CheckpointTrigger — the rescan has no subject"
	# A plain Node3D in group "player": the rescan is pure geometry (position
	# against the trigger's own AABB), so no physics body, no settle, and no
	# dependence on overlap lists — which read empty headless.
	var body := Node3D.new()
	body.add_to_group("player")
	root.add_child(body)
	# Negative control first: far outside the box, the rescan must earn
	# nothing — otherwise it fires unconditionally and proves no routing.
	body.global_position = (trigger as Node3D).global_position + Vector3(500.0, 0.0, 0.0)
	interior._rescan_triggers()
	if BestRunStore.tower_opened_ids().has(TowerInterior.GATE_CHECKPOINT):
		body.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "the rescan earned a checkpoint for a body 500 m away — it fires unconditionally"
	# Standing on the shut plate: earns and lights it through the rescan alone.
	body.global_position = (trigger as Node3D).global_position
	interior._rescan_triggers()
	if not BestRunStore.tower_opened_ids().has(TowerInterior.GATE_CHECKPOINT):
		body.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "the rescan earned nothing for a body standing on a shut checkpoint — the plate stays dark"
	if not shell.is_opened(TowerInterior.GATE_CHECKPOINT):
		body.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "the rescan persisted without opening — state did not become geometry"
	body.queue_free()
	await TowerProbe.clear(self, null, shell)
	Sentinel.done("rescan_refires_triggers")
	return ""



func _check_join_cancels_deferred_close() -> String:
	"""
	13e. A JOIN CANCELS A STALE DEFERRED CLOSE (review round 2, major): leave
	the room from inside the walls, then host/join the NEXT room without
	stepping out. The old room's parked close must die at the join AND a
	deferral that survives it must be harmless — the re-hydrate rebuilds
	`opened` as profile UNION the live mirror, so the new room's gates stay
	open. Driven through the shipped calls: `leave()`, `_on_lobby_joined()`,
	`poll_pending_room_close()`, `_apply_opened()`.
	"""
	TowerProbe.fresh_store()
	var shell := await TowerProbe.make_tower(self)
	var interior := shell.get_node_or_null("TowerInterior")
	if interior == null:
		await TowerProbe.clear(self, null, shell)
		return "the tower has no TowerInterior child — the stale-close probe has no subject"
	var player := Node3D.new()
	player.add_to_group("player")
	root.add_child(player)
	player.global_position = interior.global_position
	await process_frame
	var mp: Node = MPManager.new()
	root.add_child(mp)
	mp.add_to_group("mp")
	mp.set("lobby_only", true)
	# ROOM ONE opens the identity gate; leave from inside parks its close.
	mp._on_lobby_joined("us", "ROOM1", "themaster", ["themaster", "us"])
	mp._receive_gate("peerA", {"t": "gate", "id": TowerInterior.GATE_IDENTITY})
	if not shell.is_opened(TowerInterior.GATE_IDENTITY):
		player.queue_free()
		mp.remove_from_group("mp")
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "the room's opening never reached the shell — the stale-close probe measured no setup"
	mp.leave()
	if not shell.is_opened(TowerInterior.GATE_IDENTITY):
		player.queue_free()
		mp.remove_from_group("mp")
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "leave snapped the gate shut under a player inside — the stale-close probe measured no deferral"
	# ROOM TWO, joined without leaving the building: the join must cancel
	# the previous room's parked close.
	mp._on_lobby_joined("us", "ROOM2", "us", ["us"])
	if bool(shell.call("poll_pending_room_close", true)):
		player.queue_free()
		mp.remove_from_group("mp")
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "joining the next room left the old room's deferred close armed — stepping out would snap the new room's gates shut"
	# Belt and braces: a deferral that DOES survive the join still cannot
	# close what the live room holds open. The new room's master opens the
	# same gate; a stale deferral then fires on the way out.
	mp._receive_gate("peerB", {"t": "gate", "id": TowerInterior.GATE_IDENTITY})
	shell.call("defer_room_close")
	player.global_position = interior.global_position + Vector3(5000.0, 0.0, 0.0)
	await process_frame
	interior.call("_tick_room_close")
	if not shell.is_opened(TowerInterior.GATE_IDENTITY):
		player.queue_free()
		mp.remove_from_group("mp")
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "a stale deferred close snapped the new room's gate shut — the re-hydrate must union the live mirror"
	if BestRunStore.tower_opened_ids().has(TowerInterior.GATE_IDENTITY):
		player.queue_free()
		mp.remove_from_group("mp")
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "the stale close persisted the new room's id — room-only ids must never reach the profile"
	player.queue_free()
	mp.remove_from_group("mp")
	mp.queue_free()
	await TowerProbe.clear(self, null, shell)
	Sentinel.done("join_cancels_deferred_close")
	return ""


func _check_absorbed_never_persists() -> String:
	"""
	14. OWN VS ABSORBED, ACROSS A LATE STREAM-IN (bead godot-test1-crk). An
	id absorbed with no shell in range lives in the mirror only; a shell
	that streams in AFTER the absorb still opens it (the `_enter_tree`
	mirror pull — review round 1's hole stays shut without the profile);
	and a local `mark_opened` afterwards lands in the profile while the
	absorbed id stays out of it.
	"""
	TowerProbe.fresh_store()
	if get_first_node_in_group("tower") != null:
		return "group 'tower' is not empty — the late stream-in must build the only tower"
	var mp: Node = MPManager.new()
	root.add_child(mp)
	mp.add_to_group("mp")
	mp._absorb_opened_gate(TowerInterior.GATE_IDENTITY)
	if FileAccess.file_exists(BestRunStore.config_path):
		mp.remove_from_group("mp")
		mp.queue_free()
		return "a shell-less absorb created a profile — the room persists with no shell to blame"
	# The shell streams in after the absorb: the mirror pull opens it.
	var shell := await TowerProbe.make_tower(self)
	if not shell.is_opened(TowerInterior.GATE_IDENTITY):
		mp.remove_from_group("mp")
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "a shell built after the absorb came up closed — the mirror pull is missing"
	if FileAccess.file_exists(BestRunStore.config_path):
		mp.remove_from_group("mp")
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "streaming in over a room id created a profile — hydration persists the room"
	# Own opening now: the profile gains exactly it.
	shell.mark_opened(TowerInterior.GATE_CHECKPOINT)
	var stored: Array = BestRunStore.tower_opened_ids()
	if stored != [TowerInterior.GATE_CHECKPOINT]:
		mp.remove_from_group("mp")
		mp.queue_free()
		await TowerProbe.clear(self, null, shell)
		return "the profile holds %s — own and absorbed must never mix there" % str(stored)
	mp.remove_from_group("mp")
	mp.queue_free()
	await TowerProbe.clear(self, null, shell)
	Sentinel.done("absorbed_never_persists")
	return ""


func _check_drain_publishes_own_only() -> String:
	"""
	15. THE JOIN DRAIN PUBLISHES WHAT THIS PEER EARNED (bead godot-test1-crk).
	The once-per-join queue is the profile set: an id absorbed after the
	join never queues, so the room's set cannot launder itself into a
	joiner's drain. Same loopback as probe 7 — shipped code either side,
	only the air is the test's.
	"""
	TowerProbe.fresh_store()
	BestRunStore.merge_tower_opened_ids(["maintenance_crawl"])
	var joiner: Node = MPManager.new()
	root.add_child(joiner)
	joiner.set("lobby_only", true)
	joiner._on_lobby_joined("us", "ROOM", "themaster", ["themaster", "us"])
	# A teammate's id, absorbed mid-room: in the mirror, never in the queue.
	joiner._absorb_opened_gate("collapsed_slab")
	joiner.set("_join_wait", MPManager.JOIN_SNAPSHOT_WAIT)
	joiner._tick_join_gate_publish(0.1)
	if not bool(joiner.get("_join_gate_primed")):
		joiner.queue_free()
		return "a settled join never primed its publish — the own-only probe measured no setup"
	var queue: Array = (joiner.get("_join_gate_queue") as Array).duplicate()
	joiner.queue_free()
	if queue != ["maintenance_crawl"]:
		return "priming queued %s — an absorbed id rides the drain" % str(queue)
	Sentinel.done("drain_publishes_own_only")
	return ""
