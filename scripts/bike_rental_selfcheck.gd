extends SceneTree
## bike_rental_selfcheck — THE RENTAL (bead godot-test1-z2yv.7, owner rulings
## 2026-09-20): mount at a `bike_stand` rack for 2 coins, BIKE_SPEED 14 flat,
## a ~5 km DISTANCE budget, the dismount edges, hero switch KEEPS the bike, the
## `Bike` glb child, bit 5 in `ability_visual_state()`.
##
## Driven against the LIVE world (main.tscn: player, terrain, clock) because
## every claim is about what the shipped `try_mount_bike()` / `_physics_process`
## / `set_active_character` do to a real run — a stub player would re-implement
## the routing this check exists to pin. The lattice seat itself lives in
## `enemy_spawn_selfcheck` (BIKE_SPEED > slowest run, BIKE_SPEED > every burst
## peak, read never restated); here the speed branch is only asked to ignore
## gait_mult and wading.
##
## THE WALK STAYS HOME: the 100 m ride is walked as chords of a 10 m circle
## around spawn, so the body never leaves the spawn's predator-free bubble —
## a bite mid-ride would dismount through the shipped tax edge and fail the
## budget number for no reason. Chords are measured back off the body (position
## delta per frame, the same quantity the budget decrements), and the total is
## asserted >= 99 m, so a walk that went nowhere cannot pass.
##
## Every acceptance line carries its mutations (brief rule 3): M-free (no
## charge), M-cheap (cost 1), M-mute (no toast), M-generous (mount anyway),
## M-anywhere (reach 1e9), M-mult (speed takes gait_mult), M-timer (budget by
## delta), M-immortal (budget never ends), M-switch (switch clears), M-sticky
## (reset skips the bike), M-jump (jump still jumps), M-refill (switch refills).

const PlayerScript: GDScript = preload("res://scripts/player_controller.gd")

## The raw-panel-key registry, borrowed rather than copied — `debug_teleport_selfcheck`'s idiom.
const CityMapSelfcheck: GDScript = preload("res://scripts/city_map_selfcheck.gd")

const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")

var _failures: Array[String] = []


class ToastStub extends Node:
	var calls: Array = []
	func announce(title: String, body: String) -> bool:
		calls.append([title, body])
		return true


class CaptionStub extends Node:
	var posts: Array = []
	func post_caption(msg: String, _duration: float = 3.0) -> bool:
		posts.append(msg)
		return true


class TowerStub extends Node:
	# Same shape as TowerShell.sheltered(pos): the player calls with the body.
	func sheltered(_pos: Vector3) -> bool:
		return true


func _initialize() -> void:
	Sentinel.isolate_user_state()
	await process_frame
	var boot: Array = await _boot()
	if bool(boot[0]):
		_fail(String(boot[1]))
		_report()
		return
	var player: Node = boot[1]
	# The terrain grows real `bike_stand` markers as chunks build; the rack the
	# mount reads must be the stub this file placed, so the group is cleared
	# for the run and restored at the end. Removing from the group deletes
	# nothing — the markers stand where they stood.
	var real_stands: Array = _swap_group("bike_stand", null)
	await _check_mount(player)
	await _check_refuse(player)
	await _check_reach(player)
	_check_flat_speed(player)
	await _check_budget(player)
	await _check_edges(player)
	await _check_switch_budget(player)
	_check_visual_bit(player)
	await _check_key(player)
	_restore_group("bike_stand", null, real_stands)
	_report()


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
	else:
		for line: String in _failures:
			printerr("FAIL: " + line)
		printerr("SELFCHECK FAILED (%d)" % _failures.size())
		quit(1)


func _boot() -> Array:
	"""main.tscn running: the debug_teleport check's prelude (overlay dismissed)."""
	root.add_child(load("res://scenes/main.tscn").instantiate())
	await process_frame
	var overlay: Node = root.get_node_or_null("Main/HUD/StartOverlay")
	if overlay == null or not overlay.has_method("_dismiss"):
		return [true, "no dismissible StartOverlay under Main/HUD"]
	overlay._dismiss()
	await process_frame
	await physics_frame
	var player: Node = get_first_node_in_group("player")
	if player == null:
		return [true, "no player after boot"]
	return [false, player]


