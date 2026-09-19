class_name MpWorldSync
extends RefCounted
## THE MASTER-RELAYED WORLD VERBS FAMILY — herd, weather (wx), flee, and pad,
## lifted whole out of `mp_manager.gd` (bd godot-test1-ftn.31) — plus the HQ
## alarm (`alrm`, epic godot-test1-buyt), which is the one pair here that is NOT
## master-arbitrated: `publish_alarm()`'s send site says why, and it is the same
## coverage argument `MpManager.publish_gate_opened()` already makes.
##
## THE SPLIT, and why it falls exactly here. `MpManager` keeps the MESH: the
## socket, the peers, presence, the verbs' dispatch table, the join snapshot, the
## rate limits, the hero pool — and it keeps the STATE this file reads
## (`_master`, `_you`, `_rtc`, `_peer_state`, `_state`), because a room's
## bookkeeping belongs to the node that owns the room. The send helpers
## (`_send_reliable_to_master`) stay on the manager as general mesh primitives.
## This file keeps the HANDLERS: everything that broadcasts the master's simulated
## herd and sky to peers, arbitrates a stink wave or lure plate press, and applies
## those effects room-wide.
##
## WHY STATIC FUNCTIONS AND NO STATE. There is exactly one MP node in a scene and
## its state is the room's, so a second object holding half of it would be a
## second thing to reset on `leave()`. Every function here takes the manager as
## its first argument and reaches back through it — `mp._rtc`, `mp.is_online()`,
## `mp._send_reliable_to_master()` — which is one direction only.
## The parameter is typed `Node` rather than `MpManager` to avoid a circular
## parse-time reference, as `MpManager` aliases `MAX_FLEE_DURATION`.
##
## IT IS A MOVE AND NOTHING ELSE. Every rule, every measured number and every
## comment below arrived unchanged from `mp_manager.gd`; the only edits are the
## `mp.` dereferences and the dropped leading underscore on internal names.


## Trust-boundary bound on a relayed Stink Wave (see `receive_flee`). A flee
## duration is peer input and it is applied to the WHOLE pack, so an unbounded one
## would leave every crocodile in the room fleeing — and a fleeing crocodile is
## harmless — for the room's life: a one-packet griefing button. Phoboman's own
## PHOBOMAN_FLEE_DURATION is 10 s, so this is six times the honest value.
const MAX_FLEE_DURATION: float = 60.0


# =============================================================================
# FAUNA HERD SYNC (bead godot-test1-6xc)
# =============================================================================
#
# THE MASTER SIMULATES, PEERS REPLAY — the whole of the owner's report ("in
# multiplayer i can see giraffes and I ride on one of them but my buddy in the
# same game don't see them"). Fauna still never touches `run_seed`; this is the
# SCENT TRAIL's precedent — runtime state the master broadcasts, outside the
# determinism contract, costing no seeded stream a draw.
#
# ONE PACKET PER TICK, NOT ONE PER ANIMAL. A herd's whole state is its build
# params plus (centre, facing yaw, metres travelled): every member sits at
# `centre + offset` and every limb angle is a pure function of metres walked, so
# ~70 bytes at CROC_SYNC_HZ describes up to ten animals completely. The params
# ride EVERY tick rather than once, which is what makes it self-healing for a
# dropped packet, for a peer whose mesh was still negotiating and for a late
# joiner — no relay leg and no join-snapshot field.
#
# THE SYNC LAYER CREATES NO NODE AND FREES NONE, exactly like the crocodile sync
# in `mp_croc_sync.gd`. `fauna_manager.gd` owns the animals at both ends: `herd_sync_state()`
# describes its own herd, `apply_herd_sync()` builds or eases one, and the
# silence timeout that frees a replay lives beside the state it frees.
#
# MIXED-BUILD CEILING, documented like the `room` verb's: a master on a build
# without this verb publishes nothing, and a peer in that room draws no fauna at
# all (it will not roll its own — see `_mp_replays_the_herd`). It converges the
# moment the room's master is on this build.

static func send_herd_sync(mp: Node) -> void:
	"""
	Master only: tell every peer about the herd crossing our field, or that none
	is (`k: -1`, the all-clear — see `MpCodec.decode_herd`).

	Sent UNRELIABLE, for the reason presence is: another one follows in 100 ms and
	re-transmitting a stale centre would be strictly worse than skipping it. Sent
	UNCONDITIONALLY rather than only while a herd is alive, because the all-clear
	is what frees a peer's copy promptly when a crossing ends; it is ~26 bytes at
	10 Hz to at most three peers, half a percent of what the crocodile sync costs.
	"""
	if mp._rtc == null:
		return
	var state: Dictionary = {"k": -1}
	var fauna := mp.get_tree().get_first_node_in_group("fauna")
	if fauna != null and fauna.has_method("herd_sync_state"):
		var live: Dictionary = fauna.call("herd_sync_state")
		if not live.is_empty():
			state = live
	state["t"] = "herd"
	var bytes: PackedByteArray = var_to_bytes(state)
	mp._rtc.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	# Targeted, not broadcast-to-peer-0, for the reason `_send_presence()` spells
	# out: `_connections` holds peers negotiation has merely STARTED with.
	var peers: Dictionary = mp._rtc.get_peers()
	for pid: int in peers:
		if not bool((peers[pid] as Dictionary).get("connected", false)):
			continue
		mp._rtc.set_target_peer(pid)
		mp._rtc.put_packet(bytes)


