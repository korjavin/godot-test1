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

var _role: String = ""
var _code: String = ""
var _hold: float = DEFAULT_HOLD_SEC
var _stall: bool = false
var _await_master: bool = false
var _deadline_msec: int = 0


func _initialize() -> void:
	_deadline_msec = Time.get_ticks_msec() + int(TIMEOUT_SEC * 1000.0)
	_read_args()
	if _role != "host" and _role != "join":
		printerr("E2E: --role=host or --role=join is required")
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
	print("E2E_SEED=%d" % int(terrain.get("run_seed")))

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
