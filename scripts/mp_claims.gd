class_name MpClaims
extends RefCounted
## THE PICKUP CLAIMS FAMILY — arbitrated claims, confirms, retry ticking and the
## room multiplier arithmetic, lifted whole out of `mp_manager.gd` (bd godot-test1-ftn.30).
##
## THE SPLIT, and why it falls exactly here. `MpManager` keeps the MESH: the
## socket, the peers, presence, the verbs' dispatch table, the join snapshot, the
## rate limits, the hero pool — and it keeps the STATE this file reads
## (`_pending_claims`, `_collected_ids`, `_room_multiplier`, `_room_streak`,
## `_room_streak_deadline_msec`, `_master`, `_you`, `_rtc`, `_state`), because a room's
## bookkeeping belongs to the node that owns the room. The three send helpers
## (`_send_reliable_to_master`, `_broadcast_reliable`, `_is_mesh_peer_connected`)
## also stay on the manager as general mesh primitives. This file keeps the
## HANDLERS: everything that initiates a claim, prices it on the master,
## confirms it room-wide, retries unacknowledged claims or falls back to local awards.
##
## WHY STATIC FUNCTIONS AND NO STATE. There is exactly one MP node in a scene and
## its state is the room's, so a second object holding half of it would be a
## second thing to reset on `leave()`. Every function here takes the manager as
## its first argument and reaches back through it — `mp._pending_claims`,
## `mp.is_online()`, `mp._broadcast_reliable()` — which is one direction only.
## The parameter is typed `Node` rather than `MpManager` to avoid a circular
## parse-time reference, as `MpManager` aliases the constants below.
##
## IT IS A MOVE AND NOTHING ELSE. Every rule, every measured number and every
## comment below arrived unchanged from `mp_manager.gd`; the only edits are the
## `mp.` dereferences and the dropped leading underscore on the names.


const PLAYER_SCRIPT := preload("res://scripts/player_controller.gd")

## PICKUP CLAIMS. An unconfirmed claim is re-sent every CLAIM_RETRY_SEC, at most
## CLAIM_MAX_TRIES times; 0.5 s × 4 is 2 s, comfortably over a relay-free mesh
## round trip and short enough that a player never notices a coin "thinking".
const CLAIM_RETRY_SEC: float = 0.5
const CLAIM_MAX_TRIES: int = 4

## Trust-boundary bounds on a claim (see `receive_claim`). `n` drives a LOOP on
## the master, so it is the one field a hostile peer could turn into a frame
## stall — the largest honest claim in the game is a treasure chest's
## CHEST_COINS_MAX (15) pickups, so 64 is generous. `v` is the base value per
## pickup: 1 for a coin, `Coin.GEM_VALUE` (10) for a gem.
const MAX_CLAIM_PICKUPS: int = 64
const MAX_CLAIM_VALUE: int = 1000


# =============================================================================
# PICKUP CLAIMS (phase 5)
# =============================================================================
#
# Coins and treasure chests are deterministic: every peer in the room has its own
# copy of the same pickup in the same place. Through phase 4 that meant two peers
# walking over one coin each banked it into the SHARED bank — the room paid twice
# for one coin, and a chest (~12 pickups) paid twice for twelve.
#
# The fix is an arbitrated claim, all over the MESH and RELIABLE (a lost claim is
# a pickup that pays nothing; a lost confirm is a pickup that pays twice — neither
# is something an unreliable channel may drop):
#
#     claim    peer   → master   {"t":"clm","id":int,"n":int,"v":int}
#     confirm  master → everyone {"t":"cnf","id":int,"by":int,"a":int,"m":int}
#
# `n` is how many PICKUPS (1 for a coin, the whole burst for a chest), `v` the
# base value of each (1, or Coin.GEM_VALUE). `by` is the winner's `peer_int_id`,
# `a` the total awarded AFTER the room's multiplier, and `m` the room's
# multiplier after the award, so every peer's HUD shows the same `(xN)`.
#
# FIRST CLAIM WINS, and the set that decides it is `_collected_ids` — the very
# set phase 4 already keeps and already replays to a joiner. A second claim for an
# id already in it is refused with no confirm, and the loser's pickup is simply
# gone: it was already gone on the winner's screen.

