extends SceneTree
## ============================================================================
## SOUND MANAGER SELF-CHECK — run headless, prints "SELFCHECK OK", exits 0
## ============================================================================
##
##     godot --headless --path . --script res://scripts/sound_selfcheck.gd
##
## Guards:
##  1. No ambient wind bed: unlock_audio() opens the browser-gesture gate
##     without starting any audio playback. No AudioStreamPlayer child is playing.
##  2. _loop_players has no "wind" key.
##  3. Event-driven loop voices (heartbeat pre-baked, rain lazily created) exist
##     but remain stopped until explicitly driven by their respective managers.
##  4. THE TWO WAYPOINT CUES (epic godot-test1-sc6, bead .5): both are gated
##     behind unlock_audio() like every other play path, `play_waypoint_found`
##     lands three RISING taps of the COIN buffer on three pool voices, and
##     `play_waypoint_travel` plays a "whoosh_rev" buffer that is the whoosh
##     backwards to the sample — not a copy of it, and not an asset file.
##  5. And the hub actually calls the new cue: bead .2 borrowed `play_level_up`
##     and marked the line, so this greps `waypoint_hub.gd` to prove the borrow
##     was returned. A cue nothing fires is a cue nobody hears.
##  6. THE ROAD MUSIC (bead godot-test1-bv0f): the motif starts inside 80 m of
##     a compass target or a circle and climbs, holds under a chase without
##     taking a voice, stops voiceless on a loss, resolves a fifth-to-octave
##     cadence on a visited target or the stood edge, sings nothing while
##     standing, and plays a falling one-bar phrase on every 25th pickup.
##

const SoundManager := preload("res://scripts/sound_manager.gd")
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")

var _failures: Array[String] = []


## Group-peer stubs for the road-music check. They expose the SAME method names
## the real minimap / hub / toast carry (the brief's allowed stub shape); every
## voice assertion reads the REAL sound_manager node's pool.
class StubCompass extends Node:
	var dist: float = INF
	var pos: Vector3 = Vector3.ZERO
	func compass_target_distance() -> float:
		return dist
	func compass_target_pos() -> Vector3:
		return pos


class StubHub extends Node:
	var stood: int = -1
	var circle_dist: float = INF
	func standing_on() -> int:
		return stood
	func nearest_circle_distance(_from: Vector3) -> float:
		return circle_dist


class StubToast extends Node:
	var visited: bool = false
	func is_visited(_pos: Vector3) -> bool:
		return visited


class StubCroc extends Node:
	var is_chasing: bool = false


func _initialize() -> void:
	Sentinel.isolate_user_state()
	_run()


func _run() -> void:
	await process_frame
	_check_sound_unlock_and_loops()
	_check_waypoint_cues()
	_check_road_music()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	printerr("SELFCHECK FAILED (%d)" % _failures.size())
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


func _check_sound_unlock_and_loops() -> void:
	var sm := SoundManager.new()
	root.add_child(sm)

	var loop_players: Dictionary = sm.get("_loop_players")
	if loop_players.has("wind"):
		_fail("sound_manager must not register an ambient 'wind' loop player")

	if not loop_players.has("heartbeat"):
		_fail("sound_manager must register the 'heartbeat' loop player")

	# Lazily request the rain player as weather_manager does.
	var rain_player: AudioStreamPlayer = sm.get_loop_player("rain")
	if rain_player == null or not loop_players.has("rain"):
		_fail("get_loop_player('rain') did not create the rain player")

	# Browser gate starts locked.
	if sm.is_unlocked():
		_fail("sound_manager must start locked")

	# Unlock audio on first gesture.
	sm.unlock_audio()
	if not sm.is_unlocked():
		_fail("unlock_audio() must set is_unlocked() to true")

	# Assert no AudioStreamPlayer child is playing.
	for child in sm.get_children():
		if child is AudioStreamPlayer:
			if child.playing:
				_fail("AudioStreamPlayer child '%s' is playing after unlock_audio(); expected silence" % child.name)

	# Verify heartbeat and rain players specifically exist and are stopped.
	var heartbeat_player: AudioStreamPlayer = loop_players.get("heartbeat")
	if heartbeat_player == null:
		_fail("heartbeat player missing from _loop_players")
	elif heartbeat_player.playing:
		_fail("heartbeat player must exist but be stopped")

	if rain_player != null and rain_player.playing:
		_fail("rain player must exist but be stopped")

	root.remove_child(sm)
	sm.free()
	Sentinel.done("sound_unlock_and_loops")


