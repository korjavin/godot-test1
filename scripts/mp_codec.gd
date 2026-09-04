class_name MpCodec
extends RefCounted
## THE MULTIPLAYER CODEC — every pure function that turns a peer's bytes into a
## value this build is willing to act on, and the wire-format constants those
## functions are written against. Lifted whole out of scripts/mp_manager.gd
## (bead godot-test1-ftn.11), behaviour unchanged.
##
## THE SPLIT, and why it falls exactly here. `mp_manager.gd` keeps everything
## that has STATE or a SOCKET: the lobby client, the `WebRTCMultiplayerPeer`
## mesh (`_rtc`, which is NEVER assigned to `multiplayer.multiplayer_peer` —
## the single most important line in that file), presence publication, the
## verbs, the per-peer rate limits, the hero pool and the room's totals. This
## file keeps what a packet MEANS: one static, allocation-light function per
## trust boundary, plus the peer-id arithmetic the mesh numbers itself with.
## Nothing here reads instance state, opens anything, or knows a room exists.
##
## THE RULES THESE PARSERS ALL SHARE — they were true before the split and the
## split is what makes them checkable:
##
##   1. **Everything relayed is unvalidated peer input.** Room codes are public
##      over `/rooms`, so "a peer in the room" means "anyone"; the master is only
##      the oldest member, not a trusted party.
##   2. **Whole or nothing.** A parser returns the validated value or an EMPTY
##      DICTIONARY, never a half-trusted one, so the caller's failure branch is
##      one `is_empty()` test and there is no partial state to reason about.
##   3. **`bytes_to_var`, never `bytes_to_var_with_objects`.** Only
##      `decode_presence()` takes bytes at all; every other entry point takes
##      the already-decoded Dictionary, so there is one place in the project
##      where a mesh packet becomes a Variant.
##   4. **Finiteness BEFORE any cast.** `int(NAN)` is undefined and on wasm the
##      float→int trunc can trap the module outright — one hostile packet would
##      take the tab down before any range check ran.
##   5. **Missing is not malformed, present-and-bad is.** A field a later build
##      added must cost an older peer nothing, because `build_version`
##      deliberately refuses to reload a peer that is in a room: mixed-build
##      rooms are a state that really happens and lasts.
##
## WHY STATIC, AND WHY THAT IS THE WHOLE POINT. `scripts/mp_selfcheck.gd`,
## `scripts/capture_selfcheck.gd` and `scripts/landmark_progress_selfcheck.gd`
## beat on these with fistfuls of hostile packets without standing up a mesh, a
## lobby or a room. That was already true when they lived in `mp_manager.gd` —
## every one of them was written `static` and `_rtc`-free on purpose — so this
## file is where the shape those functions already had is finally the file
## boundary too.


# =============================================================================
# WIRE-FORMAT BOUNDS
# =============================================================================

## The constant banner of the code below, moved with it. Every one of these is
## a bound a parser in this file enforces; `mp_manager.gd` reads the handful it
## also needs on the SEND side (`MpCodec.MAX_STATE_IDS` when it truncates its
## own id lists, `MpCodec.MAX_CROC_SYNC` when it fills a sync packet) through
## this class, so the encoder and the decoder cannot name different numbers.

## Sanity bounds on a presence packet's position and speed. Generous by design —
## a real run is a few km along +X — because these exist to reject hostile
## garbage, not to police where a peer may stand. See `decode_presence()`.
const MAX_PRESENCE_COORD: float = 1.0e7
const MAX_PRESENCE_SPEED: float = 1.0e4

## Caps on a join snapshot — see `decode_state()`. `MAX_STATE_IDS` bounds BOTH
## ends of BOTH id lists — the collected-coin set and the crushed-crocodile kill
## list, each in the one we send and the one we accept.
## `MAX_STATE_COUNTER` is a sanity bound on the coin/distance counters,
## generous by design because it exists to reject hostile garbage, not to police
## how long a run may get.
const MAX_STATE_IDS: int = 2048
const MAX_STATE_COUNTER: int = 1000000000

## Coin ids are `hash()` output, so 32 bits — but they cross the relay as JSON
## doubles, and `int()` on a value past a double's exact-integer range is
## undefined (on wasm the float→int trunc can trap the module outright). 2⁵³ is
## that range, so anything beyond it is refused before the cast.
const MAX_STATE_ID_MAGNITUDE: float = 9007199254740992.0