static func claim_pickup(mp: Node, id: int, count: int, value: int) -> bool:
	"""
	Ask the room for this pickup. Returns true when the claim was taken over (the
	caller must NOT award anything — the confirm does that), false when the caller
	should run its ordinary solo path.

	FALSE OFFLINE, so every call site falls through to today's behaviour on one
	test — the same `null`/`false` discipline `shared_bank()` and friends use.

	@param id: the pickup's stable id (`Coin.id_at`), which every peer derives
	    identically because every spawner is a pure function of `run_seed`.
	@param count: how many PICKUPS this is worth for streak purposes — 1 for a
	    coin, the whole burst for a chest, which is what makes a chest step the
	    room's multiplier exactly as it steps a solo one.
	@param value: the base value of each pickup, before the room's multiplier.
	"""
	if not mp.is_online():
		return false
	# No mesh means no arbitration is possible: `--lobby-only`, or a room whose
	# ICE never completed. Falling back to the solo path banks the pickup locally,
	# which is exactly the phase-4 behaviour this replaces — a double-count is a
	# far better failure than a coin that pays nobody.
	if mp._rtc == null:
		return false
	if mp._collected_ids.has(id):
		# Somebody already took it. Claim it anyway (true) so the caller hides the
		# pickup without awarding: that is the truth on every other screen.
		return true
	if mp._master != mp._you and not mp._is_mesh_peer_connected(MpCodec.peer_int_id(mp._master)):
		# A MESH THAT EXISTS IS NOT A MESH THAT CONNECTS. `_rtc` is built the
		# moment /ice answers, seconds before any data channel opens — and never
		# opens at all behind a symmetric NAT with no TURN — so the guard above
		# does not actually cover the case its comment describes. Answering true
		# here hid the pickup, sent a claim nobody could receive, and paid it
		# CLAIM_RETRY_SEC × CLAIM_MAX_TRIES (2 s) later from `_tick_claims`; worse,
		# only `_apply_confirm` advances `room_multiplier()`, so with no confirms
		# landing the room was pinned at x1 for the whole run. Same discipline as
		# `request_croc_kill()`: if the request cannot leave, fall through NOW.
		return false
	if mp._master == mp._you:
		resolve_claim(mp, id, MpCodec.peer_int_id(mp._you), count, value)
		return true
	mp._pending_claims[id] = {"n": count, "v": value, "age": 0.0, "tries": 1}
	send_claim(mp, id, count, value)
	return true


static func room_multiplier(mp: Node) -> Variant:
	"""
	The room's current coin multiplier, or `null` offline so
	`player_controller.get_streak_multiplier()` falls through to its own on one
	test — the same trick phase 4 used for the bank, which is why
	`coin_hud.gd` shows the room's `(xN)` with no HUD change at all.

	Expires on its own: a room that stops picking things up for STREAK_WINDOW is
	back to x1 without anybody having to send a "streak broke" message.

	THE GUARDS MUST MATCH `claim_pickup()`'s EXACTLY, and that pairing is the
	whole correctness of the fall-through. When arbitration is impossible
	(`--lobby-only`, ICE never completed, a symmetric NAT with no TURN) that
	function banks the pickup through the ordinary solo path — but this one used
	to keep answering non-null on `_state` alone, and only `_apply_confirm` ever
	advances the room streak, so it returned a hard `1` forever: every coin banked
	at x1 with `(x1)` on the HUD while the peer's own perfectly good `coin_streak`
	was ignored. Falling through to solo has to be BOTH halves or it is neither.
	"""
	if not mp.is_online() or mp._rtc == null:
		return null
	if mp._master != mp._you and not mp._is_mesh_peer_connected(MpCodec.peer_int_id(mp._master)):
		return null
	if Time.get_ticks_msec() > mp._room_streak_deadline_msec:
		return 1
	return mp._room_multiplier


