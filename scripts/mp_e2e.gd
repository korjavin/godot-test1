extends SceneTree
## The automated two-instance check for the multiplayer RELAY path. One process
## is one peer; `scripts/mp_e2e.sh` runs two of them against a locally started
## lobby and compares what they print.
##
##     godot --headless --path . --script res://scripts/mp_e2e.gd -- \
##         --lobby=ws://127.0.0.1:8080 --lobby-only --role=host --hold=20
##     godot --headless --path . --script res://scripts/mp_e2e.gd -- \
##         --lobby=ws://127.0.0.1:8080 --lobby-only --role=join --code=ABC123
##
## It prints, on their own lines:
##
##     E2E_ROOM=<6-character invite code>
##     E2E_YOU=<our own 16-hex lobby id>
##     E2E_MASTER=<the master's lobby id>
##     E2E_SEED=<endless_terrain.run_seed>
##
## and quits 0, or prints `E2E_TIMEOUT` and quits 1. The harness compares the two
## seeds — they must be equal, because that is the whole promise of a room.
##
## Phase 5 adds the STALL → RE-ELECTION half, which is the one part of master
## migration a headless run can reach (`--lobby-only` has no mesh, and the
## heartbeat rides the relay precisely so it works without one):
##
##     --stall         (host) stop heartbeating once the room exists
##     --await-master  (join) wait until WE are the master, then print
##                     E2E_NEWMASTER=<our id>
##
## ⚠️ A STALLED HOST MUST KEEP ITS SOCKET OPEN. `--stall` only silences the
## heartbeat — it is the simulated throttled tab, where the TCP connection is
## alive and the room is intact but nothing is being sent. If the host process
## exited instead, the lobby's ORDINARY disconnect re-election would fire and the
## joiner would become master without a single vote being cast, so the test would
## pass while proving nothing about stall detection. The host therefore still
## `--hold`s, sized to outlive the vote. Same family of trap as the fixed-code
## one below: a green run for the wrong reason.
##
## ⚠️ THE HOST MUST USE `host()`, NOT A FIXED SHARED CODE. `MpManager`'s typo
## guard drops a peer that asked for a code and came out alone AND master, since
## that is exactly what one wrong character in an invite code looks like (the
## lobby mints any well-formed code it does not know). A fixed code like
## "FIXED1" is indistinguishable from that typo to the FIRST instance, so it
## would leave the room immediately and the test would fail for the wrong
## reason. The host therefore lets the lobby mint a room and PRINTS the code;
## the harness scrapes it and hands it to the joiner. Do not "simplify" this
## back to a hardcoded code.
##
## A THIRD ROLE, `--role=drag`, needs no lobby and no second process. It is the
## regression check for bead godot-test1-s86.17 — "players get dragged toward each
## other during normal play" — and it drives `MpManager`'s lobby handlers directly
## rather than over a socket, because the bug is about WHEN a packet arrives and a
## two-process run cannot schedule "late" reliably (measured: the joiner had
## already been placed before the harness could throttle anything). See
## `_run_drag_check()`.
##
## A FOURTH ROLE, `--role=respawn`, is the same shape again and covers bead
## godot-test1-s86.18 — a death respawn inside a room puts the player back with
## the group, while a solo one still leaves them exactly where they fell. Both
## halves run in the one process, the solo negative control first. See
## `_run_respawn_check()`.
##
## ponytail: this covers the LOBBY RELAY — the room, the seed broadcast and its
## adoption, i.e. the path that broke in production (see Task 9a). It covers
## neither the WebRTC mesh nor the avatars, because desktop headless has no
## `webrtc-native` addon; those still need two real browsers. Upgrade path: once
## the addon is vendored (bead godot-test1-s86.8), drop `--lobby-only` and
## additionally assert that each instance sees one remote avatar.

## Wall-clock budget for the whole run, per instance. Generous on purpose: a
## cold `godot --headless` spends seconds importing before the first frame, and
## a timeout here is reported as a FAILURE, so it must never fire on a slow
## machine that would otherwise have passed.
const TIMEOUT_SEC: float = 60.0

## Extra budget granted to `--await-master` when it starts waiting. The vote is
## paced by the manager's own constants (`HEARTBEAT_TIMEOUT` 4 s of silence, then
## a vote every `STALL_REPORT_INTERVAL` 2 s), so the wait itself is ~6 s — but it
## begins AFTER the boot the 60 s budget was sized for, and a deadline already
## half spent on importing would report a working migration as a timeout.
const MASTER_WAIT_SEC: float = 30.0