## State byte carried by a crocodile sync entry (see `_send_croc_sync()` and
## `decode_croc_sync()`). Declared HERE, once, so the encoder on the master and
## the decoder in `piglet_crocodile_ai.set_remote_state()` cannot drift apart.
const CROC_FLAG_CHASING: int = 1
const CROC_FLAG_FLEEING: int = 2
const CROC_FLAG_PAUSED: int = 4
const CROC_FLAG_BITING: int = 8
## The ambusher's burrow (asc.4). It is the one piece of a crocodile's pose that
## is NOT derivable from the bits above: the sand viper buries itself whenever it
## is not chasing, but that decision is made by the behaviour dispatch, which a
## paused or fleeing crocodile never reaches — so through either state the flag
## FREEZES at whatever the strike left it, and a peer recomputing `not chasing`
## for itself surfaces a viper the master left buried (or buries one it left
## striking) for as long as that state lasts. Sending the answer costs a bit that
## was spare; deriving it costs a desync with no bound on how long it shows.
const CROC_FLAG_BURROWED: int = 16
##
## THE HUNTER OWES NO BIT, AND THAT IS A RULING, NOT A DEFERRAL (bead
## godot-test1-9rm.5). The hunt arm has three states — telegraphing, shadowing at
## its standoff ring, closing — and none of them earns a flag, because the
## BURROW'S TEST is the test, and the hunt fails it in the opposite direction: the
## viper's burrow changes the POSE while the body stands still, so a peer that
## cannot see the bit cannot see the viper. Shadow-vs-close changes only where the
## unit WALKS (`hunt_steer_point` bends `chase_target` and touches nothing else —
## no mesh, no scale, no visibility, no animation input), and where it walks is
## the position this packet already carries at full fidelity, 10 Hz eased. A peer
## therefore renders a pacing hunter pacing and a closing hunter closing without
## being told which it is, and there is no state that FREEZES the way the burrow
## does: the arm is skipped wholesale on a remote-driven body, so nothing stale
## can accumulate there to disagree with.
##
## The acquisition cue is the same answer from the other end: it belongs on the
## not-chasing -> chasing edge, which already rides CROC_FLAG_CHASING and is
## already restored by `set_remote_state`, so a peer has the edge a cue needs
## without a sixth bit. (Today the arm fires it, which is silent on a peer — see
## the ping note in bead godot-test1-9rm.6.)
##
## Three bits are spare; the reason not to spend one is that a bit nothing reads
## is a bit the encoder and the decoder can drift apart on. If a hunter ever grows
## a pose that motion cannot show — a lock-on beam, a carry animation — it takes
## bit 32 and extends BOTH sides, which `mp_selfcheck._check_hunter_sync()` sweeps
## for: it round-trips every combination the encoder can produce and fails if the
## decoder has not learned one.

## Most crocodile entries one sync packet may carry — see `decode_croc_sync()`.
## Generous by design: the master only ever sends the crocs awake around one
## peer, which is a couple of dozen. Like `MAX_STATE_IDS`, this exists to reject
## hostile garbage before it is walked, not to police the size of the pack.
const MAX_CROC_SYNC: int = 192

## How far outside a Budapest landmark's OWN radius a peer may be standing and
## still have walked into it, in metres.
##
## THE TRUST BOUNDARY THE `lmk` VERB NEEDS, and the reason the packet carries a
## slot INDEX and no position at all — `MAX_PAD_PRESS_DISTANCE`'s rule one verb
## along. The master looks the slot up in the authored plan and asks whether the
## sender was anywhere near it; without that a modified client explores the whole
## city from the gate and hands the room a win nobody walked.
##
## Generous on purpose, and it has to be: the claim is triggered at
## `radius + landmark_toast.APPROACH_PAD` (6 m) but presence is only published at
## `PRESENCE_HZ`, so the master's picture of the sender can be a fraction of a
## second — several metres of running — behind the moment the trigger fired.
## Against slot radii of 40-156 m this is a small skirt, not a second radius.
const MAX_LANDMARK_CLAIM_PAD: float = 30.0

## How far from a lure plate a peer may be and still have pressed it, in metres.
##
## THE TRUST BOUNDARY THE `pad` VERB NEEDS, and the reason the packet carries a
## plate INDEX and no position at all: the master looks the plate up in the
## authored plan and then asks whether the sender was anywhere near it. Without
## the second half a modified client diverts any guard in the building from
## anywhere in the world. Generous — presence is published at PRESENCE_HZ and the
## plate is a 1.94 m cell — and still three cells wide, against a 78 m storey.
const MAX_PAD_PRESS_DISTANCE: float = 6.0

## Trust-boundary bound on the `cd` field. RETIRED AS A VALUE, KEPT AS A SHAPE
## (owner veto 2026-09-01, bead `godot-test1-ueg`): this build always publishes 0.0
## and reads nothing off it, but `decode_room()` DROPS a packet missing `cd`, and
## `build_version` refuses to reload a peer that is in a room — so a mixed room is a
## state that really happens and an older master's real clock must still decode, or
## the room's cells stop converging over a field nobody uses.
const MAX_CUSTODY_SECONDS: float = 3600.0

## Highest `co` value THIS build understands. RETIRED AS A VALUE, KEPT AS A SHAPE
## alongside `MAX_CUSTODY_SECONDS` (owner veto 2026-09-01, bead `godot-test1-ueg`):
## nothing reads the field, but `decode_room()` folds anything above it DOWN rather
## than dropping the packet, because the `room` packet is also the captive-set
## repair channel and an older master's larger verdict must not cost a mixed room
## its cells.
const CUSTODY_VERDICT_MAX: int = 2