static func receive_herd(mp: Node, from_id: String, packet: Dictionary) -> void:
	"""
	Apply one herd packet from the master.

	DROPPED UNLESS IT CAME FROM THE MASTER, and dropped while WE are the master,
	for exactly `MpCrocSync.receive_croc_sync()`'s reasons: the mesh is peer input, so
	without the first any member could put a giraffe in front of everybody, and
	without the second our own herd would be driven by an echo of itself.
	"""
	if from_id != mp._master or mp._master == mp._you:
		return
	var state: Dictionary = MpCodec.decode_herd(packet)
	if state.is_empty():
		return  # The eighth trust boundary refused it; whole or nothing.
	var fauna := mp.get_tree().get_first_node_in_group("fauna")
	if fauna == null or not fauna.has_method("apply_herd_sync"):
		return  # No fauna manager in this scene — not an error, the LOD idiom.
	fauna.call("apply_herd_sync", state)


# =============================================================================
# SHARED STORMS (bead godot-test1-vej)
# =============================================================================
#
# THE MASTER SIMULATES, PEERS REPLAY — the owner's report ("one player had
# rain when another didn't"). Rain gates Windman's Air Rush through
# `is_raining_at()`, so a storm is gameplay and the room must share one sky —
# while clear clouds and birds stay per-peer cosmetic on the local RNG. This is
# the herd's precedent, not the seed's: runtime state the master broadcasts,
# outside the determinism contract, costing no seeded stream a draw.
#
# ONE PACKET PER TICK, storms only. Each storm's whole state is its build seed
# plus its live centre: every box, the speed and the rain radius are pure
# functions of the seed, so a few dozen bytes at CROC_SYNC_HZ describe the
# whole stormy sky. The params ride EVERY tick rather than once, which is what
# makes it self-healing for a dropped packet, for a peer whose mesh was still
# negotiating and for a late joiner — no relay leg and no join-snapshot field.
#
# THE SYNC LAYER CREATES NO CLOUD AND FREES NONE, exactly like the herd sync.
# `weather_manager.gd` owns the clouds at both ends: `weather_sync_state()`
# describes its own storms, `apply_weather_sync()` builds or snaps them, and
# the silence timeout that frees a replay lives beside the state it frees.
#
# MIXED-BUILD CEILING, documented like the herd's: a master on a build without
# this verb publishes nothing, and a peer on this build in that room draws no
# storms at all (it will not roll its own — see `_mp_replays_the_weather`).
# It converges the moment the room's master is on this build.

static func send_wx_sync(mp: Node) -> void:
	"""
	Master only: tell every peer about the storms crossing our field, or that
	none is (`k: -1`, the all-clear — see `MpCodec.decode_wx`).

	Sent UNRELIABLE, for the reason presence is: another one follows in 100 ms
	and re-transmitting a stale centre would be strictly worse than skipping
	it. Sent UNCONDITIONALLY rather than only while a storm is alive, because
	the all-clear is what frees a peer's copy promptly when the sky clears; it
	is ~26 bytes at 10 Hz to at most three peers.
	"""
	if mp._rtc == null:
		return
	var state: Dictionary = {"k": -1}
	var weather := mp.get_tree().get_first_node_in_group("weather")
	if weather != null and weather.has_method("weather_sync_state"):
		var live: Dictionary = weather.call("weather_sync_state")
		if not live.is_empty():
			state = live
	state["t"] = "wx"
	var bytes: PackedByteArray = var_to_bytes(state)
	mp._rtc.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	# Targeted, not broadcast-to-peer-0, for the reason `_send_presence()` spells
	# out: `_connections` holds peers negotiation has merely STARTED with.
	var peers: Dictionary = mp._rtc.get_peers()
	for pid: int in peers:
		if not bool((peers[pid] as Dictionary).get("connected", false)):
			continue
		mp._rtc.set_target_peer(pid)
		mp._rtc.put_packet(bytes)