## Group-swap: park every member of `group` aside and (optionally) stand a stub
## in it, so the shipped group lookup answers the stub. Restored by
## `_restore_group`. Returns the parked members.
func _swap_group(group: StringName, stub: Node) -> Array:
	var parked: Array = []
	for n: Node in get_nodes_in_group(group):
		n.remove_from_group(group)
		parked.append(n)
	if stub != null:
		root.add_child(stub)
		stub.add_to_group(group)
	return parked


func _restore_group(group: StringName, stub: Node, parked: Array) -> void:
	if stub != null:
		stub.remove_from_group(group)
		stub.queue_free()
	for n: Node in parked:
		if is_instance_valid(n):
			n.add_to_group(group)


func _settle(player: Node) -> void:
	"""Park the player: dismounted, timers flat, no buffered press."""
	player.dismount_bike()
	player.jump_buffer_timer = 0.0
	player.speed_burst_timer = 0.0
	player.is_wading = false
	player.is_ducking = false
	player.velocity = Vector3.ZERO


func _add_stand(player: Node, met_from_player: Vector3, anchor: int = 7) -> Node:
	"""A stub rack: group + metas exactly as terrain_bike_paths writes them."""
	var at: Vector3 = player.global_position + met_from_player
	var stand := Node3D.new()
	stand.name = "BikeStand%d" % anchor
	stand.set_meta("anchor", anchor)
	stand.set_meta("pos", Vector3(at.x, 0.0, at.z))
	player.get_parent().add_child(stand)
	stand.global_position = Vector3(at.x, 0.0, at.z)
	stand.add_to_group("bike_stand")
	return stand


func _bike_node(player: Node) -> Node:
	return player.character_container.get_node_or_null("Bike")


## queue_free() is deferred: a freed rack stays in the group until the frame
## ends, and the next check would mount through the ghost. Out of the group
## NOW, freed whenever.
func _free_stand(stand: Node) -> void:
	stand.remove_from_group("bike_stand")
	stand.queue_free()


## Walk `metres` horizontal metres as chords of a 10 m circle around the body's
## current XZ, one physics frame per chord. Returns the metres actually covered
## (position deltas read back off the body — the budget's own quantity).
func _ride_metres(player: Node, metres: float) -> float:
	var center := Vector2(player.global_position.x, player.global_position.z)
	var covered := 0.0
	var angle := 0.0
	var guard := 0
	while covered < metres and guard < 400:
		guard += 1
		angle += 0.2
		var want := Vector2(center.x + 10.0 * cos(angle), center.y + 10.0 * sin(angle))
		var before := Vector2(player.global_position.x, player.global_position.z)
		var left := metres - covered
		var step: Vector2 = want - before
		if step.length() > left:
			step = step.normalized() * left
		player.global_position = Vector3(
			player.global_position.x + step.x, player.global_position.y,
			player.global_position.z + step.y)
		player.velocity = Vector3.ZERO
		await physics_frame
		covered += Vector2(
			player.global_position.x - before.x,
			player.global_position.z - before.y).length()
	return covered


func _check_mount(player: Node) -> void:
	"""Acceptance 1: 2 coins mount, full budget, mesh shown, speed exactly 14."""
	_settle(player)
	player.own_coins = 2
	player.coins_collected = 5
	player.record_coins = 0
	var stand := _add_stand(player, Vector3(1, 0, 0))
	if not player.try_mount_bike():
		_fail("mount: try_mount_bike() refused 2 coins at a rack 1 m away")
		_free_stand(stand)
		Sentinel.done("mount")
		return
	if player.own_coins != 0:
		_fail("mount: 2 coins in, own_coins is %d, not 0 — M-free" % player.own_coins)
	if player.coins_collected != 3:
		_fail("mount: coins_collected is %d, not 5 - 2 — M-cheap" % player.coins_collected)
	if player.record_coins != 2:
		_fail("mount: record_coins is %d, not the pre-bill peak 2" % player.record_coins)
	if not player.is_riding:
		_fail("mount: is_riding false after a paid mount")
	if player.bike_range_left != PlayerScript.BIKE_RANGE_METRES:
		_fail("mount: budget is %.1f, not BIKE_RANGE_METRES — M-cheap"
			% player.bike_range_left)
	var bike := _bike_node(player)
	if bike == null:
		_fail("mount: no Bike node under CharacterModel after mounting")
	elif not bool(bike.get("visible")):
		_fail("mount: Bike node hidden while riding")
	if player.calculate_current_speed() != PlayerScript.BIKE_SPEED:
		_fail("mount: speed is %.2f, not exactly BIKE_SPEED"
			% player.calculate_current_speed())
	_free_stand(stand)
	_settle(player)
	Sentinel.done("mount")


