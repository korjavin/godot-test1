class_name MpCrocSync
extends RefCounted
## THE CROCODILE SYNC FAMILY — the master's transform broadcast, the receiver, the
## timeout sweep, the id cache and the kill/dead arbitration, lifted whole out of
## `mp_manager.gd` (bd godot-test1-ftn.18).
##
## THE SPLIT, and why it falls exactly here. `MpManager` keeps the MESH: the
## socket, the peers, presence, the verbs' dispatch table, the join snapshot, the
## rate limits, the hero pool — and it keeps the STATE this file reads
## (`_synced_crocs`, `_croc_seen`, `_dead_crocs`, `_croc_accum`), because a room's
## bookkeeping belongs to the node that owns the room. This file keeps the
## HANDLERS: everything that turns a crocodile into bytes, bytes back into a
## crocodile, or a crush into a room-wide ruling.
##
## THE PARSERS ARE STILL `MpCodec`'S. `decode_croc_sync`, the `CROC_FLAG_*` bits
## and `MAX_CROC_SYNC` did not move and must not: CLAUDE.md's seam is "the parsers
## are MpCodec, the handlers are MpManager", and this bead only moves handlers OUT
## of the manager into a sibling. A new field on the wire is still a bound plus a
## parser in `mp_codec.gd` and a handler here.
##
## WHY STATIC FUNCTIONS AND NO STATE. There is exactly one MP node in a scene and
## its state is the room's, so a second object holding half of it would be a
## second thing to reset on `leave()`. Every function here takes the manager as
## its first argument and reaches back through it — `mp._synced_crocs`,
## `mp.is_online()`, `mp._broadcast_reliable()` — which is one direction only, and
## the direction `landmark_builders.gd` established. The parameter is typed `Node`
## rather than `MpManager` for that file's reason too: `MpManager` aliases the
## three constants below, so naming its type here would close a class-name cycle.
##
## IT IS A MOVE AND NOTHING ELSE. Every rule, every measured number and every
## comment below arrived unchanged from `mp_manager.gd`; the only edits are the
## `mp.` dereferences and the dropped leading underscore on the names.


## How often the room master broadcasts crocodile sync packets, in hertz.
## Deliberately slower than PRESENCE_HZ: a crocodile is a background actor the
## receiver eases toward (see `piglet_crocodile_ai._tick_remote`), while the
## player avatar is what the eye tracks. 10 Hz is the cheapest rate at which the
## easing still reads as motion rather than as stepping.
const CROC_SYNC_HZ: float = 10.0

## Radius (metres) around EACH TARGET PEER whose crocodiles that peer is sent.
##
## THE RELATIONSHIP THAT MUST HOLD — and it is the same kind of invariant as the
## LOD manager's `SIM_RADIUS ≫ DETECTION_RADIUS`: this must EXCEED the LOD
## manager's sleep radius, `SIM_RADIUS + HYSTERESIS_MARGIN` = 50 m. A crocodile
## between the two would be awake for that peer (so its local AI is running) yet
## outside its sync window (so no sample ever arrives), and the two simulations
## would silently disagree about a crocodile close enough to bite. 55 > 50 leaves
## 5 m of slack; retune this if either LOD constant moves.
const CROC_SYNC_RADIUS: float = 55.0

## How long a crocodile keeps following the master's samples after the last one
## arrived, in seconds, before it is handed back to its own local AI.
##
## This is what makes the master's COVERAGE CEILING degrade gracefully (a peer
## further than the master's render distance gets no samples for its neighbours,
## so they simply resume local simulation — today's behaviour, for peers who
## cannot see each other anyway) AND what makes migration seamless: a lobby
## re-election takes ~1 s, well inside this window, so crocodiles never visibly
## stall during a handover.
const CROC_SYNC_TIMEOUT: float = 2.0