static func receive_wx(mp: Node, from_id: String, packet: Dictionary) -> void:
	"""
	Apply one storm packet from the master.

	DROPPED UNLESS IT CAME FROM THE MASTER, and dropped while WE are the
	master, for exactly `MpCrocSync.receive_croc_sync()`'s reasons: the mesh is
	peer input, so without the first any member could put a storm over
	everybody, and without the second our own sky would be driven by an echo of
	itself.
	"""
	if from_id != mp._master or mp._master == mp._you:
		return
	var state: Dictionary = MpCodec.decode_wx(packet)
	if state.is_empty():
		return  # The ninth trust boundary refused it; whole or nothing.
	var weather := mp.get_tree().get_first_node_in_group("weather")
	if weather == null or not weather.has_method("apply_weather_sync"):
		return  # No weather manager in this scene — not an error, the LOD idiom.
	weather.call("apply_weather_sync", state)


# =============================================================================
# CROCODILE ABILITIES THROUGH THE MASTER (phase 5)
# =============================================================================
#
# Two player abilities change a crocodile's state rather than merely reading it,
# and once the master simulates the pack, a peer doing either LOCALLY changes
# nothing anybody else can see — the very next sync packet overwrites it. So both
# are routed to the master, over the MESH and RELIABLE (each is a one-off event:
# a lost one is an ability that visibly did nothing):
#
#     flee   peer   → master   {"t":"flee","x","y","z","d"}    Phoboman's wave
#     shr    peer   → master   {"t":"shr","x","y","z","d","r"} Teibi's Shrink Ray
#     pad    peer   → master   {"t":"pad","f":int,"p":int}     an HQ lure plate
#     kill   peer   → master   {"t":"kill","id":int}           giant Teibi's crush
#     dead   master → everyone {"t":"dead","id":int}           the kill ruling
#     bait   anyone → everyone {"t":"bait","x","y","z"}        a Kimchi jar
#
# `bait` is the odd one and `publish_bait()` says why at length: the jar is a
# PICTURE as well as an effect (owner ruling 2026-09-18), so it goes to the whole
# room rather than to the master, everybody draws one, and the master's copy is
# still the one whose beats the pack obeys.
#
# THERE IS DELIBERATELY NO `flee` OR `shr` BROADCAST: `is_fleeing` and
# `is_shrunk` are both bits in the sync packet's flag byte, so the master applying
# `flee_from()` / `shrink_for()` reaches every peer 100 ms later through machinery
# that already exists. A kill needs its own broadcast only because it FREES a
# node, which no amount of transform sync can express.
#
# `flee`, `shr` and `pad` are below; the `kill`/`dead` pair moved to
# `mp_croc_sync.gd` with the rest of the crocodile family (bd godot-test1-ftn.18),
# and this table is still the one place all five are written down together.

static func request_croc_flee(mp: Node, origin: Vector3, duration: float, radius: float = 0.0,
		tracks_player: bool = true) -> bool:
	"""
	Phoboman's Stink Wave, made room-wide: scare the crocodiles this peer can see
	AND ask the master to scare the ones it is the authority for, so a wave set
	off on one screen turns the pack on every other one too.

	A NO-OP OFFLINE. `_ability_phoboman()`'s own local loop stays exactly as it
	was; the local pass here is what `clear_nearby_crocodiles()` needs, since that
	caller has no local alternative left in a room. Applying locally as well as
	relaying is not redundant: the master only drives the crocodiles ITS terrain
	has loaded, so a peer more than a render distance away from the master gets
	nothing back at all — the same coverage ceiling the croc sync documents — and
	a respawning player would have had no spawn protection whatsoever.

	`tracks_player` is false when the CASTER is not the local player, so the flight
	runs from the fixed `origin` - the same distinction `_receive_flee()` makes for a
	relayed wave, exposed here because the vent purge is a local caller naming a
	remote position.

	`radius` bounds the wave to `radius` metres of `origin`; 0.0 means unbounded
	(Phoboman's wave, which is global by design). WITHOUT IT the bounded sweep
	`clear_nearby_crocodiles()` performs solo became a room-wide one: every death
	by any peer disarmed every awake crocodile in the room for four seconds.

	RETURNS whether the room has taken it over — false offline only, so a caller
	whose LOCAL alternative would break the room
	(`player_controller.clear_nearby_crocodiles()`, which frees bodies the master
	is the authority for) can fall through on one test, the same shape
	`request_croc_kill()` uses. It is true even when the relay could not leave,
	because the local pass above still ran and freeing is never right in a room.
	"""
	if not mp.is_online():
		return false
	# Whatever we can reach ourselves, scare now. Harmless on remote-driven
	# crocodiles (the next sample overwrites the flag 100 ms later) and on the
	# master this IS the authoritative application.
	# `tracks_player` FALSE for a caster who is not the local player - the cell
	# block's vent purge, which names a TEAMMATE's position. Default true, so
	# Phoboman's wave and `clear_nearby_crocodiles()` are byte-for-byte unchanged;
	# without it a purge fired on the master would send the pack running from the
	# prisoner in the tower, i.e. straight at the teammate it was meant to help.
	apply_flee(mp, origin, duration, radius, tracks_player)
	if mp._master == mp._you:
		return true
	mp._send_reliable_to_master(var_to_bytes({
		"t": "flee", "x": origin.x, "y": origin.y, "z": origin.z,
		"d": duration, "r": radius,
	}))
	return true