## How long the host lingers after printing its code, so the joiner has a room
## to join. Overridden with `--hold=<seconds>`; the harness sizes it to its own
## joiner timeout.
const DEFAULT_HOLD_SEC: float = 20.0

## `--role=drag` fixtures. The two ids are the lobby's shape — 16 lowercase hex
## characters — because `peer_int_id()` slices the first seven of them.
const DRAG_MASTER_ID: String = "aaaaaaaaaaaaaaaa"
const DRAG_ME_ID: String = "bbbbbbbbbbbbbbbb"
## Far enough from spawn that either teleport the bug produced (the world origin,
## or the group's ring around it) is an unmissable failure rather than a nudge.
const DRAG_AWAY := Vector3(400.0, 2.0, 0.0)
## Slack for the physics settle of a body parked in mid-air. The failures this
## guards against are hundreds of metres, so this is nowhere near a knife edge.
const DRAG_TOLERANCE: float = 3.0
const DRAG_SEED: int = 123456

## `--role=respawn` fixtures (bead godot-test1-s86.18). Same single-instance,
## no-socket shape as `--role=drag` above, and for a related reason: the thing
## under test is a LOCAL event (`_respawn_in_place()`), so a second process would
## add a scheduler to the test without adding anything to the assertion.
const RESPAWN_MASTER_ID: String = "cccccccccccccccc"
const RESPAWN_ME_ID: String = "dddddddddddddddd"
const RESPAWN_SEED: int = 654321
## Where the "group" (one master peer) is standing. Far enough from the spawn
## that landing beside it cannot be confused with not having moved.
const RESPAWN_GROUP := Vector3(600.0, 2.0, 0.0)
## Where this peer has walked off to and dies. The origin, i.e. 600 m of
## unmissable gap from the group.
const RESPAWN_AWAY := Vector3(0.0, 2.0, 0.0)
## Where the NEGATIVE CONTROL dies, with no room at all. Nowhere near either of
## the two above, so "did not move" is a real measurement and not the origin
## being the answer to everything.
const RESPAWN_SOLO_SPOT := Vector3(120.0, 2.0, -40.0)
## A solo respawn keeps the player EXACTLY where it fell, so this is slack for
## the physics settle of a body parked in mid-air, nothing more.
const RESPAWN_SOLO_TOLERANCE: float = 1.0
## How close to the anchor counts as "with the group": the widest ring
## `player_controller.JOIN_RING_RADII` probes (12 m) plus slack.
const RESPAWN_NEAR_MAX: float = 16.0

var _role: String = ""
var _code: String = ""
var _hold: float = DEFAULT_HOLD_SEC
var _stall: bool = false
var _await_master: bool = false
var _deadline_msec: int = 0


func _initialize() -> void:
	_deadline_msec = Time.get_ticks_msec() + int(TIMEOUT_SEC * 1000.0)
	_read_args()
	if _role == "drag":
		_run_drag_check.call_deferred()
		return
	if _role == "respawn":
		_run_respawn_check.call_deferred()
		return
	if _role != "host" and _role != "join":
		printerr("E2E: --role=host, --role=join, --role=drag or --role=respawn is required")
		quit(1)
		return
	if _role == "join" and _code.is_empty():
		printerr("E2E: --role=join needs --code=XXXXXX")
		quit(1)
		return
	# The scene change is deferred to the first idle frame, so the run itself is
	# a coroutine started from here and driven by `await process_frame` — the
	# same polling shape as a `while` loop, without a `_process` override that
	# would have to remember to chain to SceneTree's own.
	_run.call_deferred()


func _read_args() -> void:
	"""Everything after the bare `--`, same convention as `--lobby=` itself."""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.substr("--role=".length())
		elif arg.begins_with("--code="):
			_code = arg.substr("--code=".length()).to_upper()
		elif arg.begins_with("--hold="):
			_hold = maxf(0.0, arg.substr("--hold=".length()).to_float())
		elif arg == "--stall":
			_stall = true
		elif arg == "--await-master":
			_await_master = true