# =============================================================================
# CROCODILE SYNC (phase 5)
# =============================================================================
#
# The room MASTER simulates the crocodiles and broadcasts their transforms; every
# other peer stops running that crocodile's AI and renders the synced state.
#
# THE SYNC LAYER NEVER CREATES, RE-PARENTS OR FREES A CROCODILE. Crocodiles stay
# chunk-parented, per-peer, deterministic and freed on chunk unload exactly as in
# single player; this only overlays dynamic state onto nodes that already exist
# locally, matched by `croc_id()`. That is what keeps a sleeping crocodile free:
# its spawn state is already a pure function of chunk coords + `run_seed`, which
# every peer computes identically, so only the AWAKE ones cost any network at all.
#
# COVERAGE: the master simulates only the crocodiles ITS OWN terrain has loaded,
# which used to stop at `render_distance` × 50 m (150 m on web) — a peer beyond
# that got no samples for its neighbours and they fell back to local simulation
# after CROC_SYNC_TIMEOUT. That is now closed from the terrain side (bead
# godot-test1-s86.14): `crocodile_lod_manager.gd` hands the same peer-position
# array it already builds to `endless_terrain.set_focus_points()`, which keeps a
# 3×3 chunk block loaded around each teammate — 50 m of ground in every
# direction, covering the 45 m SIM_RADIUS inside which a crocodile is awake at
# all. Focus points decide only WHICH CHUNKS STAY LOADED, never what one
# contains; chunk content is still a pure function of coords + `run_seed`.
#
# ponytail: the residual ceiling is the CAP — at most three teammates and 27
# extra chunks are honoured (`endless_terrain.MAX_FOCUS_POINTS` /
# `MAX_FOCUS_CHUNKS`), because the union of peer areas multiplies the active
# chunk count and the web build is what all of this exists to protect. A room
# whose four players stand in four different places pins 27 chunks and the rest
# degrades exactly as before: local simulation, for peers far past each other's
# fog. Nothing duplicates, nothing vanishes either way.