static func apply_flee(mp: Node, origin: Vector3, duration: float, radius: float = 0.0, tracks_player: bool = true) -> void:
	"""
	The same group loop `player_controller._ability_phoboman()` runs, over the
	crocodiles this peer drives.

	No boss test here on purpose — `flee_from()` itself early-returns for a boss
	(Stink Wave immunity), so the rule stays in the one file that owns it.

	`tracks_player` is false for a RELAYED wave: this peer has no body for the
	caster, so the flight must run from the fixed `origin` rather than from our
	own player — see `piglet_crocodile_ai.flee_from()`.
	"""
	var radius_sq: float = radius * radius
	for croc: Node in mp.get_tree().get_nodes_in_group("crocodile"):
		# `is Node3D` alongside the has_method guard, like every other group loop
		# here: `croc as Node3D` on a non-Node3D yields null, and the property read
		# below is then a hard error — which in GDScript unwinds the whole function,
		# abandoning every remaining crocodile mid-sweep.
		if not is_instance_valid(croc) or not (croc is Node3D) or not croc.has_method("flee_from"):
			continue
		if radius > 0.0 and (croc as Node3D).global_position.distance_squared_to(origin) > radius_sq:
			continue
		croc.flee_from(origin, duration, tracks_player)


static func receive_flee(mp: Node, _from_id: String, packet: Dictionary) -> void:
	"""
	MASTER ONLY: another peer's Stink Wave, arriving over the mesh as unvalidated
	peer input — so the origin and the duration are both checked finite and
	bounded before either reaches a crocodile, and a packet failing any of it is
	dropped whole (no partial trust, exactly like the other boundaries here).

	`d` is the field that matters: a fleeing crocodile is a harmless one, so an
	unbounded duration would disarm the whole room for its lifetime.
	"""
	if mp._master != mp._you:
		return
	if not MpCodec._is_number(packet.get("x", null)) or not MpCodec._is_number(packet.get("y", null)) \
			or not MpCodec._is_number(packet.get("z", null)) or not MpCodec._is_number(packet.get("d", null)):
		return
	var origin := Vector3(float(packet["x"]), float(packet["y"]), float(packet["z"]))
	var duration: float = float(packet["d"])
	# Finiteness is checked BEFORE anything is derived from these, the same rule
	# decode_presence() states: a NaN origin would poison every flee heading it
	# touched, and on wasm a non-finite float→int trunc can trap the module.
	if not is_finite(origin.x) or not is_finite(origin.y) or not is_finite(origin.z):
		return
	if absf(origin.x) > MpCodec.MAX_PRESENCE_COORD or absf(origin.y) > MpCodec.MAX_PRESENCE_COORD \
			or absf(origin.z) > MpCodec.MAX_PRESENCE_COORD:
		return
	if not is_finite(duration) or duration <= 0.0 or duration > MAX_FLEE_DURATION:
		return
	# `r` is optional (a phase-5.0 peer sends none) and bounded like everything
	# else here; a missing or malformed one reads as 0.0 = unbounded, which is
	# what that older peer meant.
	var radius: float = 0.0
	if MpCodec._is_number(packet.get("r", null)):
		radius = float(packet["r"])
		if not is_finite(radius) or radius < 0.0 or radius > MpCodec.MAX_PRESENCE_COORD:
			return
	# tracks_player FALSE: the caster is on another screen, so the crocodiles must
	# run from `origin`, not from our own player.
	apply_flee(mp, origin, duration, radius, false)


static func request_croc_shrink(mp: Node, origin: Vector3, duration: float,
		radius: float) -> bool:
	"""
	Teibi's Shrink Ray, made room-wide (bead godot-test1-0mr0.4): the `flee` verb's
	shape one verb along, and everything it shares with that one it shares for that
	one's reasons — so read `request_croc_flee()` above first.

	The three differences, and each is a design decision rather than a detail:

	  * THE RADIUS IS MANDATORY. Phoboman's wave is global by design and passes 0
	    for "unbounded"; an 8 m pulse is the whole of what makes this a corridor
	    you walk through rather than a room-wide disarm, so a zero here is a bug
	    and `MpCodec.decode_shr()` refuses one on the wire.
	  * NO `tracks_player`. A flee needs to know whose position to run FROM; a
	    shrink is not a heading, so the origin is only ever the centre of a sphere
	    and a relayed pulse needs no caster at all.
	  * THERE IS DELIBERATELY NO BROADCAST, for the same reason the flee has none:
	    `is_shrunk` is a bit in the sync packet's flag byte (`CROC_FLAG_SHRUNK`),
	    so the master applying `shrink_for()` reaches every peer 100 ms later
	    through machinery that already exists.

	APPLIED LOCALLY AS WELL AS RELAYED, for the coverage reason the flee gives: the
	master only drives the crocodiles ITS terrain has loaded, so a peer a render
	distance away from the master would otherwise get nothing back at all and press
	G on a pack that never blinked.

	@return whether the room has taken it over — false OFFLINE only, the same
	    one-test shape `request_croc_flee()` gives its callers.
	"""
	if not mp.is_online():
		return false
	apply_shrink(mp, origin, duration, radius)
	if mp._master == mp._you:
		return true
	mp._send_reliable_to_master(var_to_bytes({
		"t": "shr", "x": origin.x, "y": origin.y, "z": origin.z,
		"d": duration, "r": radius,
	}))
	return true