static func room_multiplier_from(streak: int, per_step: int, max_bonus: int) -> int:
	"""
	The score multiplier for a streak of `streak` pickups — the same arithmetic as
	`player_controller.get_streak_multiplier()`, pulled out as a pure static so
	scripts/mp_codec_selfcheck.gd can pin it against the player's own constants without
	a room, a player or a socket.
	"""
	if per_step <= 0:
		return 1  # No step size, no bonus — guards the division below.
	return 1 + mini(max_bonus, streak / per_step)


static func resolve_claim(mp: Node, id: int, by_int: int, count: int, value: int) -> void:
	"""
	MASTER ONLY: award a claimed pickup, or refuse it silently.

	The refusal is `_collected_ids.has(id)` and it is the whole arbitration —
	first claim wins, and a second claimant gets no confirm at all rather than a
	"denied" message, because there is nothing for it to do with one: its pickup
	is already hidden and the id will reach it in a confirm or a join snapshot.

	The room's streak advances ONCE PER PICKUP, exactly as `collect_coin()` does
	per coin, so a chest's burst steps the multiplier the same way in a room as it
	does solo — that is what `count` is for.
	"""
	if mp._collected_ids.has(id):
		return
	# NOT recorded here: `_apply_confirm` below records it, through
	# `_absorb_collected`, which skips ids already in the set and then returns
	# early when nothing was fresh. Recording it up front therefore turned the
	# master's own sweep of the `"coin"` group into a no-op, and `coin.gd`
	# deliberately does not `queue_free()` on the claimed path (it only hides the
	# coin and stops monitoring) — so every coin the MASTER picked up stayed in
	# the tree, invisible and still in the `"coin"` group, until its chunk
	# unloaded. `MpCrocSync.resolve_kill` has the same shape and gets it right:
	# `_dead_crocs` is written inside `apply_dead`, not before it.
	#
	# Safe because nothing between here and `_apply_confirm` re-enters this
	# function: `_broadcast_reliable` is a synchronous `put_packet` loop.

	var now: int = Time.get_ticks_msec()
	if now > mp._room_streak_deadline_msec:
		mp._room_streak = 0  # The window lapsed: the room's chain is broken.
	var awarded: int = 0
	for _pickup: int in count:
		mp._room_streak += 1
		awarded += value * room_multiplier_from(
			mp._room_streak, PLAYER_SCRIPT.STREAK_COINS_PER_STEP, PLAYER_SCRIPT.STREAK_MAX_BONUS
		)
	mp._room_multiplier = room_multiplier_from(
		mp._room_streak, PLAYER_SCRIPT.STREAK_COINS_PER_STEP, PLAYER_SCRIPT.STREAK_MAX_BONUS
	)
	mp._room_streak_deadline_msec = now + int(PLAYER_SCRIPT.STREAK_WINDOW * 1000.0)

	# The PRE-MULTIPLIER worth of the whole claim — `count` pickups at `value`
	# each — for meta-progression (bead godot-test1-42n): lifetime coins count what
	# was physically picked up, so they can never be credited from `a`, which the
	# room's multiplier is already in.
	#
	# IT DOES NOT GO ON THE WIRE, and that is a security decision rather than a
	# saving. A confirm is signed by nothing: the master names the winner in `by`,
	# so a hostile master could address a confirm to somebody else and, with a base
	# value on the wire, hand them any number of LIFETIME coins — which are
	# monotone and persisted, so unlike the run-scoped `a` beside it the damage
	# outlives the room. Every peer can derive this figure for itself instead: the
	# master from the claim it is resolving right here, and a non-master from its
	# own `_pending_claims` entry, which still holds `n`/`v` when the confirm lands
	# (see `_receive_confirm`). So `bank_awarded`'s base total is never anything a
	# peer told us.
	var base_total: int = count * value
	var confirm: Dictionary = {
		"t": "cnf", "id": id, "by": by_int, "a": awarded, "m": mp._room_multiplier,
	}
	mp._broadcast_reliable(var_to_bytes(confirm))
	# And apply it to ourselves: the master is a player too, and this is the only
	# path that banks a pickup it claimed.
	apply_confirm(mp, id, by_int, awarded, mp._room_multiplier, base_total)