static func send_croc_sync(mp: Node) -> void:
	"""
	Master only: send each connected peer the crocodiles awake near IT.

	Sent UNRELIABLE, for the same reason presence is: a dropped sample is
	replaced 100 ms later, and re-transmitting a stale transform would be strictly
	worse than skipping it.

	PER-PEER FILTERING IS WHAT KEEPS THIS AFFORDABLE. ~25 crocodiles inside
	CROC_SYNC_RADIUS of one peer × 21 bytes an entry × 10 Hz ≈ 5 KB/s per peer,
	against ~100 KB/s if the whole awake set (which spans the whole room) were
	broadcast unfiltered.

	ONE PASS OVER THE GROUP, N BUFFERS — never one pass per peer. The group holds
	~1000 nodes and this runs 10 times a second, so the loop order is the whole
	cost model.
	"""
	# Who is actually reachable, and where they last told us they were. Built off
	# `_rtc.get_peers()` rather than `_connections` for the reason `_send_presence`
	# spells out: `_connections` holds peers whose channels are still negotiating.
	var peers: Dictionary = mp._rtc.get_peers()
	var target_int: Array[int] = []
	var target_pos: Array[Vector3] = []
	for id: String in mp._peer_state:
		var pid: int = MpCodec.peer_int_id(id)
		if not peers.has(pid) or not bool((peers[pid] as Dictionary).get("connected", false)):
			continue
		target_int.append(pid)
		target_pos.append(mp._peer_state[id]["pos"])
	if target_int.is_empty():
		return  # Nobody to tell.

	var count: int = target_int.size()
	var buf_ids: Array[PackedInt32Array] = []
	var buf_xf: Array[PackedFloat32Array] = []
	var buf_flags: Array[PackedByteArray] = []
	for _t: int in count:
		buf_ids.append(PackedInt32Array())
		buf_xf.append(PackedFloat32Array())
		buf_flags.append(PackedByteArray())

	var radius_sq: float = CROC_SYNC_RADIUS * CROC_SYNC_RADIUS
	for croc: Node in mp.get_tree().get_nodes_in_group("crocodile"):
		# Defensive `in` / `has_method` guards in the LOD manager's style: the
		# group is a contract, not a type.
		if not is_instance_valid(croc) or not croc.has_method("croc_id") or not (croc is Node3D):
			continue
		# Asleep crocodiles cost zero network — every peer already agrees on where
		# a sleeping one stands, because that is its deterministic spawn state.
		#
		# EXCEPT A SLEEPER THAT HAS STALKED, which is the one body that has left
		# that state without waking: `crocodile_lod_manager` walks a sleeping
		# tracker up the scent trail on its own scan (see `advance_tracking`), so
		# the master's copy is somewhere the peer's deterministic spawn position
		# is not, and skipping it would pop the unit into place the frame it woke.
		# No protocol change and no measurable traffic — the per-peer radius filter
		# below still applies, and a hunter is one body per few chunks.
		#
		# `has_stalked` and NOT `is_tracking`, deliberately: the question is whether
		# the spawn position is still a true statement about this body, and it stops
		# being one permanently the first time the unit takes a step. A tracker whose
		# trail has gone cold is just as displaced as one still walking.
		if "lod_active" in croc and not croc.lod_active:
			if not ("has_stalked" in croc and croc.has_stalked):
				continue
		# A crocodile WE are being driven on is not ours to publish. This cannot
		# normally be true on the master (promotion releases them all), but a
		# sample in flight across an election could land just after we were
		# elected, and echoing it back would be a loop.
		if "remote_driven" in croc and croc.remote_driven:
			continue

		var body: Node3D = croc as Node3D
		var pos: Vector3 = body.global_position
		var id: int = croc.croc_id()
		var flags: int = MpCodec._croc_flags(croc)
		# `rotation.y`, not a global yaw: `set_remote_state()` writes `rotation.y`
		# on the far side, and a chunk (the crocodile's parent) is never rotated,
		# so the two are the same number and the round trip is symmetric.
		var yaw: float = body.rotation.y

		for t: int in count:
			if buf_ids[t].size() >= MpCodec.MAX_CROC_SYNC:
				continue  # Packet full for this peer; the rest wait 100 ms.
			if pos.distance_squared_to(target_pos[t]) > radius_sq:
				continue
			buf_ids[t].append(id)
			buf_xf[t].append(pos.x)
			buf_xf[t].append(pos.y)
			buf_xf[t].append(pos.z)
			buf_xf[t].append(yaw)
			buf_flags[t].append(flags)

	mp._rtc.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	for t: int in count:
		if buf_ids[t].is_empty():
			continue
		var bytes: PackedByteArray = var_to_bytes({
			"t": "croc", "i": buf_ids[t], "x": buf_xf[t], "f": buf_flags[t],
		})
		mp._rtc.set_target_peer(target_int[t])
		mp._rtc.put_packet(bytes)


static func receive_croc_sync(mp: Node, from_id: String, packet: Dictionary) -> void:
	"""
	Apply one crocodile-sync packet from the master.

	DROPPED UNLESS IT CAME FROM THE MASTER, for exactly the reason only the
	master's `seed` is accepted: the mesh is peer input, and without this check
	any member of the room could drive everybody's crocodiles. A packet arriving
	while WE are the master is dropped too — we are the authority, not a listener.
	"""
	if from_id != mp._master or mp._master == mp._you:
		return
	var sync: Dictionary = MpCodec.decode_croc_sync(packet)
	if sync.is_empty():
		return  # The fourth trust boundary refused it; whole or nothing.

	var ids: PackedInt32Array = sync["ids"]
	var xf: PackedFloat32Array = sync["xf"]
	var flags: PackedByteArray = sync["flags"]
	var now: int = Time.get_ticks_msec()
	# At most ONE group scan per packet, not one per missing id.
	var rescanned: bool = false

	for entry: int in ids.size():
		var id: int = ids[entry]
		var croc: Node = croc_by_id(mp, id)
		if croc == null and not rescanned:
			rebuild_croc_cache(mp)
			rescanned = true
			croc = croc_by_id(mp, id)
		if croc == null:
			# EXPECTED, NOT AN ERROR: this peer has not generated the chunk that
			# crocodile lives in. Silent on purpose — warning here would be one
			# line per crocodile at 10 Hz.
			continue
		var base: int = entry * 4
		croc.set_remote_state(
			Vector3(xf[base], xf[base + 1], xf[base + 2]), xf[base + 3], int(flags[entry])
		)
		mp._croc_seen[id] = now