static func apply_shrink(mp: Node, origin: Vector3, duration: float, radius: float) -> void:
	"""
	The same group loop `player_abilities._shrink_crocodiles()` runs, over the
	crocodiles this peer drives.

	No boss test and no `crush_immune` test here on purpose — `shrink_for()` owns
	all three of its early returns, which is what keeps the rule in the one file
	that owns it. `apply_flee()`'s rule, verbatim.

	`is Node3D` alongside the `has_method` guard for `apply_flee()`'s reason: a
	property read on a null cast is a hard error, and in GDScript that unwinds the
	whole function — abandoning every remaining crocodile mid-sweep.
	"""
	var radius_sq: float = radius * radius
	for croc: Node in mp.get_tree().get_nodes_in_group("crocodile"):
		if not is_instance_valid(croc) or not (croc is Node3D) or not croc.has_method("shrink_for"):
			continue
		if (croc as Node3D).global_position.distance_squared_to(origin) > radius_sq:
			continue
		croc.shrink_for(duration)


static func receive_shr(mp: Node, _from_id: String, packet: Dictionary) -> void:
	"""
	MASTER ONLY: another peer's Shrink Ray, arriving over the mesh as unvalidated
	peer input. Whole or nothing through `MpCodec.decode_shr()`, which is where
	every bound and the reason for it is written down.

	The master test is the authority half and it is not a formality: this verb
	mutates bodies the master simulates for the whole room, so a non-master that
	acted on it would be applying a stranger's pulse to a copy nobody else can see
	— exactly the divergence the croc sync exists to prevent.
	"""
	if mp._master != mp._you:
		return
	var msg: Dictionary = MpCodec.decode_shr(packet)
	if msg.is_empty():
		return
	apply_shrink(mp, msg["origin"] as Vector3, float(msg["d"]), float(msg["r"]))


static func request_guard_lure(mp: Node, floor_index: int, pad_index: int) -> bool:
	"""
	An HQ lure plate was stepped on: divert that storey's guard, room-wide.

	@return: whether the room has taken it over — false OFFLINE ONLY, which is the
	    caller's signal to apply the press itself (`TowerInterior._press_lure_pad`,
	    the same one-test shape `request_croc_flee()` gives its callers).

	THE `flee` VERB'S SHAPE, ONE VERB ALONG, and everything it does not do is the
	point: no transform, no flag, no broadcast. The master applies the press to the
	guard it is the authority for and the walk reaches every other screen through
	the crocodile sync that is already running — a lured guard is just a crocodile
	that is somewhere else 100 ms later.

	APPLIED LOCALLY AS WELL AS RELAYED, for the coverage reason the flee's own
	docstring states: the master only drives the bodies ITS terrain has streamed
	in, so a peer standing in the HQ while the master is a kilometre away in the
	field would otherwise press a plate that did nothing at all. On that peer the
	guard is nobody's remote, so the local pass IS the simulation; where the master
	does drive it, `investigate_point()` refuses a remote-driven body and the local
	pass is a no-op.
	"""
	if not mp.is_online():
		return false
	apply_guard_lure(mp, floor_index, pad_index)
	if mp._master == mp._you:
		return true
	mp._send_reliable_to_master(var_to_bytes({
		"t": "pad", "f": floor_index, "p": pad_index,
	}))
	return true


static func apply_guard_lure(mp: Node, floor_index: int, pad_index: int) -> void:
	"""
	Hand one press to the building. Group-discovered and `has_method`-guarded like
	every other cross-system call here: no tower streamed in on this machine and
	there is no guard to divert, which is not an error.
	"""
	var interior := mp.get_tree().get_first_node_in_group("tower_interior")
	if interior == null or not interior.has_method("lure_guard"):
		return
	interior.call("lure_guard", floor_index, pad_index)