## Longest hero name a `cap` packet or a join snapshot may carry. The names are
## `player_controller.CHARACTERS` entries ("phoboman" is the longest at 8), and the
## value is only ever tested against `_pool` - the lobby's own list - so this is a
## cheap length gate in front of that whitelist, not the whitelist itself.
const MAX_HERO_NAME: int = 32

## Most captive heroes one join snapshot may assert. A sender may only assert its
## OWN capture and a peer holds at most one hero, so the honest value is 0 or 1;
## the cap is a little roster-sized slack, and a longer list is hostile by
## construction.
const MAX_STATE_CAPTIVES: int = 8

## The player script, preloaded ONLY to read the CHARACTERS list — a presence
## packet's `c` is an index into it, so the bound is the roster itself and never
## a number written down twice. `mp_manager.gd` carries the same preload for the
## coin-economy constants it reads; two files naming one resource is not two
## sources of truth, and neither may re-type what it finds there.
const PLAYER_SCRIPT := preload("res://scripts/player_controller.gd")


# =============================================================================
# PEER ID MAPPING
# =============================================================================

static func peer_int_id(lobby_id: String) -> int:
	"""
	Turn the lobby's 16-hex-character peer id into the `int` id
	`WebRTCMultiplayerPeer` requires.

	The first 7 hex digits give 28 bits, and `+ 2` puts the result safely clear of
	the two ids MultiplayerPeer reserves (0 = broadcast/none, 1 = server). Every
	peer derives every *other* peer's int id with this same pure function, so the
	whole mesh agrees on the numbering with **no extra protocol** — nobody has to
	be told what to call anybody.

	ponytail: two of four peers colliding on the same 28-bit prefix is a ~2e-7
	birthday chance. The upgrade path, if it ever matters, is having the room
	master assign small ids over the relay — which costs a round trip that this
	buys for free.
	"""
	return ("0x" + lobby_id.substr(0, 7)).hex_to_int() + 2

# =============================================================================
# SHARED HELPER
# =============================================================================

static func _is_number(value: Variant) -> bool:
	"""JSON gives ints and floats interchangeably, so accept either."""
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

# =============================================================================
# PACKET DISPATCH
# =============================================================================

static func packet_kind(packet: Dictionary) -> String:
	"""
	Which kind of mesh packet this is: `""` for presence, otherwise the verb.

	THE WHOLE BACKWARD-COMPATIBILITY RULE LIVES HERE. A phase-3/4 peer sends no
	`"t"` key, so its packet must land on the presence path; a packet carrying a
	verb — including one from a LATER build that this one has never heard of —
	must NOT, because the fields beside the verb can be a perfectly valid presence
	packet and would decode there. Pulled out as a pure static rather than left
	inline so `scripts/mp_selfcheck.gd` can pin both directions: driving
	`_receive_mesh_verb()` directly cannot test this, since that function has no
	presence branch to leak through and the assertion passes no matter what the
	dispatch does.
	"""
	return str(packet["t"]) if packet.has("t") else ""

# =============================================================================
# PRESENCE — the first trust boundary
# =============================================================================

static func decode_presence(bytes: PackedByteArray) -> Dictionary:
	"""
	The presence packet parser, and the whole trust boundary in one pure function.

	Returns the validated state, or an EMPTY DICTIONARY for anything that fails —
	a packet is trusted whole or dropped whole, there is no partial trust. Static
	and `_rtc`-free so scripts/mp_selfcheck.gd can hold it to that with a fistful
	of malformed byte arrays.

	Kept as the byte-array entry point even though `_receive_mesh_packets()` now
	decodes once and dispatches on `"t"`: the selfcheck pins this signature, and
	the validation itself lives in `_decode_presence_dict()` so there is ONE
	validator rather than two that can drift.
	"""
	var decoded: Variant = bytes_to_var(bytes)
	if typeof(decoded) != TYPE_DICTIONARY:
		return {}
	return _decode_presence_dict(decoded as Dictionary)