func _check_refuse(player: Node) -> void:
	"""Acceptance 2: 1 coin refuses, keeps its coin, toasts exactly once."""
	_settle(player)
	var toast := ToastStub.new()
	var parked: Array = _swap_group("landmark_toast", toast)
	player.own_coins = 1
	player.coins_collected = 4
	var stand := _add_stand(player, Vector3(1, 0, 0))
	if player.try_mount_bike():
		_fail("refuse: try_mount_bike() mounted with 1 coin — M-generous")
	if player.own_coins != 1:
		_fail("refuse: the single coin is gone after a refusal")
	if player.coins_collected != 4:
		_fail("refuse: coins_collected moved on a refusal")
	if player.is_riding:
		_fail("refuse: riding after a refusal")
	if toast.calls.is_empty():
		_fail("refuse: no toast announced — we saw nothing, M-mute")
	else:
		if toast.calls.size() != 1:
			_fail("refuse: toast announced %d times, not exactly once" % toast.calls.size())
		if String(toast.calls[0][0]) != "Not enough coins":
			_fail("refuse: toast title is %s, not 'Not enough coins'"
				% String(toast.calls[0][0]).c_escape())
		if not String(toast.calls[0][1]).contains("2"):
			_fail("refuse: toast body %s does not carry the 2-coin fare"
				% String(toast.calls[0][1]).c_escape())
	_free_stand(stand)
	_restore_group("landmark_toast", toast, parked)
	_settle(player)
	Sentinel.done("refuse")


func _check_reach(player: Node) -> void:
	"""Acceptance 3: a rack 10 m out is out of reach — no mount, no charge."""
	_settle(player)
	player.own_coins = 5
	var stand := _add_stand(player, Vector3(10, 0, 0))
	if player.try_mount_bike():
		_fail("reach: mounted a rack 10 m away — M-anywhere")
	if player.own_coins != 5:
		_fail("reach: a rack out of reach charged %d coins" % (5 - player.own_coins))
	if player.is_riding:
		_fail("reach: riding after an out-of-reach mount")
	_free_stand(stand)
	_settle(player)
	Sentinel.done("reach")


func _check_flat_speed(player: Node) -> void:
	"""Acceptance 4: the branch ignores gait_mult and wading — still exactly 14."""
	_settle(player)
	player.is_riding = true
	player.is_wading = true
	player.is_ducking = true
	player.speed_burst_timer = 5.0
	var mult: float = player._skill_gait_mult()
	if mult <= 1.0:
		_fail("flat_speed: gait_mult is %.3f with a burst running — the probe is vacuous" % mult)
		_settle(player)
		Sentinel.done("flat_speed")
		return
	if player.calculate_current_speed() != PlayerScript.BIKE_SPEED:
		_fail("flat_speed: wading + burst + ducking rides at %.2f, not exactly BIKE_SPEED — M-mult"
			% player.calculate_current_speed())
	_settle(player)
	Sentinel.done("flat_speed")