static func receive_pad(mp: Node, from_id: String, packet: Dictionary) -> void:
	"""
	MASTER ONLY: another peer stepped on a lure plate.

	THE VERB CARRIES INTENT AND NOTHING ELSE — a storey and a plate index — so
	there is no position to spoof and no body to name. What makes it safe is the
	pair of questions asked here, both against things this machine owns:

	  1. IS THERE SUCH A PLATE? `pad_world()` reads the authored plan, so a peer
	     naming storey 12 plate 9 names nothing.
	  2. WAS THE SENDER THERE? Its last published presence position has to be
	     within `MAX_PAD_PRESS_DISTANCE` of that plate. Without this a modified
	     client would divert any guard in the building from the far side of the
	     world, which is the whole attack this verb could otherwise offer.

	A master with no tower streamed in answers `Vector3.INF` to question 1 and
	drops the packet — correct, because it also has no guard to divert.
	"""
	if mp._master != mp._you:
		return
	var msg: Dictionary = MpCodec.decode_pad(packet)
	if msg.is_empty():
		return
	var interior := mp.get_tree().get_first_node_in_group("tower_interior")
	if interior == null or not interior.has_method("pad_world"):
		return
	var where: Variant = interior.call("pad_world", int(msg["f"]), int(msg["p"]))
	if typeof(where) != TYPE_VECTOR3:
		return
	if not mp._peer_state.has(from_id):
		return
	var sender: Variant = (mp._peer_state[from_id] as Dictionary).get("pos", null)
	if typeof(sender) != TYPE_VECTOR3:
		return
	if not MpCodec.pad_press_in_reach(sender as Vector3, where as Vector3):
		return
	apply_guard_lure(mp, int(msg["f"]), int(msg["p"]))


# =============================================================================
# KIMCHI JARS — the `bait` verb (bead godot-test1-0mr0.5)
# =============================================================================

static func publish_bait(mp: Node, at: Vector3) -> bool:
	"""
	Phoboman set a Kimchi Offering jar down: put the same jar on every screen in
	the room.

	@param at: where it landed, in WORLD metres.
	@return: whether the room has been told — `publish_alarm()`'s contract and not
	    a delivery receipt. False offline, and false for a jar this machine's own
	    caller got wrong.

	ANYONE-TO-EVERYONE AND NOT MASTER-ARBITRATED, unlike `flee` and `pad`, and the
	reason is the OWNER'S RULING (2026-09-18): "the katana pose and the kimchi jar
	are VISIBLE TO EVERYONE IN THE ROOM in v1". A jar is a PICTURE as much as an
	effect — a clay pot sitting on the ground that the pack is visibly walking
	toward — and a master-arbitrated `bait` puts that picture on exactly one
	machine. So this is `alrm`'s shape rather than `flee`'s: it goes to everybody,
	everybody drops a jar, and every jar runs its own clock.

	THAT IS NOT A SECOND SIMULATION, and the difference is worth stating because
	"master simulates, peers replay" is a CLAUDE.md rule. What a peer's jar does
	locally is exactly what `request_croc_flee()`'s local pass already does, for
	the same documented reasons: it is the real simulation for the bodies the
	master's terrain has not streamed in, and a no-op for the rest
	(`investigate_point()` refuses a `remote_driven` body outright, and a flee
	flag set on one is overwritten by the master's next croc-sync sample 100 ms
	later). So the GAMEPLAY still comes from the master's jar and rides home in
	the flag byte; the peers' copies are the picture and the coverage skirt.

	RELIABLE, because a jar is an EDGE and not a state: nothing re-sends it, and a
	lost one is a pot that never appeared.

	NO REPAIR LEG, `alrm`'s ruling for `alrm`'s reason: a jar is NOT MONOTONE — it
	cracks and frees itself after six seconds — so there is no field on the `room`
	packet and none in the join snapshot. A peer whose ICE is still negotiating
	misses this one, and a jar that arrives four seconds late would be worse than
	a jar that never arrives (its clock would start as everybody else's ended).

	NO LOCAL PASS HERE. The caster's own jar was dropped by
	`PlayerAbilities._ability2_phoboman()` before this was called — the arm owns
	the weakref that gates the second press — so applying again here would be two
	jars in one spot on the caster's screen. `publish_gate_opened()`'s split
	exactly: this function only moves the fact.

	AN OLDER BUILD drops the verb silently (`_receive_mesh_verb`'s forward-
	compatibility arm), which is one peer who does not see the pot.
	"""
	if not mp.is_online():
		return false
	var packet: Dictionary = {"t": "bait", "x": at.x, "y": at.y, "z": at.z}
	# OUR OWN BUG STAYS OFF THE WIRE, tested by running the packet through the
	# RECEIVER'S OWN PARSER rather than by re-stating its bounds — `publish_alarm`
	# argues this at length, and the second half of the argument is the one that
	# keeps working: the encoder and the decoder can now never disagree about a
	# FIELD NAME either.
	if MpCodec.decode_bait(packet).is_empty():
		return false
	mp._broadcast_reliable(var_to_bytes(packet))
	return true