static func _decode_presence_dict(state: Dictionary) -> Dictionary:
	"""
	Validate an already-decoded presence Dictionary. See `decode_presence()` for
	the contract: whole or nothing, `{}` on any failure.
	"""
	if typeof(state.get("p", null)) != TYPE_VECTOR3 \
			or typeof(state.get("g", null)) != TYPE_BOOL \
			or not _is_number(state.get("y", null)) \
			or not _is_number(state.get("s", null)) \
			or not _is_number(state.get("c", null)):
		return {}

	var pos: Vector3 = state["p"]
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
		return {}
	var yaw: float = float(state["y"])
	var speed: float = float(state["s"])
	# `c` is folded into the SAME gate rather than trusted up to its range check:
	# `_is_number` accepts a float, and `int(NAN)` is undefined — on wasm the
	# float→int trunc can trap the module outright, so one hostile packet would
	# take the tab down before `char_index < 0` ever ran.
	if not (is_finite(yaw) and is_finite(speed) and is_finite(float(state["c"]))):
		return {}

	# `y` LATCHES TOO, and wrapping is the whole fix: an angle has no natural
	# magnitude limit, but `RemoteAvatar` assigns it to `rotation.y` (float32) and
	# then eases it with `lerp_angle`, which is `from + short_way * weight` — and
	# `1e30 + anything small IS 1e30`. One packet and that avatar's basis is
	# garbage (sin/cos of 1e30) for the rest of the room, with no path back.
	# Wrapping into [0, TAU) is lossless for every honest sender, so this
	# normalises rather than dropping.
	yaw = fposmod(yaw, TAU)

	# FINITE IS NOT THE SAME AS SANE, and `s` is the one that latches: 1e38 is
	# finite, and `RemoteAvatar._animate` does `stride_phase += move_speed *
	# delta * ...`, so ONE such packet makes the accumulator infinite and every
	# limb rotation NaN for the rest of the room — the same permanent poisoning
	# the position's finiteness check exists to prevent. Bound both.
	if absf(pos.x) > MAX_PRESENCE_COORD or absf(pos.y) > MAX_PRESENCE_COORD \
			or absf(pos.z) > MAX_PRESENCE_COORD or absf(speed) > MAX_PRESENCE_SPEED:
		return {}

	var char_index: int = int(state["c"])
	if char_index < 0 or char_index >= PLAYER_SCRIPT.CHARACTERS.size():
		return {}

	# The shared-total fields, validated exactly like `c`: number, finite,
	# non-negative, bounded. MISSING IS NOT MALFORMED — a phase-3 peer sends a
	# packet without them, and dropping those whole would make an older peer
	# invisible rather than merely un-counted — so absent reads as 0 and only a
	# value that is PRESENT and bad drops the packet.
	#
	# `lv` (this peer's spent lives) and `rl` (the room's hearts) RETIRED with the
	# hearts themselves — bead godot-test1-0bc. They are not in this list and not
	# in the returned dict, so an older peer still sending them is accepted whole
	# and those two fields are simply never looked at.
	var counters: Dictionary = {}
	for key: String in ["cc", "dd"]:
		var raw: Variant = state.get(key, null)
		if raw == null:
			counters[key] = 0
			continue
		if not _is_number(raw):
			return {}
		var value: float = float(raw)
		if not is_finite(value) or value < 0.0 or value > float(MAX_STATE_COUNTER):
			return {}
		counters[key] = int(value)

	# `ab` — the sender's visible ability state, which RemoteAvatar draws as a
	# scale and a wing beat. Same missing-is-not-malformed rule as the counters
	# (absent reads as 0: an older peer keeps its normal-sized avatar rather than
	# going invisible), and BOUNDED TO ONE BYTE so a hostile "ability" cannot be
	# 2^40. Unknown bits are not rejected but IGNORED by the reader, exactly like
	# the crocodile sync's flag byte — a fifth bit added by a later build must
	# cost an older peer nothing, and `ability_visual_scale()` is total over every
	# value that gets through here.
	var ability: int = 0
	var raw_ability: Variant = state.get("ab", null)
	if raw_ability != null:
		if not _is_number(raw_ability):
			return {}
		var ability_value: float = float(raw_ability)
		if not is_finite(ability_value) or ability_value < 0.0 or ability_value > 255.0:
			return {}
		ability = int(ability_value)

	# `pz` — THE SENDER HAS PAUSED THE ROOM (bead godot-test1-3a2). Same
	# missing-is-not-malformed rule as `ab` and the counters — an older build
	# sends no `pz` and simply never pauses anybody, which is the behaviour it
	# already has — but unlike them there is nothing here to clamp: the field is
	# a BOOL or the packet is malformed, so present-and-not-a-bool drops it
	# whole. `true` is the only value ever sent (the encoder OMITS false), and
	# `false` is accepted anyway because "I have resumed" is a perfectly honest
	# thing for a later build to say explicitly.
	var room_paused: bool = false
	var raw_paused: Variant = state.get("pz", null)
	if raw_paused != null:
		if typeof(raw_paused) != TYPE_BOOL:
			return {}
		room_paused = raw_paused

	return {
		"p": pos, "y": yaw, "c": char_index, "s": speed, "g": state["g"],
		"cc": counters["cc"], "dd": counters["dd"], "ab": ability,
		"pz": room_paused,
	}

# =============================================================================
# CROCODILE SYNC — the fourth trust boundary
# =============================================================================

static func _croc_flags(croc: Node) -> int:
	"""
	Pack one crocodile's coarse behaviour into the state byte.

	Read back through the same CROC_FLAG_* constants in
	`piglet_crocodile_ai.set_remote_state()`, which is why they live in this file
	once — an encoder and a decoder that name their bits separately drift.
	"""
	var flags: int = 0
	if "is_chasing" in croc and croc.is_chasing:
		flags |= CROC_FLAG_CHASING
	if "is_fleeing" in croc and croc.is_fleeing:
		flags |= CROC_FLAG_FLEEING
	if "is_paused" in croc and croc.is_paused:
		flags |= CROC_FLAG_PAUSED
	if "is_biting" in croc and croc.is_biting:
		flags |= CROC_FLAG_BITING
	if "is_burrowed" in croc and croc.is_burrowed:
		flags |= CROC_FLAG_BURROWED
	return flags