func _run() -> void:
	"""Boot the game scene, join a room over the relay, report, quit."""
	change_scene_to_file("res://scenes/main.tscn")

	var mp: Node = await _await_group("mp")
	var terrain: Node = await _await_group("terrain")
	if mp == null or terrain == null:
		_fail("scene has no \"mp\" / \"terrain\" node")
		return

	# `lobby_only` is normally set from the command line in `_init()`; set it
	# again here so this script works even if the flag is dropped from the
	# invocation. Without it `join()` refuses outright on a desktop with no
	# WebRTC addon, which is every headless machine.
	mp.lobby_only = true
	mp.display_name = "e2e-" + _role

	if _role == "host":
		mp.host()
	else:
		mp.join(_code)

	# Both roles need a room; only the joiner waits for a seed to arrive, since
	# the host's seed IS the room's (it publishes its own terrain's).
	if not await _await_until(func() -> bool: return not mp.get_room_code().is_empty()):
		_fail("no room")
		return
	if _role == "join":
		if not await _await_until(func() -> bool: return mp.room_seed() != null):
			_fail("seed never arrived")
			return

	# The throttled tab: beats stop, socket stays. See the header warning.
	if _stall:
		mp.heartbeat_enabled = false

	print("E2E_ROOM=%s" % mp.get_room_code())
	print("E2E_YOU=%s" % mp.my_id())
	print("E2E_MASTER=%s" % mp.get_master())
	# The TERRAIN's seed, not the manager's: the point of the test is that the
	# ground was actually regenerated from the room's seed, not merely that a
	# number was received and stored.
	#
	# TYPE-CHECKED, because `Object.get()` on a property that does not exist
	# answers `null` and `int(null)` is 0 — so a renamed or getter-wrapped
	# `run_seed` would make BOTH instances print `E2E_SEED=0`, the harness's
	# equality test hold, and the one assertion this whole script exists for pass
	# while proving nothing.
	var seed_value: Variant = terrain.get("run_seed")
	if typeof(seed_value) != TYPE_INT:
		_fail("terrain exposes no int run_seed — the seed comparison would be vacuous")
		return
	print("E2E_SEED=%d" % (seed_value as int))

	if _await_master:
		_deadline_msec = maxi(
			_deadline_msec, Time.get_ticks_msec() + int(MASTER_WAIT_SEC * 1000.0)
		)
		if not await _await_until(func() -> bool: return mp.get_master() == mp.my_id()):
			_fail("never became master — the stalled host was not deposed")
			return
		print("E2E_NEWMASTER=%s" % mp.my_id())

	if _role == "host":
		await _hold_open()
	mp.leave()
	quit(0)


