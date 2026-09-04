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