static func apply_confirm(mp: Node, id: int, by_int: int, awarded: int, multiplier: int, base_total: int = 0) -> void:
	"""
	Every peer's half of a confirm: the pickup is gone room-wide, and whoever won
	it banks the amount the MASTER already multiplied.

	`_absorb_collected` does double duty here — it records the id AND sweeps the
	live world for a coin still holding it, which is what makes the confirm
	arrival order irrelevant (a coin spawned afterwards asks `is_coin_collected()`
	in its own `_ready()`).

	@param base_total: the claim's PRE-MULTIPLIER worth, for the lifetime-coin
	    counter. ALWAYS DERIVED BY THE CALLER FROM ITS OWN STATE — the master from
	    the claim it is resolving, a peer from its own `_pending_claims` entry —
	    and never taken off the wire, because a confirm names its own winner and a
	    forgeable base value would mint PERSISTED progression rather than a
	    run-scoped bank. Trailing and defaulting to 0 so nothing that does not know
	    about it changes behaviour: 0 means "no base value known" and
	    `bank_awarded()` credits no lifetime coins, which is exactly what every
	    call did before bead godot-test1-42n.
	"""
	mp._absorb_collected([id])
	mp._pending_claims.erase(id)
	mp._room_multiplier = multiplier
	mp._room_streak_deadline_msec = Time.get_ticks_msec() + int(PLAYER_SCRIPT.STREAK_WINDOW * 1000.0)
	if by_int != MpCodec.peer_int_id(mp._you):
		return
	var player: Node = mp.get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("bank_awarded"):
		player.bank_awarded(awarded, base_total)


static func send_claim(mp: Node, id: int, count: int, value: int) -> void:
	"""Send one claim to the master, RELIABLE. A no-op when the master's data
	channel is not open — `_tick_claims` will try again."""
	mp._send_reliable_to_master(var_to_bytes({"t": "clm", "id": id, "n": count, "v": value}))


static func tick_claims(mp: Node, delta: float) -> void:
	"""
	Re-drive claims still waiting on a confirm, and give up on the ones that never
	get one.

	ponytail: giving up RESOLVES THE PICKUP LOCALLY — banked with the local
	multiplier and the id recorded — rather than eating it. The ceiling is a rare
	double-count when the confirm was merely slow (2 s slow); the alternative is a
	coin that visibly vanished and paid nothing, which is worse. The upgrade path
	is the master ACKing the claim itself, so a slow confirm can be distinguished
	from a lost one.
	"""
	if mp._pending_claims.is_empty():
		return
	for id: int in mp._pending_claims.keys():
		var claim: Dictionary = mp._pending_claims[id]
		claim["age"] = float(claim["age"]) + delta
		if float(claim["age"]) < CLAIM_RETRY_SEC:
			continue
		claim["age"] = 0.0
		if int(claim["tries"]) >= CLAIM_MAX_TRIES:
			mp._pending_claims.erase(id)
			resolve_claim_locally(mp, id, int(claim["n"]), int(claim["v"]))
			continue
		claim["tries"] = int(claim["tries"]) + 1
		send_claim(mp, id, int(claim["n"]), int(claim["v"]))


static func resolve_claim_locally(mp: Node, id: int, count: int, value: int) -> void:
	"""
	The retry budget ran out: bank the pickup ourselves through the ordinary solo
	path, so the player is paid for something they visibly picked up.

	`collect_coin` is deliberately the vehicle — it already owns the streak, the
	HUD and the print, and in a room it reads the ROOM's multiplier through
	`get_streak_multiplier()` anyway.
	"""
	# Through `_absorb_collected` rather than a bare set write, so the hidden
	# pickup waiting on that confirm is actually freed — the same sweep the
	# confirm would have run.
	mp._absorb_collected([id])
	var player: Node = mp.get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("collect_coin"):
		return
	for _pickup: int in count:
		player.collect_coin(value)