static func decode_croc_sync(state: Dictionary) -> Dictionary:
	"""
	The crocodile-sync parser — the FOURTH trust boundary, and built exactly like
	the other three: static and `_rtc`-free so scripts/mp_selfcheck.gd can beat on
	it with hostile input, and whole-or-nothing, returning an EMPTY DICTIONARY for
	anything that fails so the caller drops the packet entire.

	Wire format, the `var_to_bytes` of:

	    {"t": "croc",
	     "i": PackedInt32Array,    # one crocodile id per entry
	     "x": PackedFloat32Array,  # 4 per entry: px, py, pz, yaw
	     "f": PackedByteArray}     # one CROC_FLAG_* state byte per entry

	Three parallel packed arrays rather than an array of Dictionaries because this
	goes out at 10 Hz to every peer: packed arrays serialise as a flat block with
	no per-entry key strings.

	@param state: the already-`bytes_to_var`-decoded packet — NEVER
	    `bytes_to_var_with_objects`, see `_receive_mesh_packets()`.
	@return `{"ids": PackedInt32Array, "xf": PackedFloat32Array,
	    "flags": PackedByteArray}` with every yaw wrapped into `[0, TAU)`, or `{}`.
	"""
	# EXACT packed types, not "some array": a plain Array of the right length
	# would index fine and then hand a String to `global_position`.
	if typeof(state.get("i", null)) != TYPE_PACKED_INT32_ARRAY \
			or typeof(state.get("x", null)) != TYPE_PACKED_FLOAT32_ARRAY \
			or typeof(state.get("f", null)) != TYPE_PACKED_BYTE_ARRAY:
		return {}

	var ids: PackedInt32Array = state["i"]
	var flags: PackedByteArray = state["f"]
	var raw_xf: PackedFloat32Array = state["x"]

	# SIZES FIRST, before anything is copied: the `duplicate()` below is a full
	# allocation, and an oversized hostile packet must not get to pay for one on
	# its way to being rejected. The three arrays describe the SAME entries, so
	# their sizes are not independent — a mismatch is exactly the shape a truncated
	# or hostile packet takes, and walking it would read off the end of one of them
	# per entry.
	if ids.size() != flags.size() or raw_xf.size() != ids.size() * 4:
		return {}
	if ids.size() > MAX_CROC_SYNC:
		return {}

	# Copied because the yaw wrap below writes into it, and a packed array read
	# out of a Dictionary is a reference until it is written to.
	var xf: PackedFloat32Array = raw_xf.duplicate()

	for entry: int in ids.size():
		var base: int = entry * 4
		# FINITENESS BEFORE ANY USE, for the reason `decode_presence()` spells
		# out at length: a crocodile assigned a NaN position interpolates to NaN
		# forever after, with no path back for the room's life, and 1e30 is
		# finite but just as permanent. The coordinate bound is the presence
		# packet's — a croc stands in the same world a player does.
		for axis: int in 3:
			var value: float = xf[base + axis]
			if not is_finite(value) or absf(value) > MAX_PRESENCE_COORD:
				return {}
		var yaw: float = xf[base + 3]
		if not is_finite(yaw):
			return {}
		# WRAPPED, not bounded, exactly as `decode_presence()` wraps `y`: an angle
		# has no natural magnitude limit, but it is eased with `lerp_angle`, which
		# is `from + short_way * weight` — and `1e30 + anything small IS 1e30`.
		xf[base + 3] = fposmod(yaw, TAU)

	# `flags` needs no validation: every one of the 256 byte values is a legal
	# combination of CROC_FLAG_* bits plus unknown bits, and the receiver reads it
	# with `&` so bits it does not know are ignored.
	return {"ids": ids, "xf": xf, "flags": flags}

# =============================================================================
# JOIN SNAPSHOT — the third trust boundary
# =============================================================================