func _run_drag_check() -> void:
	"""
	REGRESSION CHECK (bead godot-test1-s86.17): nothing on the wire may move the
	local player once it is alive and playing.

	The bug: `_can_join_place()` is a pure STATE test — "we still owe a placement
	and both inputs are in hand" — and `JOIN_SNAPSHOT_WAIT` never disarmed it, it
	only stopped the waiting. So a peer whose master was silent for the first few
	seconds (a backgrounded tab, a `seed_req` retry, a master migration handing the
	retry budget back) kept the placement armed indefinitely, and the packets it
	was owed at ARRIVAL fired it minutes later: the late `seed` teleported it to
	the world origin through `reset_position()` — wiping the run's coins, distance
	and streak — and the late `state` snapshot then pulled it onto the group's
	ring. Measured before the fix: 397 m of drag, twice, at 400 m from spawn.

	Driven through `_on_lobby_joined` / `_on_lobby_relay` directly, with no socket:
	the assertion is about arrival TIMING, and two real processes cannot schedule
	"late" — the joiner is placed within one relay round trip, long before a
	harness can throttle anything. `_ensure_lobby()` gives the manager a
	LobbyClient that was never connected, so its outbound frames drop silently
	(`LobbyClient._send` bails on a closed socket) instead of erroring on a null.

	⚠️ THE SEED-ADOPTION ASSERTION IS WHAT STOPS THIS PASSING VACUOUSLY. "The
	player did not move" is also true if the packets were dropped outright, or if
	the manager never entered the room at all — so the run seed the terrain ends up
	on must equal the one the late packet carried. Same trap, and same guard, as
	the `E2E_SEED` type-check above.
	"""
	change_scene_to_file("res://scenes/main.tscn")
	var mp: Node = await _await_group("mp")
	var terrain: Node = await _await_group("terrain")
	var player: Node3D = await _await_group("player") as Node3D
	if mp == null or terrain == null or player == null:
		_fail("scene has no \"mp\" / \"terrain\" / \"player\" node")
		return
	mp.lobby_only = true
	mp._ensure_lobby()

	# Arrive into a room that already holds somebody, so a placement really is owed
	# (a host is `_first_member` and is never placed).
	mp._on_lobby_joined(DRAG_ME_ID, "DRAG01", DRAG_MASTER_ID, [
		{"id": DRAG_MASTER_ID, "name": "host"}, {"id": DRAG_ME_ID, "name": "me"},
	])
	if mp.get_room_code() != "DRAG01":
		_fail("drag: the manager did not enter the room")
		return

	# The master says nothing at all, so the snapshot deadline burns down and the
	# placement finds neither of its two inputs.
	await _sleep(MpManager.JOIN_SNAPSHOT_WAIT + 1.0)

	# NORMAL PLAY: walk away from the group. The StartOverlay holds the tree paused
	# in a headless boot, so one teleport stands in for walking — and that is what
	# makes the assertion sharp, because nothing else can move the player.
	player.global_position = DRAG_AWAY
	await _sleep(MpManager.JOIN_PLACE_WINDOW)

	# The packets this peer was owed at arrival finally land.
	mp._on_lobby_relay(DRAG_MASTER_ID, {"mp": "seed", "seed": DRAG_SEED})
	await _sleep(0.5)
	var after_seed: Vector3 = player.global_position
	mp._on_lobby_relay(DRAG_MASTER_ID, {
		"mp": "state", "cc": 0, "ls": 0, "dd": 0,
		"px": 0.0, "py": 2.0, "pz": 0.0, "gc": 0, "gs": 0, "ids": [],
	})
	await _sleep(1.0)
	var after_snapshot: Vector3 = player.global_position

	if after_seed.distance_to(DRAG_AWAY) > DRAG_TOLERANCE:
		_fail("drag: a late seed moved the player %.1f m (to %s)"
			% [after_seed.distance_to(DRAG_AWAY), after_seed])
		return
	if after_snapshot.distance_to(DRAG_AWAY) > DRAG_TOLERANCE:
		_fail("drag: a late join snapshot moved the player %.1f m (to %s)"
			% [after_snapshot.distance_to(DRAG_AWAY), after_snapshot])
		return

	# ...and the packets were genuinely acted on, so the check is not vacuous.
	var seed_value: Variant = terrain.get("run_seed")
	if typeof(seed_value) != TYPE_INT or int(seed_value) != DRAG_SEED:
		_fail("drag: the late seed was never adopted (run_seed=%s) — the "
			% str(seed_value) + "no-movement assertion would be vacuous")
		return

	print("E2E_NODRAG=%d" % DRAG_SEED)
	quit(0)