static func receive_bait(mp: Node, from_id: String, packet: Dictionary) -> void:
	"""
	ANY member's jar: drop the same one here.

	No authority test — see `publish_bait()` for why this verb is anyone-to-
	everyone. Safety is two questions, `receive_alrm()`'s pair:

	  1. IS THIS A POINT? `decode_bait()`, whole or nothing: three finite
	     coordinates inside the world's envelope.
	  2. WAS THE SENDER THERE? Its last published presence position, against
	     `MpCodec.bait_place_in_reach()`. Without it a modified client drops jars
	     on the far side of the world and scatters a pack it cannot see.

	QUESTION 2 FAILS OPEN, and for `receive_alrm()`'s reason in as many words:
	every receiver evaluates it against ITS OWN presence table, so failing closed
	would mean a peer whose picture of the sender is stale, or who has none yet,
	silently loses a REAL jar while everybody else sees it. Only a sender this
	machine can place AND places far away is refused.

	WHAT THAT LEAVES: a modified client genuinely standing where it says it is can
	drop a jar 50 m away instead of 3 m away, at the verb's 4/s, in a 2-4 player
	co-op room. It could have walked there.

	NOTHING IS RE-BROADCAST. A replayed jar must not go back on the wire or two
	peers would echo one pot round the room forever — `receive_alrm()`'s `publish`
	flag, expressed here by this arm simply not calling `publish_bait()`.
	"""
	var msg: Dictionary = MpCodec.decode_bait(packet)
	if msg.is_empty():
		return
	# QUESTION 2, FAIL-OPEN. Every branch skipped here is a position this machine
	# could not evaluate — no entry for the sender, or no `pos` on that entry —
	# and each one deliberately lets the jar through rather than refusing it.
	if mp._peer_state.has(from_id):
		var sender: Variant = (mp._peer_state[from_id] as Dictionary).get("pos", null)
		if typeof(sender) == TYPE_VECTOR3 \
				and not MpCodec.bait_place_in_reach(sender as Vector3, msg["at"] as Vector3):
			return
	apply_bait(mp, msg["at"] as Vector3)


static func apply_bait(mp: Node, at: Vector3) -> void:
	"""
	Put one jar in this machine's world, on the same parent the caster's own arm
	uses (`_ability2_phoboman`): the player's PARENT, so it survives a switch, a
	respawn and the player being freed.

	FALLS BACK TO THE MP NODE'S OWN PARENT when there is no local player — a
	spectating or still-loading peer is not a reason to lose the pot, and the jar
	needs a parent and nothing else. Group discovery with no hard reference, like
	every other cross-system call in this file.
	"""
	var host: Node = null
	var player: Node = mp.get_tree().get_first_node_in_group("player")
	if player != null:
		host = player.get_parent()
	if host == null:
		host = mp.get_parent()
	if host == null:
		return
	KimchiJar.drop(host, at)


static func publish_alarm(mp: Node, floor_index: int, local_xz: Vector2) -> bool:
	"""
	A staffer saw somebody: raise that storey's alarm on every screen in the room.

	@param floor_index: the storey, an index into `TowerPlanBoxes.FLOOR_Y`.
	@param local_xz: where they were seen, in metres LOCAL to the shell's origin.
	@return: whether the room has been told — `request_guard_lure()`'s contract and
	    not a delivery receipt. False OFFLINE, and false for a sighting this
	    machine's own caller got wrong; true means the packet was handed to
	    `_broadcast_reliable`, which writes only to peers whose data channel is
	    already open and silently reaches nobody when the mesh is not up.

	THE CALLER HAS ALREADY RAISED IT HERE. Unlike `request_guard_lure()` this does
	not apply anything locally: the alarm lives on the interior and the interior is
	what calls this, so a local pass would be the raise happening twice. This
	function only moves the fact — `publish_gate_opened()`'s shape, and the arm
	that replays it (`receive_alrm`) is the one that goes through the building.

	THE CEILINGS, written here because this is the send site:

	ANYONE-TO-EVERYONE AND NOT MASTER-ARBITRATED, unlike `pad`, and the reason is
	COVERAGE. The master may be two kilometres away in the field with no tower
	streamed in at all, in which case it has no plan to check the sighting against
	and no klaxon to sound — a master-arbitrated alarm would be an alarm nobody
	hears. `pad` tolerates that because a refused lure is a plate that did nothing;
	a refused ALARM is the feature not existing for the party actually inside the
	building. What replaces the master's arbitration is that the packet is
	checkable against constants every machine owns (`MpCodec.decode_alrm()`):
	there is no world coordinate in it to spoof.

	RELIABLE, because it is an EDGE and not a state: nothing re-sends it.

	NO REPAIR LEG, and this is where it parts company with `gate`. An alarm is NOT
	MONOTONE — it expires — so there is no field on the `room` packet and no field
	in the join snapshot, for the same reason the captive set stays out of
	`BestRunStore`: a union merge of something that comes back down is a lie. A
	dropped `alrm` is one alarm one peer missed, and it self-heals when that alarm
	expires anyway. A peer whose ICE is still negotiating simply does not get this
	one, and there is no lobby relay leg either: an alarm that arrives three
	seconds late is worse than an alarm that never arrives.

	AN OLDER BUILD drops the verb silently (`_receive_mesh_verb`'s forward-
	compatibility arm), which is the same no-op as having no tower streamed in.
	"""
	if not mp.is_online():
		return false
	var packet: Dictionary = {
		"t": "alrm", "f": floor_index, "x": local_xz.x, "z": local_xz.y,
	}
	# OUR OWN BUG STAYS OFF THE WIRE, `announce_boss_shot`'s rule — but tested by
	# running the packet through the RECEIVER'S OWN PARSER rather than by
	# re-stating its bounds here. Two reasons, and the second is the one that
	# keeps working: a sighting outside the envelope or on a storey the plans do
	# not draw would be dropped by every peer while this returned true, and the
	# encoder and the decoder can now never disagree about a FIELD NAME either —
	# a typo'd key is a packet that fails to decode here, on this machine, in the
	# self-check, instead of one that decodes nowhere in the room.
	if MpCodec.decode_alrm(packet).is_empty():
		return false
	mp._broadcast_reliable(var_to_bytes(packet))
	return true