static func tick_croc_timeout(mp: Node) -> void:
	"""
	Hand back any crocodile whose samples have stopped, and purge the id cache of
	crocodiles whose chunk has since unloaded.

	Runs on the sync tick (10 Hz) rather than per frame — CROC_SYNC_TIMEOUT is
	2 s, so a tenth of a second of granularity is free.
	"""
	var cutoff: int = Time.get_ticks_msec() - int(CROC_SYNC_TIMEOUT * 1000.0)
	for id: int in mp._croc_seen.keys():
		if int(mp._croc_seen[id]) > cutoff:
			continue
		mp._croc_seen.erase(id)
		var croc: Node = croc_by_id(mp, id)
		if croc != null:
			croc.clear_remote_drive()

	# The cache holds hard references, so a crocodile freed with its chunk would
	# otherwise sit here as a freed instance until its id came round again.
	for id: int in mp._synced_crocs.keys():
		if not is_instance_valid(mp._synced_crocs[id]):
			mp._synced_crocs.erase(id)


static func croc_by_id(mp: Node, id: int) -> Node:
	"""The local crocodile with this id, or `null`. Purges a freed instance it
	finds on the way; does NOT scan the group — see `rebuild_croc_cache()`."""
	var cached: Variant = mp._synced_crocs.get(id, null)
	if cached == null:
		return null
	if not is_instance_valid(cached):
		mp._synced_crocs.erase(id)
		return null
	return cached as Node


static func rebuild_croc_cache(mp: Node) -> void:
	"""Cache every loaded crocodile's id in one pass. Called on a lookup miss —
	at most once per packet — because a miss usually means a chunk streamed in
	since the last scan, and re-caching one id at a time would rescan per entry."""
	mp._synced_crocs.clear()
	for croc: Node in mp.get_tree().get_nodes_in_group("crocodile"):
		# Filtered on the method the SYNC needs, not merely on `croc_id` — every
		# consumer of this cache calls `set_remote_state` / `clear_remote_drive`
		# straight off it, and a group member exposing an id but not the phase-5
		# API would be a hard runtime error inside `_process`. GDScript unwinds
		# the whole erroring function, so that would silently abandon the rest of
		# the sync packet and the timeout sweep with it.
		if is_instance_valid(croc) and croc.has_method("set_remote_state"):
			mp._synced_crocs[croc.croc_id()] = croc


static func release_synced_crocs(mp: Node) -> void:
	"""Hand every crocodile we were rendering from the master's samples back to
	its own AI, and forget the sync bookkeeping. Used by promotion (the hot
	standby handover) and by `leave()`."""
	for croc: Variant in mp._synced_crocs.values():
		if is_instance_valid(croc) and (croc as Node).has_method("clear_remote_drive"):
			(croc as Node).clear_remote_drive()
	mp._synced_crocs.clear()
	mp._croc_seen.clear()


# =============================================================================
# THE KILL RULING (phase 5)
# =============================================================================
#
# Giant Teibi's crush, routed through the master like Phoboman's wave and the HQ
# lure plate beside it — see `mp_manager.gd`'s "CROCODILE ABILITIES THROUGH THE
# MASTER" banner for the whole table and for why a kill is the one of the four
# that needs a broadcast back (it FREES a node, which no amount of transform sync
# can express).
#
#     kill   peer   → master   {"t":"kill","id":int}           giant Teibi's crush
#     dead   master → everyone {"t":"dead","id":int}           the kill ruling