static func decode_state(payload: Dictionary) -> Dictionary:
	"""
	The join-snapshot parser, and the THIRD trust boundary in this file.

	The lobby never inspects a relayed payload — that opacity is what keeps game
	logic off the server — so this is unvalidated peer input, arriving over JSON
	where *every* number is a float. Returns the validated snapshot
	(`{"cc": int, "dd": int, "gc": int, "pos": Vector3,
	"ids": Array[int], "dead": Array[int]}`) or
	an EMPTY DICTIONARY: trusted whole or dropped whole, exactly like
	`decode_presence()`, and static and `_rtc`-free for the same reason — so
	scripts/mp_selfcheck.gd can beat on it with a fistful of hostile payloads.
	"""
	# RETIRED KEYS ARE NOT VALIDATED AND NOT READ. Hearts are gone (bead
	# godot-test1-0bc), so an older peer's `ls` / `gs` are simply absent from every
	# list below: unread, so a hostile value in them can reach nothing, and never
	# required, so that peer's snapshot is still worth its position and its ids.
	for key: String in ["cc", "dd", "px", "py", "pz"]:
		if not _is_number(payload.get(key, null)):
			return {}

	# Finiteness is tested BEFORE every cast, for the reason `decode_presence()`
	# folds `c` into its finite gate: `int(NAN)` is undefined and on wasm the
	# trunc can trap the module, taking the tab down before any range check runs.
	var counters: Array[int] = []
	for key: String in ["cc", "dd"]:
		var raw: float = float(payload[key])
		if not is_finite(raw) or raw < 0.0 or raw > float(MAX_STATE_COUNTER):
			return {}
		counters.append(int(raw))

	# The departed-members bank. MISSING IS NOT MALFORMED — the same rule
	# `decode_presence()` applies to its counters: a peer on an older build sends
	# no `gc`, and dropping its whole snapshot would cost the joiner a position
	# and an id list over one optional field. Present-but-bad still drops the
	# payload, like every other field here.
	if not payload.has("gc"):
		counters.append(0)
	else:
		var gone: float = float(payload["gc"]) if _is_number(payload["gc"]) else NAN
		if not is_finite(gone) or gone < 0.0 or gone > float(MAX_STATE_COUNTER):
			return {}
		counters.append(int(gone))

	var pos: Vector3 = Vector3(
		float(payload["px"]), float(payload["py"]), float(payload["pz"])
	)
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
		return {}
	# Same bound as a presence position, and for the same reason: this feeds the
	# join placement, and an absurd-but-finite anchor would teleport the joiner
	# somewhere the terrain will never build.
	if absf(pos.x) > MAX_PRESENCE_COORD or absf(pos.y) > MAX_PRESENCE_COORD \
			or absf(pos.z) > MAX_PRESENCE_COORD:
		return {}

	if typeof(payload.get("ids", null)) != TYPE_ARRAY:
		return {}
	var ids: Variant = _decode_id_list(payload["ids"])
	if ids == null:
		return {}

	# The kill list. MISSING IS NOT MALFORMED, the rule `gc`/`gs` above follow and
	# for the same reason: a peer on a build without this field is still worth its
	# position, its counters and its coin ids. Present-but-not-an-array, or one bad
	# entry, still drops the whole snapshot.
	var dead: Variant = []
	if payload.has("dead"):
		if typeof(payload["dead"]) != TYPE_ARRAY:
			return {}
		dead = _decode_id_list(payload["dead"])
		if dead == null:
			return {}

	# The captive set. MISSING IS NOT MALFORMED, the rule `gc`/`gs`/`dead` follow:
	# a peer on a build without this field is still worth its position, its
	# counters and its id lists. Present-but-not-an-array, an over-long list or one
	# bad entry all drop the whole snapshot - and an over-long list is REJECTED
	# rather than truncated, unlike the id lists, because there is no honest reason
	# for a second entry at all (a peer holds one hero) and no "the head is the
	# part nearest the joiner" ordering to salvage.
	var captives: Array[String] = []
	if payload.has("cap"):
		if typeof(payload["cap"]) != TYPE_ARRAY:
			return {}
		var raw_caps: Array = payload["cap"] as Array
		if raw_caps.size() > MAX_STATE_CAPTIVES:
			return {}
		for entry: Variant in raw_caps:
			if typeof(entry) != TYPE_STRING:
				return {}
			var hero: String = String(entry)
			if hero.is_empty() or hero.length() > MAX_HERO_NAME:
				return {}
			captives.append(hero)

	# Budapest's explored mask. MISSING IS NOT MALFORMED, the `gc`/`dead`/`cap`
	# rule: a peer on a pre-.5 build is still worth its position, its counters and
	# its id lists. Finite and bounded before the cast, then folded down to the
	# slots this build knows — see `decode_room()`, which does the same thing to
	# the same number for the same reasons.
	var explored: int = 0
	if payload.has("lm"):
		if not _is_number(payload["lm"]):
			return {}
		var raw_mask: float = float(payload["lm"])
		if not is_finite(raw_mask) or raw_mask < 0.0 or raw_mask > float(MAX_STATE_COUNTER):
			return {}
		explored = int(raw_mask) & ((1 << BudapestPlan.SLOTS.size()) - 1)

	return {
		"cc": counters[0],
		"dd": counters[1],
		"gc": counters[2],
		"pos": pos,
		"ids": ids,
		"dead": dead,
		"cap": captives,
		"lm": explored,
	}


static func _decode_id_list(raw: Array) -> Variant:
	"""
	Validate one snapshot id array — the coin ids or the crocodile kill list, which
	are the same kind of thing over the same wire and so get one validator rather
	than two that can drift.

	Returns `Array[int]`, or `null` meaning "drop the whole snapshot".

	An over-long list is TRUNCATED, not rejected — the one place this parser keeps
	part of a payload. The sender orders both lists most-recent-first, so the head
	is the part nearest the joiner, and a snapshot whose list is too long is still
	worth its position and its counters, which are what the join placement and the
	shared bank actually need. A malformed *entry* is a different thing and still
	drops the whole snapshot.
	"""
	var ids: Array[int] = []
	for i: int in range(mini(raw.size(), MAX_STATE_IDS)):
		var entry: Variant = raw[i]
		if not _is_number(entry):
			return null
		var value: float = float(entry)
		if not is_finite(value) or absf(value) > MAX_STATE_ID_MAGNITUDE:
			return null
		ids.append(int(value))
	return ids