func _check_waypoint_cues() -> void:
	## Checks 4 and 5 — the two cues epic godot-test1-sc6 bead .5 adds.
	##
	## NOTHING HERE ASKS WHETHER A VOICE IS `playing`. Headless runs on the dummy
	## audio driver, where that flag is not a promise; what IS a promise is the
	## state `_play_oneshot` writes before it calls play() — which pool voice, which
	## buffer, which pitch. So the assertions read the POOL, which is also what makes
	## "three taps, rising" checkable at all: the three are three voices.
	var sm := SoundManager.new()
	root.add_child(sm)
	var players: Array = sm.get("_players")
	var streams: Dictionary = sm.get("_streams")

	# --- THE GATE, and it is the negative control for everything below: while the
	# browser-gesture gate is shut, both new paths must consume no voice at all.
	sm.play_waypoint_found()
	sm.play_waypoint_travel()
	if int(sm.get("_next_player")) != 0:
		_fail("a waypoint cue took a pool voice before unlock_audio() — the gesture gate is bypassed")

	sm.unlock_audio()

	# --- CHECK 4a: three taps of the COIN buffer, rising, on three voices.
	sm.play_waypoint_found()
	var used: int = SoundManager.WAYPOINT_FOUND_PITCHES.size()
	if int(sm.get("_next_player")) != used:
		_fail("play_waypoint_found() took %d pool voices, expected %d (three taps)"
			% [int(sm.get("_next_player")), used])
	var previous: float = 0.0
	for i in range(used):
		var voice: AudioStreamPlayer = players[i]
		if voice.stream != streams.get("coin"):
			_fail("waypoint-found tap %d plays a buffer that is not the coin — bead .5 replays, it does not bake" % i)
		if voice.pitch_scale <= previous:
			_fail("waypoint-found tap %d is pitched %.3f, not above the previous %.3f — the taps must RISE"
				% [i, voice.pitch_scale, previous])
		previous = voice.pitch_scale
	# ...and NOT the level-up, which is TWO taps of this same buffer and can fire in
	# the same minute. A third tap is the whole of what tells them apart by ear.
	if used < 3:
		_fail("play_waypoint_found() is %d taps — the level-up is 2, and these two cues must not be one sound" % used)

	# --- CHECK 4b: the travel cue is the whoosh BACKWARDS, to the sample.
	sm.play_waypoint_travel()
	var travel: AudioStreamPlayer = players[used]
	if travel.stream != streams.get("whoosh_rev"):
		_fail("play_waypoint_travel() does not play the reversed whoosh buffer")
	if not is_equal_approx(travel.pitch_scale, SoundManager.WAYPOINT_TRAVEL_PITCH):
		_fail("play_waypoint_travel() played at pitch %.3f, not WAYPOINT_TRAVEL_PITCH" % travel.pitch_scale)
	var forward: AudioStreamWAV = streams.get("whoosh")
	var backward: AudioStreamWAV = streams.get("whoosh_rev")
	if forward == null or backward == null:
		_fail("the whoosh / whoosh_rev buffers are not both baked")
	elif forward.data.size() != backward.data.size():
		_fail("whoosh_rev is %d bytes against the whoosh's %d — it is not the same buffer reversed"
			% [backward.data.size(), forward.data.size()])
	else:
		# Frame 0 of the reversal must be the LAST frame of the original (16-bit
		# mono, 2 bytes a frame). Equality of the whole buffer would pass for a
		# palindrome of silence; this pins the direction, and the tail test below
		# refuses a buffer that is merely a copy.
		var last: int = forward.data.size() - 2
		if backward.data[0] != forward.data[last] or backward.data[1] != forward.data[last + 1]:
			_fail("whoosh_rev does not start on the whoosh's last frame — the reversal is wrong-way-round")
		if backward.data == forward.data:
			_fail("whoosh_rev is byte-identical to the whoosh — it was copied, not reversed")

	root.remove_child(sm)
	sm.free()

	# --- CHECK 5: the hub returned the borrowed cue.
	var hub: String = FileAccess.get_file_as_string("res://scripts/waypoint_hub.gd")
	if hub.is_empty():
		_fail("could not read waypoint_hub.gd to check which cue it fires")
	else:
		if not hub.contains("play_waypoint_found"):
			_fail("waypoint_hub.gd never calls play_waypoint_found() — a find still borrows another cue")
		if hub.contains("sound.call(\"play_level_up\")"):
			_fail("waypoint_hub.gd still fires play_level_up() — bead .5 returns that borrow")
	Sentinel.done("waypoint_cues")