static func request_croc_kill(mp: Node, id: int) -> bool:
	"""
	Giant Teibi crushed a crocodile: ask the room to kill THAT crocodile
	everywhere.

	Returns true when the room has taken it over — the caller must then NOT run
	its own squash, because the master's `dead` broadcast frees the body on every
	peer including this one. FALSE OFFLINE, and false whenever the request could
	not actually leave (no mesh, master's channel still negotiating), so the
	caller falls through to today's local squash on one test rather than leaving a
	crocodile the player visibly stood on still walking around.
	"""
	if not mp.is_online() or mp._rtc == null:
		return false
	if mp._dead_crocs.has(id):
		# Already dead room-wide, but this body is somehow still standing (a chunk
		# that regenerated between the broadcast and now). Free it here rather than
		# answering true and leaving it: the packet that killed it has been and gone.
		apply_dead(mp, id)
		return true
	if mp._master == mp._you:
		resolve_kill(mp, id)
		return true
	return mp._send_reliable_to_master(var_to_bytes({"t": "kill", "id": id}))


static func resolve_kill(mp: Node, id: int) -> void:
	"""
	MASTER ONLY: rule that a crocodile is dead, tell the room, and kill our own
	copy through the same path everyone else takes.

	First kill wins and a repeat is dropped silently — the same shape
	`_resolve_claim()` uses for a pickup, one set per thing being arbitrated.
	"""
	if mp._dead_crocs.has(id):
		return
	mp._broadcast_reliable(var_to_bytes({"t": "dead", "id": id}))
	apply_dead(mp, id)


static func apply_dead(mp: Node, id: int) -> void:
	"""
	Every peer's half of a kill: remember the id and run the ORDINARY squash on
	the local body, so a crush READS as a crush on every screen rather than as a
	crocodile blinking out.

	The id is recorded even when no body is found, which is the common case and
	NOT an error: this peer may never have generated that chunk, and the record is
	what stops the crocodile walking back in when it does
	(`piglet_crocodile_ai._ready()` asks `is_croc_dead`).
	"""
	mp._dead_crocs[id] = true
	var croc: Node = croc_by_id(mp, id)
	if croc == null:
		# At most one group scan, and only on a miss — see `rebuild_croc_cache()`.
		rebuild_croc_cache(mp)
		croc = croc_by_id(mp, id)
	# Drop the sync bookkeeping either way: a dead crocodile is nobody's to drive,
	# and the cache holds a hard reference to a node about to free itself.
	mp._synced_crocs.erase(id)
	mp._croc_seen.erase(id)
	if croc != null and croc.has_method("squash_and_die"):
		croc.squash_and_die()


static func receive_kill(mp: Node, _from_id: String, packet: Dictionary) -> void:
	"""
	MASTER ONLY: a peer's crush. One int to validate, and nothing to bound — the
	id space is the whole of `String.hash()`, so an id naming no crocodile simply
	finds nothing and costs one dictionary write.
	"""
	if mp._master != mp._you:
		return
	if typeof(packet.get("id", null)) != TYPE_INT:
		return
	resolve_kill(mp, int(packet["id"]))


static func receive_dead(mp: Node, from_id: String, packet: Dictionary) -> void:
	"""
	The master's kill ruling. ONLY the master's is accepted, the same authority
	rule `_receive_confirm()` and `receive_croc_sync()` enforce: the mesh is
	peer-to-peer, so without it any member could free every crocodile in the room.
	"""
	if from_id != mp._master:
		return
	if typeof(packet.get("id", null)) != TYPE_INT:
		return
	apply_dead(mp, int(packet["id"]))


static func is_croc_dead(mp: Node, id: int) -> bool:
	"""
	Whether the ROOM has already killed this crocodile. Asked once per crocodile
	AT SPAWN, never per frame — the same shape and placement `coin.gd` uses for
	`is_coin_collected` — so a chunk regenerating on a peer that saw the kill does
	not walk the crocodile back in. False offline, where the set is always empty
	anyway.

	The set IS replayed in the join snapshot (`_recent_dead_ids()` on the way out,
	`_absorb_dead()` on the way in), so a peer joining after a crush no longer
	sees the crocodile alive again. What remains is `_recent_dead_ids()`'s
	`MAX_STATE_IDS` ceiling, documented there. A peer that left and rejoined
	starts from an empty set of its own and re-learns the room's from the
	incumbents' snapshots — the same answer by a different route.
	"""
	return mp.is_online() and mp._dead_crocs.has(id)