func _run_respawn_check() -> void:
	"""
	BEAD godot-test1-s86.18: in a room, a death respawn puts the player back with
	the group; solo it still leaves them exactly where they fell.

	The NEGATIVE CONTROL runs FIRST, out of a room, and is the half that keeps
	this honest: "landed near the group" is also true of a `_respawn_in_place()`
	that teleports unconditionally, and the whole promise of the change is that
	single-player is untouched. So the same call is made twice — once with no
	room, where the player must not move by so much as a metre, and once in a
	room 600 m from the group, where it must end up inside the join ring.

	Single instance and no socket, exactly like `_run_drag_check()` above: the
	trigger under test is a LOCAL event (`_on_caught_finished()` → this), so a
	second process would add scheduling to the test without adding anything to
	the assertion. The room is entered by driving `_on_lobby_joined()` /
	`_on_lobby_relay()` directly, with a never-connected `LobbyClient` whose
	outbound frames drop silently.

	⚠️ AND IT ASSERTS THE ANCHOR THE MANAGER ACTUALLY OFFERED, not only where the
	body ended up — the same anti-vacuity rule the drag check's seed-adoption
	assertion follows. Without it a run in which the manager never entered the
	room would report `group_anchor() == null`, take the solo path, and the
	"moved to the group" test would be the only thing standing between a silent
	no-op and a green tick.
	"""
	change_scene_to_file("res://scenes/main.tscn")
	var mp: Node = await _await_group("mp")
	var player: Node3D = await _await_group("player") as Node3D
	if mp == null or player == null:
		_fail("scene has no \"mp\" / \"player\" node")
		return

	# --- NEGATIVE CONTROL: solo, so nothing may move -------------------------
	player.global_position = RESPAWN_SOLO_SPOT
	if mp.group_anchor() != null:
		_fail("respawn: group_anchor() is not null while OFFLINE — the solo path is gone")
		return
	player._respawn_in_place()
	await _sleep(0.5)
	var solo_drift: float = player.global_position.distance_to(RESPAWN_SOLO_SPOT)
	if solo_drift > RESPAWN_SOLO_TOLERANCE:
		_fail("respawn: a SOLO respawn moved the player %.1f m (to %s) — it must stay put"
			% [solo_drift, player.global_position])
		return
	# The grace window the control just started would otherwise still be running
	# under the room half (the headless boot is paused, so nothing ticks it down).
	player.is_respawning = false
	player.respawn_timer = 0.0

	# --- IN A ROOM: come back with the group ---------------------------------
	mp.lobby_only = true
	mp._ensure_lobby()
	mp._on_lobby_joined(RESPAWN_ME_ID, "RSPN01", RESPAWN_MASTER_ID, [
		{"id": RESPAWN_MASTER_ID, "name": "host"}, {"id": RESPAWN_ME_ID, "name": "me"},
	])
	if mp.get_room_code() != "RSPN01":
		_fail("respawn: the manager did not enter the room")
		return
	mp._on_lobby_relay(RESPAWN_MASTER_ID, {"mp": "seed", "seed": RESPAWN_SEED})
	mp._on_lobby_relay(RESPAWN_MASTER_ID, {
		"mp": "state", "cc": 0, "ls": 0, "dd": 0,
		"px": RESPAWN_GROUP.x, "py": RESPAWN_GROUP.y, "pz": RESPAWN_GROUP.z,
		"gc": 0, "gs": 0, "ids": [],
	})
	# The join placement itself awaits a physics frame before it moves anybody.
	await _sleep(1.0)

	var anchor: Variant = mp.group_anchor()
	if typeof(anchor) != TYPE_VECTOR3 or (anchor as Vector3).distance_to(RESPAWN_GROUP) > 0.5:
		_fail("respawn: group_anchor() answered %s, not the group at %s — the "
			% [str(anchor), str(RESPAWN_GROUP)] + "placement test would be vacuous")
		return

	# Walk away from the group and die there. One teleport stands in for walking:
	# the StartOverlay holds a headless boot paused, which is also what makes the
	# assertion sharp — nothing but the respawn can move the player.
	player.global_position = RESPAWN_AWAY
	var origin_before: Vector2 = player.own_distance_origin
	player._respawn_in_place()
	await _sleep(0.5)

	var landed: Vector3 = player.global_position
	var from_group: float = landed.distance_to(RESPAWN_GROUP)
	if from_group > RESPAWN_NEAR_MAX:
		_fail("respawn: died at %s in a room and came back %.1f m from the group (at %s)"
			% [str(RESPAWN_AWAY), from_group, str(landed)])
		return

	# ...and the teleport was not banked as distance RUN, or dying beside a team
	# kilometres down the road writes THEIR distance into this player's personal
	# best (see player_controller.own_distance_origin).
	var expected_origin: Vector2 = origin_before \
		+ Vector2(landed.x, landed.z) - Vector2(RESPAWN_AWAY.x, RESPAWN_AWAY.z)
	if player.own_distance_origin.distance_to(expected_origin) > 0.5:
		_fail("respawn: own_distance_origin is %s, expected %s — the regroup teleport "
			% [str(player.own_distance_origin), str(expected_origin)]
			+ "would inflate the personal distance record")
		return

	print("E2E_REGROUP=%d" % int(from_group))
	quit(0)


func _sleep(sec: float) -> void:
	var until_msec: int = Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until_msec:
		await process_frame


func _await_group(group: String) -> Node:
	"""The scene change is deferred, so the nodes appear a frame or two later."""
	var node: Node = null
	while node == null and Time.get_ticks_msec() < _deadline_msec:
		await process_frame
		node = get_first_node_in_group(group)
	return node


func _await_until(condition: Callable) -> bool:
	"""Poll `condition` once a frame until true or the wall clock runs out."""
	while Time.get_ticks_msec() < _deadline_msec:
		if condition.call():
			return true
		await process_frame
	return false


func _hold_open() -> void:
	"""Keep the host's socket alive so the joiner has somebody to join."""
	var until_msec: int = Time.get_ticks_msec() + int(_hold * 1000.0)
	while Time.get_ticks_msec() < until_msec:
		await process_frame


func _fail(reason: String) -> void:
	printerr("E2E: " + reason)
	print("E2E_TIMEOUT")
	quit(1)