func _check_road_music() -> void:
	## Check 6 — the road music (bead godot-test1-bv0f).
	##
	## Drives the REAL sound_manager node (`tick_road_music()`, the same step
	## `_process()` accumulates into) and reads the REAL pool state
	## (`_players` / `_streams` / `_next_player`); only the group PEERS are
	## stubs, exposing the same method names the real minimap / hub / toast
	## carry. The pool wraps at ONESHOT_PLAYER_COUNT, so `expected` counts
	## every voice while `_voice()` reads the wrapped slot.
	var sm := SoundManager.new()
	root.add_child(sm)
	var players: Array = sm.get("_players")
	var streams: Dictionary = sm.get("_streams")
	var coin_stream: AudioStreamWAV = streams.get("coin")
	var pool_size: int = SoundManager.ONESHOT_PLAYER_COUNT
	var expected: int = 0

	var player_stub := Node3D.new()
	player_stub.add_to_group("player")
	root.add_child(player_stub)
	var compass := StubCompass.new()
	compass.add_to_group("minimap")
	root.add_child(compass)
	var hub := StubHub.new()
	hub.add_to_group("waypoint_hub")
	root.add_child(hub)
	var toast := StubToast.new()
	toast.add_to_group("landmark_toast")
	root.add_child(toast)
	var croc := StubCroc.new()
	croc.add_to_group("crocodile")
	root.add_child(croc)

	# --- THE GATE: everything hot, still locked → no voice at all. ---
	compass.dist = 50.0
	sm.tick_road_music()
	_expect_voices(sm, expected, "road music took a pool voice before unlock_audio()")
	sm.unlock_audio()

	# --- APPROACH: inside 80 m the motif starts and climbs, every 2nd tick. ---
	sm.tick_road_music()
	expected += 1
	_expect_voices(sm, expected, "approach inside 80 m played no motif note")
	_expect_tap(players, 0, coin_stream, SoundManager.ROAD_MOTIF_PITCHES[0],
			SoundManager.ROAD_MOTIF_VOLUME_DB, "motif note 0")
	sm.tick_road_music()  # cooldown tick: no note
	_expect_voices(sm, expected, "motif played on consecutive ticks — notes are every ROAD_MOTIF_NOTE_EVERY ticks")
	sm.tick_road_music()
	expected += 1
	_expect_voices(sm, expected, "motif missed its 2nd-tick note")
	var climb0: float = (players[0] as AudioStreamPlayer).pitch_scale
	var climb1: float = (players[1 % pool_size] as AudioStreamPlayer).pitch_scale
	if climb1 <= climb0:
		_fail("motif does not climb: note 1 pitched %.4f vs note 0 %.4f" % [climb1, climb0])

	# --- CHASE: a chasing croc holds the music — no voice, no lost place. ---
	croc.is_chasing = true
	sm.tick_road_music()
	sm.tick_road_music()
	_expect_voices(sm, expected, "road music took a voice while is_chasing — the motif must yield to acquisition cues")
	croc.is_chasing = false
	sm.tick_road_music()  # the held cooldown tick
	_expect_voices(sm, expected, "music did not HOLD under a chase — it restarted or skipped ahead")
	sm.tick_road_music()  # the held climb position: step 2, still rising
	expected += 1
	_expect_voices(sm, expected, "motif did not resume after the chase")
	_expect_tap(players, 2, coin_stream, SoundManager.ROAD_MOTIF_PITCHES[2],
			SoundManager.ROAD_MOTIF_VOLUME_DB, "resumed motif note")

	# --- LOSS WITHOUT ARRIVAL: the target unloads unvisited → stop, no cadence. ---
	compass.dist = INF
	sm.tick_road_music()
	_expect_voices(sm, expected, "an unvisited target loss earned a cadence — a resolve is owed to an arrival, not a loss")
	# ...and the next approach restarts the climb from the bottom.
	compass.dist = 50.0
	sm.tick_road_music()
	expected += 1
	_expect_voices(sm, expected, "re-approach played no motif note")
	_expect_tap(players, 3, coin_stream, SoundManager.ROAD_MOTIF_PITCHES[0],
			SoundManager.ROAD_MOTIF_VOLUME_DB, "re-approach motif note")

	# --- ARRIVAL (landmark): a visited target resolves fifth-into-octave. ---
	toast.visited = true
	sm.tick_road_music()
	expected += 2
	_expect_voices(sm, expected, "a visited approach target did not resolve a 2-tap cadence")
	for i in range(2):
		_expect_tap(players, 4 + i, coin_stream, SoundManager.ROAD_RESOLVE_PITCHES[i],
				SoundManager.ROAD_RESOLVE_VOLUME_DB, "resolve tap %d" % i)
	# ...and the approach is over: the compass drops a visited target, silence.
	compass.dist = INF
	sm.tick_road_music()
	sm.tick_road_music()
	_expect_voices(sm, expected, "motif kept singing after the resolve — arrival ends the approach")

	# --- ARRIVAL (circle): the stood edge resolves with no compass at all. ---
	hub.circle_dist = 30.0
	sm.tick_road_music()  # circle approach starts, one motif note
	expected += 1
	_expect_voices(sm, expected, "no motif note on a circle approach")
	hub.stood = 2
	sm.tick_road_music()  # the stood EDGE → cadence
	expected += 2
	_expect_voices(sm, expected, "the stood edge did not resolve a cadence")
	for i in range(2):
		_expect_tap(players, 7 + i, coin_stream, SoundManager.ROAD_RESOLVE_PITCHES[i],
				SoundManager.ROAD_RESOLVE_VOLUME_DB, "circle resolve tap %d" % i)
	sm.tick_road_music()  # standing on the circle: nothing more
	_expect_voices(sm, expected, "motif sings while standing on the circle")
	hub.stood = -1
	hub.circle_dist = INF
	sm.tick_road_music()  # walked off to open road: nothing more either
	_expect_voices(sm, expected, "motif sings on the open road with no target in range")

	# --- PHRASE: silent for 24 pickups, a FALLING one-bar line on the 25th. ---
	for i in range(SoundManager.ROAD_PHRASE_EVERY - 1):
		sm.notify_coin_pickup()
	sm.tick_road_music()
	_expect_voices(sm, expected, "a coin phrase fired before the %dth pickup" % SoundManager.ROAD_PHRASE_EVERY)
	sm.notify_coin_pickup()  # the 25th queues the bar
	for i in range(SoundManager.ROAD_PHRASE_PITCHES.size()):
		sm.tick_road_music()
		expected += 1
		_expect_voices(sm, expected, "phrase tap %d missing — the bar is one tap per tick" % i)
		_expect_tap(players, 9 + i, coin_stream, SoundManager.ROAD_PHRASE_PITCHES[i],
				SoundManager.ROAD_PHRASE_VOLUME_DB, "phrase tap %d" % i)
		if i > 0:
			var prev: AudioStreamPlayer = players[(9 + i - 1) % pool_size]
			var tap: AudioStreamPlayer = players[(9 + i) % pool_size]
			if tap.pitch_scale >= prev.pitch_scale:
				_fail("phrase does not FALL — its contour must differ from waypoint_found's rising triad")

	# --- LEVELS, stated next to the existing cues they sit under. ---
	if not (SoundManager.ROAD_MOTIF_VOLUME_DB < SoundManager.FOOTSTEP_VOLUME_DB):
		_fail("motif at %.1f dB is not under the quietest one-shot (footstep %.1f)" \
				% [SoundManager.ROAD_MOTIF_VOLUME_DB, SoundManager.FOOTSTEP_VOLUME_DB])
	if not (SoundManager.ROAD_PHRASE_VOLUME_DB < SoundManager.COIN_VOLUME_DB):
		_fail("phrase at %.1f dB is not under the coin blip (%.1f)" \
				% [SoundManager.ROAD_PHRASE_VOLUME_DB, SoundManager.COIN_VOLUME_DB])
	if not (SoundManager.ROAD_RESOLVE_VOLUME_DB < SoundManager.GROWL_VOLUME_DB):
		_fail("resolve at %.1f dB is not under the threat cues (growl %.1f)" \
				% [SoundManager.ROAD_RESOLVE_VOLUME_DB, SoundManager.GROWL_VOLUME_DB])
	if not is_equal_approx(SoundManager.ROAD_MOTIF_RANGE, 80.0):
		_fail("approach range is %.1f m, not the ~80 m the bead wants" % SoundManager.ROAD_MOTIF_RANGE)
	if SoundManager.ROAD_PHRASE_EVERY != 25:
		_fail("phrase fires every %d pickups, not the ~25 the bead wants" % SoundManager.ROAD_PHRASE_EVERY)

	# --- THE COUNTER IS FED: both pickup paths notify, or no phrase ever fires.
	var controller: String = FileAccess.get_file_as_string("res://scripts/player_controller.gd")
	if controller.is_empty():
		_fail("could not read player_controller.gd to check the phrase counter's feeds")
	elif controller.count("notify_coin_pickup") < 2:
		_fail("fewer than two notify_coin_pickup() call sites — collect_coin() AND bank_awarded() must feed the phrase counter")

	for stub: Node in [player_stub, compass, hub, toast, croc]:
		root.remove_child(stub)
		stub.free()
	root.remove_child(sm)
	sm.free()
	Sentinel.done("road_music")