static func receive_alrm(mp: Node, from_id: String, packet: Dictionary) -> void:
	"""
	ANY member's sighting: raise the same storey's alarm here.

	No authority test — see `publish_alarm()` for why this verb is anyone-to-
	everyone. Safety is two questions, not one:

	  1. IS THIS A POINT IN THIS BUILDING? `decode_alrm()`, whole or nothing: a
	     storey the plans draw and an x/z inside the envelope, both bounds read
	     from constants this machine owns.
	  2. WAS THE SENDER AT THIS BUILDING? Its last published presence position,
	     against `MpCodec.alarm_sender_at_hq()`. This is `receive_pad()`'s second
	     question and it is here for the reason that one gives in as many words:
	     "without this a modified client would divert any guard in the building
	     from the far side of the world."

	QUESTION 2 FAILS OPEN, AND THAT IS THE WHOLE DIFFERENCE FROM `pad`. `pad` is
	MASTER-ARBITRATED — one machine holds one presence table and decides for the
	room — so it can drop a press whose sender it cannot place. This verb is
	anyone-to-everyone for the coverage reason `publish_alarm()` sets out, so
	every receiver evaluates question 2 against ITS OWN table; failing closed
	there would mean a peer whose presence for the sender is stale, or who has
	none yet, silently loses a REAL alarm while everybody else hears it. So only
	a sender this machine can place AND places far away is refused. Unknown,
	missing or non-finite reads as yes.

	WHAT THAT LEAVES, stated so nobody re-litigates it silently: a modified client
	that is genuinely at the HQ can name a storey it is not on. It gets a guard
	walking to a point on that storey, at the verb's 2/s, in a 2-4 player co-op
	room — and it is already standing in the building, where that guard is a
	threat to it too. The far-side-of-the-world spoof, which is the one that
	matters, is refused by every peer with a current position for the sender.

	The `gate` verb needs none of this because it carries an ID and not a place
	(`MpManager._receive_gate`: "no holder to check and no position to verify").
	Anyone-to-everyone settles WHO MAY SEND; it does not settle whether the
	payload is checkable, and this payload is.

	Applied through group discovery and `has_method`-guarded like every other
	cross-system call in this file: no tower streamed in on this machine and there
	is nothing to raise, which is not an error — `apply_guard_lure()`'s LOD idiom.
	The SAME guard is what lets this verb ship before the alarm itself exists
	(bead godot-test1-buyt.4 is what adds `raise_alarm`); until it lands this is a
	validated, rate-limited no-op and deliberately so.

	`false` is the publish flag: a replayed alarm raises the building's own state
	and must not go back on the wire, or two peers would echo one sighting round
	the room forever.
	"""
	var msg: Dictionary = MpCodec.decode_alrm(packet)
	if msg.is_empty():
		return
	var interior := mp.get_tree().get_first_node_in_group("tower_interior")
	if interior == null or not interior.has_method("raise_alarm"):
		return
	# QUESTION 2, FAIL-OPEN (see above). Every `return` skipped here is a position
	# this machine could not evaluate, and each one deliberately lets the alarm
	# through rather than refusing it: no entry for the sender, no `pos` on that
	# entry, or an interior with no transform to measure against.
	if interior is Node3D and mp._peer_state.has(from_id):
		var sender: Variant = (mp._peer_state[from_id] as Dictionary).get("pos", null)
		if typeof(sender) == TYPE_VECTOR3 \
				and not MpCodec.alarm_sender_at_hq(
					sender as Vector3, (interior as Node3D).global_position):
			return
	interior.call("raise_alarm", int(msg["f"]), msg["xz"] as Vector2, false)