# =============================================================================
# CAPTIVES — the fifth and sixth trust boundaries
# =============================================================================

static func decode_room(packet: Dictionary) -> Dictionary:
	"""
	The `room` parser — the SIXTH trust boundary in this file.

	@return: `{"cap": Array[String], "cd": float, "co": int}`, or an EMPTY
	    DICTIONARY. Trusted whole or dropped whole, static and `_rtc`-free, exactly
	    like the four parsers above it.

	`cap` is bounded and every entry length-gated here, then whitelisted against
	`_pool` in `_receive_room`. `cd` and `co` ARE RETIRED VALUES AND A LIVE SHAPE
	(owner veto 2026-09-01, bead `godot-test1-ueg`): this build publishes zeros and
	reads neither, but an older master publishes a real recall clock and verdict and
	the packet is also the captive-set repair channel, so both are still validated
	exactly as before — finiteness before any cast (`int(NAN)` is undefined and on
	wasm the trunc can trap the module) and the enum folded rather than dropped —
	and a malformed one still costs the whole packet.
	"""
	if typeof(packet.get("cap", null)) != TYPE_ARRAY:
		return {}
	var raw: Array = packet["cap"] as Array
	if raw.size() > MAX_STATE_CAPTIVES:
		return {}
	var names: Array[String] = []
	for entry: Variant in raw:
		if typeof(entry) != TYPE_STRING:
			return {}
		var hero: String = String(entry)
		if hero.is_empty() or hero.length() > MAX_HERO_NAME:
			return {}
		names.append(hero)
	if not _is_number(packet.get("cd", null)):
		return {}
	var seconds: float = float(packet["cd"])
	if not is_finite(seconds) or seconds < 0.0 or seconds > MAX_CUSTODY_SECONDS:
		return {}
	if not _is_number(packet.get("co", null)):
		return {}
	var verdict: float = float(packet["co"])
	if not is_finite(verdict) or verdict < 0.0 or verdict > float(MAX_STATE_COUNTER):
		return {}
	# A VERDICT THIS BUILD CANNOT READ COSTS THE VERDICT, NOT THE PACKET, which is
	# why the gate above is only a sanity bound and the enum is folded here instead.
	# This build has two outcomes; a master still on the pre-`godot-test1-0bc` build
	# publishes a third (OVERTAKEN, `co: 3`), and `build_version` deliberately
	# refuses to reload a peer that is mid-run or in a room, so a mixed room is a
	# state that really happens and lasts. Bounding at 2 instead would drop such a
	# packet WHOLE — and this packet is also the captive-set repair channel, the one
	# thing that closes the join gap `cap` cannot reach, so the room's cells would
	# stop converging over a field we do not even use.
	#
	# IT FOLDS UP AND NEVER DOWN, which is now a shape kept honest rather than a
	# behaviour: nothing reads `co`, and the fold is what stops an unknown value
	# costing the captive set it travels with.
	var known: int = int(verdict)
	if known > CUSTODY_VERDICT_MAX:
		known = CUSTODY_VERDICT_MAX

	# BUDAPEST'S EXPLORED MASK. MISSING IS NOT MALFORMED, the `dead` / `gc` rule
	# and the exact opposite of `cd` / `co` above: a master on a pre-.5 build
	# publishes no `m` at all, and `build_version` refuses to reload a peer that is
	# in a room, so that master is a state that really happens. Dropping its packet
	# over an absent field would stop the room repairing its CELLS — the thing this
	# verb has always been for — over a field that build has never heard of.
	# Present-but-malformed still costs the whole packet, like every other field.
	#
	# Finite and bounded BEFORE the cast, and the bound is the plan's own size: a
	# mask is folded down to the slots that exist rather than dropped, because a
	# LARGER one is what a peer on a build with a twenty-third landmark would send
	# and its first 22 bits are still true. `player_controller.adopt_explored_mask`
	# masks again on its own side — the same belt-and-braces `_pool` gives `cap`.
	var explored: int = 0
	if packet.has("m"):
		if not _is_number(packet.get("m", null)):
			return {}
		var raw_mask: float = float(packet["m"])
		if not is_finite(raw_mask) or raw_mask < 0.0 or raw_mask > float(MAX_STATE_COUNTER):
			return {}
		explored = int(raw_mask) & ((1 << BudapestPlan.SLOTS.size()) - 1)

	return {"cap": names, "cd": seconds, "co": known, "m": explored}