func _expect_voices(sm: Node, expected_total: int, message: String) -> void:
	## The pool wraps, so the wrapped `_next_player` must equal the total mod
	## the pool size — Godot exits 0 on runtime errors, count the voices instead.
	var pool_size: int = SoundManager.ONESHOT_PLAYER_COUNT
	if int(sm.get("_next_player")) != expected_total % pool_size:
		_fail("%s (pool holds %d, expected voice %d)" \
				% [message, int(sm.get("_next_player")), expected_total])


func _expect_tap(players: Array, voice_total: int, stream: AudioStreamWAV,
		pitch: float, volume_db: float, what: String) -> void:
	## One tapped voice: the coin buffer (bv0f replays, it does not bake), at
	## the composed pitch and level. `voice_total` is the unwrapped count; the
	## slot wraps with the pool.
	var voice: AudioStreamPlayer = players[voice_total % SoundManager.ONESHOT_PLAYER_COUNT]
	if voice.stream != stream:
		_fail("%s is not the coin buffer" % what)
	if not is_equal_approx(voice.pitch_scale, pitch):
		_fail("%s pitched %.4f, expected %.4f" % [what, voice.pitch_scale, pitch])
	if not is_equal_approx(voice.volume_db, volume_db):
		_fail("%s at %.1f dB, expected %.1f" % [what, voice.volume_db, volume_db])