static func receive_claim(mp: Node, from_id: String, packet: Dictionary) -> void:
	"""
	MASTER ONLY: one peer's claim, arriving over the mesh as unvalidated peer
	input — so every field is type-checked and bounded before it is used, and a
	packet failing any of it is dropped whole (no partial trust, exactly like the
	other four boundaries in this file).

	`n` is the field that matters: it drives the award loop in `_resolve_claim`,
	so an unbounded one would be a frame stall any peer in the room could ask for.
	"""
	if mp._master != mp._you:
		return  # Not ours to arbitrate. A peer on a stale master will retry.
	if typeof(packet.get("id", null)) != TYPE_INT \
			or typeof(packet.get("n", null)) != TYPE_INT \
			or typeof(packet.get("v", null)) != TYPE_INT:
		return
	var count: int = packet["n"]
	var value: int = packet["v"]
	if count < 1 or count > MAX_CLAIM_PICKUPS:
		return
	if value < 1 or value > MAX_CLAIM_VALUE:
		return
	resolve_claim(mp, int(packet["id"]), MpCodec.peer_int_id(from_id), count, value)


static func receive_confirm(mp: Node, from_id: String, packet: Dictionary) -> void:
	"""
	The master's ruling on a claim. ONLY the master's is accepted: the mesh is
	peer-to-peer, so without that check any member could mint confirms and pay
	itself the room's bank — the same authority rule `MpCrocSync.receive_croc_sync()` and
	the seed broadcast both enforce.
	"""
	if from_id != mp._master:
		return
	if typeof(packet.get("id", null)) != TYPE_INT \
			or typeof(packet.get("by", null)) != TYPE_INT \
			or typeof(packet.get("a", null)) != TYPE_INT \
			or typeof(packet.get("m", null)) != TYPE_INT:
		return
	var awarded: int = packet["a"]
	if awarded < 0 or awarded > MpCodec.MAX_STATE_COUNTER:
		return
	# The multiplier only ever feeds the HUD suffix, but it is clamped to the range
	# the game can actually produce so a hostile master cannot print "x9000".
	var multiplier: int = clampi(int(packet["m"]), 1, 1 + PLAYER_SCRIPT.STREAK_MAX_BONUS)
	# THE BASE VALUE FOR META-PROGRESSION IS DERIVED HERE, NEVER READ OFF THE WIRE
	# (bead godot-test1-42n). It comes from OUR OWN pending claim — the entry we
	# wrote in `claim_pickup()` before sending the claim, which still holds `n`/`v`
	# because `_apply_confirm` only erases it further down.
	#
	# Why not a `b` field with a bound on it: a confirm names its own winner, so a
	# hostile master could address one to another member with any base value it
	# liked, and that member would permanently gain those LIFETIME coins for a
	# pickup it never claimed. `a` is forgeable the same way and always has been,
	# but that inflates a run-scoped bank; lifetime coins are monotone and
	# persisted, so the same forgery there outlives the room. Deriving it locally
	# is both smaller and unforgeable: a peer credits progression only for a pickup
	# it can prove to itself that it asked for.
	#
	# Zero when there is no matching claim, which is the correct answer in all
	# three cases it happens: the confirm is for somebody else (we do not bank at
	# all), it is a duplicate whose entry we already consumed, or `_tick_claims`
	# gave up and `_resolve_claim_locally` already paid the progression through
	# `collect_coin`.
	var pickup_id: int = int(packet["id"])
	var base_total: int = 0
	if mp._pending_claims.has(pickup_id):
		var claim: Dictionary = mp._pending_claims[pickup_id]
		base_total = int(claim["n"]) * int(claim["v"])
	apply_confirm(mp, pickup_id, int(packet["by"]), awarded, multiplier, base_total)