static func decode_captive(packet: Dictionary) -> Dictionary:
	"""
	The `cap` parser, and the FIFTH trust boundary in this file.

	@return: `{"h": String, "c": bool}`, or an EMPTY DICTIONARY - trusted whole or
	    dropped whole, exactly like `decode_presence()` and `decode_state()`, and
	    static and `_rtc`-free for the same reason: so scripts/mp_selfcheck.gd can
	    beat on it with a fistful of hostile packets.

	The hero name is length-gated here and WHITELISTED against the lobby's `_pool`
	in `_receive_captive`, which is instance state this static cannot see. Both
	halves are needed: the length gate keeps a megabyte string out of the
	dictionary key space, the whitelist is what makes the name mean something.
	"""
	var hero: Variant = packet.get("h", null)
	if typeof(hero) != TYPE_STRING:
		return {}
	var name: String = String(hero)
	if name.is_empty() or name.length() > MAX_HERO_NAME:
		return {}
	# STRICTLY A BOOL, not a truthy number: `var_to_bytes` round-trips real types
	# over the mesh, so a `c` that is not a bool is a peer that is not speaking
	# this protocol and the safe reading of it is none at all.
	if typeof(packet.get("c", null)) != TYPE_BOOL:
		return {}
	return {"h": name, "c": bool(packet["c"])}

# =============================================================================
# LURE PLATES — the `pad` verb
# =============================================================================

static func decode_pad(packet: Dictionary) -> Dictionary:
	"""
	The `pad` parser, and the SIXTH trust boundary in this file.

	@return: `{"f": int, "p": int}`, or an EMPTY DICTIONARY — trusted whole or
	    dropped whole, static and instance-free so scripts/mp_selfcheck.gd can beat
	    on it, exactly like `decode_captive()`.

	STRICTLY INTS. `var_to_bytes` round-trips real types over the mesh, so a float
	or a numeric string in either field is a peer that is not speaking this
	protocol. Bounds are NOT this function's business beyond "not negative": which
	pairs exist is a question about the authored plans, and `_receive_pad()` asks
	the building rather than trusting a number written down twice.
	"""
	if typeof(packet.get("f", null)) != TYPE_INT or typeof(packet.get("p", null)) != TYPE_INT:
		return {}
	var floor_index: int = int(packet["f"])
	var pad_index: int = int(packet["p"])
	if floor_index < 0 or pad_index < 0:
		return {}
	return {"f": floor_index, "p": pad_index}


static func pad_press_in_reach(sender: Vector3, pad: Vector3) -> bool:
	"""
	Could a peer standing at `sender` have stepped on the plate at `pad`?

	Static and pure so the self-check can drive it, and finiteness-checked before
	anything is derived from either point — `pad_world()` answers `Vector3.INF` for
	a plate no plan draws, which has to read as "no" and not as "infinitely far,
	therefore compare it anyway".
	"""
	if not sender.is_finite() or not pad.is_finite():
		return false
	return sender.distance_to(pad) <= MAX_PAD_PRESS_DISTANCE

# =============================================================================
# LANDMARK CLAIMS — the `lmk` verb
# =============================================================================

static func decode_lmk(packet: Dictionary) -> Dictionary:
	"""
	The `lmk` parser, and the SEVENTH trust boundary in this file.

	@return: `{"i": int}`, or an EMPTY DICTIONARY — trusted whole or dropped
	    whole, static and instance-free so scripts/landmark_progress_selfcheck.gd
	    can beat on it, exactly like `decode_pad()`.

	`_is_number` AND NOT `TYPE_INT`, unlike `decode_pad`, and the difference is the
	transport: this verb also travels the LOBBY RELAY (see
	`report_landmark_explored`), where `JSON.parse_string` hands every number back
	as a FLOAT — the same gotcha `_receive_seed` documents. So the value is checked
	FINITE AND IN RANGE BEFORE ANY CAST (`int(NAN)` is undefined and on wasm the
	trunc can trap the module), and a fractional one is refused afterwards: 3.5 is
	not a slot, it is a peer that is not speaking this protocol.

	THE RANGE IS CHECKED HERE rather than left to the caller, because unlike a
	plate index it bounds a SHIFT — `1 << i` for a large `i` is how a claim becomes
	an overflow instead of a refusal.
	"""
	if not _is_number(packet.get("i", null)):
		return {}
	var raw: float = float(packet["i"])
	if not is_finite(raw) or raw < 0.0 or raw >= float(BudapestPlan.SLOTS.size()):
		return {}
	var index: int = int(raw)
	if float(index) != raw:
		return {}
	return {"i": index}


static func landmark_claim_in_reach(sender: Vector3, slot: Vector3, radius: float) -> bool:
	"""
	Could a peer standing at `sender` have walked into the landmark at `slot`?

	Static and pure so the self-check can drive it, and finiteness-checked before
	anything is derived from either point — the `pad_press_in_reach` rule, for the
	same reason: a non-finite input has to read as "no", never as "infinitely far,
	compare it anyway".

	FLAT XZ, like `landmark_toast._xz_distance`: three of the 22 slots stand on a
	plateau lid 30-46 m up, and a Y-aware distance would refuse the claim of
	somebody standing right on top of Buda Castle.
	"""
	if not sender.is_finite() or not slot.is_finite():
		return false
	if not is_finite(radius) or radius < 0.0:
		return false
	var flat := Vector2(sender.x - slot.x, sender.z - slot.z)
	return flat.length() <= radius + MAX_LANDMARK_CLAIM_PAD