func _check_budget(player: Node) -> void:
	"""Acceptance 5: distance decrements; exhaustion ends the ride with a caption."""
	_settle(player)
	var caption := CaptionStub.new()
	var parked: Array = _swap_group("world_caption", caption)
	player.own_coins = 2
	var stand := _add_stand(player, Vector3(1, 0, 0))
	if not player.try_mount_bike():
		_fail("budget: could not mount for the ride")
		_free_stand(stand)
		_restore_group("world_caption", caption, parked)
		Sentinel.done("budget")
		return
	var covered: float = await _ride_metres(player, 100.0)
	if covered < 99.0:
		_fail("budget: the walk covered only %.1f m — the 4900 number is vacuous" % covered)
		_free_stand(stand)
		_restore_group("world_caption", caption, parked)
		_settle(player)
		Sentinel.done("budget")
		return
	var want: float = PlayerScript.BIKE_RANGE_METRES - covered
	if absf(player.bike_range_left - want) > 1.0:
		_fail("budget: after %.1f m the budget is %.1f, not %.1f — M-timer"
			% [covered, player.bike_range_left, want])
	player.bike_range_left = 0.5
	var before := Vector2(player.global_position.x, player.global_position.z)
	player.global_position = Vector3(
		player.global_position.x + 1.0, player.global_position.y, player.global_position.z)
	player.velocity = Vector3.ZERO
	await physics_frame
	var stepped: float = Vector2(
		player.global_position.x - before.x,
		player.global_position.z - before.y).length()
	if stepped < 0.5:
		_fail("budget: the 1 m step moved only %.2f m — the exhaustion is vacuous" % stepped)
	if player.is_riding:
		_fail("budget: still riding past a spent budget — M-immortal")
	if _bike_node(player) != null and bool(_bike_node(player).get("visible")):
		_fail("budget: Bike still drawn after the budget ran out")
	# The world posts its own landmark captions through the same group while
	# the ride walks, so the stub hears those too — the assertion is on the
	# bike's own line, which must appear exactly once.
	var dones: Array = caption.posts.filter(func(m: String) -> bool: return m == "The bike is done")
	if dones.size() != 1:
		_fail("budget: 'The bike is done' posted %d times, not exactly once" % dones.size())
	_free_stand(stand)
	_restore_group("world_caption", caption, parked)
	_settle(player)
	Sentinel.done("budget")


func _check_edges(player: Node) -> void:
	"""Acceptance 6: every ending dismounts — except the switch, which keeps."""
	_settle(player)
	# The reset-routed endings, driven through the shipped reset: tax contact,
	# respawn, capture, prison in-out, run end, hop, join, the HQ knockback all
	# call _reset_ability_states(), so the reset clearing the bike IS their
	# dismount. M-sticky (reset skips the bike) goes red here.
	player.own_coins = 2
	var stand := _add_stand(player, Vector3(1, 0, 0))
	if not player.try_mount_bike():
		_fail("edges: could not mount for the reset edge")
		_free_stand(stand)
		Sentinel.done("edges")
		return
	player._reset_ability_states()
	if player.is_riding:
		_fail("edges: riding after _reset_ability_states() — M-sticky")
	if _bike_node(player) != null and bool(_bike_node(player).get("visible")):
		_fail("edges: Bike still drawn after _reset_ability_states()")
	# ...and the routing is pinned by name: every edge the spike lists reaches
	# the reset. A removed call fails here naming the edge.
	var text := FileAccess.get_file_as_string("res://scripts/player_controller.gd")
	var routed: Array[String] = ["_pay_coin_setback", "_respawn_in_place",
		"_enter_prison", "_exit_prison", "_end_run", "reset_position",
		"join_at", "_jump_to"]
	for edge: String in routed:
		if not _func_calls(text, edge, "_reset_ability_states()"):
			_fail("edges: %s no longer reaches _reset_ability_states()" % edge)
	_free_stand(stand)
	# A jump press while riding dismounts INSTEAD of jumping: the buffered press
	# counts, the press is consumed, the body never leaves the ground. M-jump
	# (the press still jumps) goes red on the upward velocity.
	_settle(player)
	player.own_coins = 2
	stand = _add_stand(player, Vector3(1, 0, 0))
	if player.try_mount_bike():
		await physics_frame
		# The press may meet the air (a teleport-stepped body lands when it
		# lands), so wait for the verdict — a dismount or a launch — not for a
		# frame count. The buffer (0.5 s) outlives the wait either way.
		player.jump_buffer_timer = 0.5
		for _i: int in 40:
			await physics_frame
			if not player.is_riding or player.velocity.y > 0.0:
				break
		if player.is_riding:
			_fail("edges: a jump press while riding did not dismount")
		if player.jump_buffer_timer != 0.0:
			_fail("edges: the jump press was not consumed by the dismount")
		if player.velocity.y > 0.0:
			_fail("edges: the dismount press still jumped (vy %.2f) — M-jump" % player.velocity.y)
	else:
		_fail("edges: could not mount for the jump edge")
	_free_stand(stand)
	# Under the HQ roof the ride ends: the tower answers sheltered() true.
	_settle(player)
	var tower := TowerStub.new()
	var parked: Array = _swap_group("tower", tower)
	player.own_coins = 2
	stand = _add_stand(player, Vector3(1, 0, 0))
	if player.try_mount_bike():
		if not player.is_riding:
			_fail("edges: try_mount_bike() reported true but is_riding is false")
		await physics_frame
		if player.is_riding:
			_fail("edges: still riding under the roof")
	else:
		_fail("edges: could not mount for the roof edge")
	_free_stand(stand)
	_restore_group("tower", tower, parked)
	_settle(player)
	Sentinel.done("edges")


