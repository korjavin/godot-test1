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
##

const SoundManager := preload("res://scripts/sound_manager.gd")
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	Sentinel.isolate_user_state()
	_run()


func _run() -> void:
	await process_frame
	_check_sound_unlock_and_loops()
	_check_waypoint_cues()
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