## The first physical key an input-map action binds (0 when none) — the turn
## control presses the KEY, the way a finger does, so every action on it fires.
func _action_physical_key(action: String) -> int:
	for event: InputEvent in InputMap.action_get_events(action):
		var as_key := event as InputEventKey
		if as_key != null and as_key.physical_keycode != 0:
			return int(as_key.physical_keycode)
	return 0


func _press_key(physical: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical
	ev.pressed = true
	Input.parse_input_event(ev)


func _release_key(physical: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical
	ev.pressed = false
	Input.parse_input_event(ev)


## Whether `func fname`'s body (up to the next top-level `func `) contains `call`.
func _func_calls(text: String, fname: String, call: String) -> bool:
	var start: int = text.find("func " + fname)
	if start < 0:
		return false
	var rest: String = text.substr(start)
	var next: int = rest.find("\nfunc ", 1)
	var body: String = rest.substr(0, next) if next >= 0 else rest
	return body.contains(call)


func _check_switch_budget(player: Node) -> void:
	"""Acceptance 7: the switch KEEPS the bike AND the budget; the mesh follows."""
	_settle(player)
	player.own_coins = 2
	var stand := _add_stand(player, Vector3(1, 0, 0))
	if not player.try_mount_bike():
		_fail("switch: could not mount for the switch")
		_free_stand(stand)
		Sentinel.done("switch")
		return
	var covered: float = await _ride_metres(player, 100.0)
	if covered < 99.0:
		_fail("switch: the walk covered only %.1f m — vacuous" % covered)
		_free_stand(stand)
		_settle(player)
		Sentinel.done("switch")
		return
	var bike_before: Node = _bike_node(player)
	var next: int = (player.current_character_index + 1) % player.CHARACTERS.size()
	player.set_active_character(next)
	if not player.is_riding:
		_fail("switch: the hero switch dismounted — M-switch breaks ruling 5")
	var want: float = PlayerScript.BIKE_RANGE_METRES - covered
	if absf(player.bike_range_left - want) > 1.0:
		_fail("switch: budget after the switch is %.1f, not %.1f — M-refill"
			% [player.bike_range_left, want])
	var bike_after: Node = _bike_node(player)
	if bike_after == null:
		_fail("switch: no Bike node after the switch")
	else:
		if not bool(bike_after.get("visible")):
			_fail("switch: Bike hidden on the new hero while riding")
		if bike_before != null and bike_after != bike_before:
			_fail("switch: the Bike node was re-created — it must survive the swap")
	_free_stand(stand)
	_settle(player)
	Sentinel.done("switch")


func _check_key(player: Node) -> void:
	"""Acceptance 10 (send-back): the mount key is X, shared with nothing.

	X (physical 88): beside WASD under the left hand, and not Y/Z, which swap
	on German QWERTZ boards. The audit is `city_map_selfcheck` check 1's, both
	halves: no input-map action shares the key (a rebindable gameplay action
	colliding is unfixable — both fire, forever), and no raw-keycode panel owns
	it (E names turn_right, B names the city map — the two mutations). The
	runtime half drives the SHIPPED poll: an X press mounts, while holding the
	turn-right key at a rack mounts nothing (the E bug, as a control).
	"""
	var key_events: Array = []
	for event: InputEvent in InputMap.action_get_events("mount_bike"):
		var as_key := event as InputEventKey
		if as_key != null:
			key_events.append(as_key)
	if key_events.size() != 1:
		_fail("key: mount_bike binds %d key events, not exactly one — the audit is vacuous"
			% key_events.size())
		Sentinel.done("key")
		return
	var key: int = int(key_events[0].physical_keycode)
	# NO early return on a wrong key: the scans below run against WHATEVER key
	# is bound, so a rebind mutation fails naming the key it collides with
	# (turn_right for E, the city map for B), not just naming a letter.
	var key_name: String = OS.get_keycode_string(key)
	if key != KEY_X:
		_fail("key: mount_bike is on %s, not X — M-key-E/M-key-B" % key_name)
	for action: StringName in InputMap.get_actions():
		if action == "mount_bike":
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			var as_key := event as InputEventKey
			if as_key == null:
				continue
			# BARE PRESSES ONLY, `debug_teleport_selfcheck`'s rule: a modified
			# chord (Ctrl+X, the editor's ui_cut) is a different chord, not a
			# collision — the unfixable kind is bare-vs-bare, both firing on one
			# press forever.
			if as_key.ctrl_pressed or as_key.alt_pressed or as_key.meta_pressed \
					or as_key.shift_pressed:
				continue
			if int(as_key.keycode) == key or int(as_key.physical_keycode) == key:
				_fail("key: %s is also bound to the input action \"%s\" — M-key-E names turn_right here" % [key_name, action])
	var claimed: String = CityMapSelfcheck._owner_claiming(
		key, CityMapSelfcheck.panel_key_owners())
	if not claimed.is_empty():
		_fail("key: %s is already %s — M-key-B names the city map here" % [key_name, claimed])
	if CityMapSelfcheck._owner_claiming(key, [[[key], "a fake flat owner"]]).is_empty():
		_fail("key: the scan missed a fake flat owner holding %s — it cannot detect a real collision either" % key_name)
	if CityMapSelfcheck._owner_claiming(key, [[[[key]], "a fake nested owner"]]).is_empty():
		_fail("key: the scan missed a fake nested owner holding %s — digits and keypad twins are not really compared" % key_name)
	# RUNTIME, through the shipped STEP 7.6 poll: an X press mounts ...
	_settle(player)
	player.own_coins = 2
	var stand := _add_stand(player, Vector3(1, 0, 0))
	# TWO awaits (`wade_selfcheck`'s measured timing gotcha): a press
	# synthesized from a physics_frame handler is stamped with the NEXT physics
	# frame, so the first frame misses it and the second mounts.
	Input.action_press("mount_bike")
	await physics_frame
	await physics_frame
	Input.action_release("mount_bike")
	if not player.is_riding:
		_fail("key: an X press at a rack did not mount through the shipped poll")
		_free_stand(stand)
		_settle(player)
		Sentinel.done("key")
		return
	# ... while the physical turn-right key at the same rack mounts nothing and
	# charges nothing. A REAL key event (`parse_input_event`), not
	# `action_press`: the E bug was one press firing TWO actions, and faking the
	# action alone cannot replay it. Same two-await stamping as the X probe.
	_settle(player)
	player.own_coins = 2
	var turn_key: int = _action_physical_key("turn_right")
	if turn_key == 0:
		_fail("key: turn_right binds no physical key — the control is vacuous")
		_free_stand(stand)
		_settle(player)
		Sentinel.done("key")
		return
	_press_key(turn_key)
	await physics_frame
	await physics_frame
	_release_key(turn_key)
	if player.is_riding:
		_fail("key: holding turn-right at a rack mounted — the E bug is back")
	if player.own_coins != 2:
		_fail("key: holding turn-right at a rack charged %d coins" % (2 - player.own_coins))
	_free_stand(stand)
	_settle(player)
	Sentinel.done("key")


func _check_visual_bit(player: Node) -> void:
	"""Acceptance 8: bit 5 set while riding, clear after, still a byte."""
	_settle(player)
	player.own_coins = 2
	var stand := _add_stand(player, Vector3(1, 0, 0))
	if not player.try_mount_bike():
		_fail("bit: could not mount for the bit check")
		_free_stand(stand)
		Sentinel.done("visual_bit")
		return
	var bits: int = player.ability_visual_state()
	if bits & PlayerScript.ABILITY_BIT_BIKE == 0:
		_fail("bit: ABILITY_BIT_BIKE not set while riding")
	if bits != PlayerScript.ABILITY_BIT_BIKE:
		_fail("bit: visual state is %d while only riding — a stale bit leaks" % bits)
	if bits > 255:
		_fail("bit: visual state %d exceeds the mp_codec byte clamp" % bits)
	player.dismount_bike()
	var after: int = player.ability_visual_state()
	if after & PlayerScript.ABILITY_BIT_BIKE != 0:
		_fail("bit: ABILITY_BIT_BIKE still set after dismount")
	if after != 0:
		_fail("bit: visual state is %d after a clean dismount, not 0" % after)
	_free_stand(stand)
	_settle(player)
	Sentinel.done("visual_bit")
