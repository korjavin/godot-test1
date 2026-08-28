extends SceneTree
## THROWAWAY visual tour of the tower interior — not shipped, deleted after use.
##   godot --path . --script res://_tour.gd --resolution 1280x720

const SHOTS: String = "user://tour"


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for _i in 30:
		await process_frame

	# Dismiss the start overlay so the world runs.
	var overlay := main.get_node_or_null("HUD/StartOverlay") as Control
	if overlay != null and overlay.visible:
		if overlay.has_method("_on_play_solo_pressed"):
			overlay.call("_on_play_solo_pressed")
		else:
			overlay.hide()
	paused = false
	for _i in 20:
		await process_frame

	var player := main.get_node_or_null("Player") as Node3D
	var terrain := main.get_node_or_null("EndlessTerrain") as Node3D
	var site: Vector3 = terrain.call("tower_site")
	print("tower site: ", site)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))

	# Looking WEST (toward -X, i.e. into the tower) is yaw +PI/2; east is -PI/2.
	const W: float = PI * 0.5
	const E: float = -PI * 0.5
	# 1. Approach: outside the yard, looking at the doorway.
	await _pose(player, site + Vector3(46.0, 0.0, 0.0), W, "01_approach")
	# 2. In the doorway.
	await _pose(player, site + Vector3(11.0, 0.0, 0.0), W, "02_doorway")
	# 3. Entry hall, looking west at the rotor gate.
	await _pose(player, site + Vector3(6.0, 0.0, 0.0), W, "03_hall")
	# 4. The rotor gate up close (the challenge space).
	await _pose(player, site + Vector3(2.5, 0.0, 0.0), W, "04_rotor")
	# 5. The demand gate: standing on the receptacle plate, facing it (-Z).
	await _pose(player, site + Vector3(5.8, 0.0, -2.6), 0.0, "05_demand")
	# 6. Courtyard, looking back east at the rotor gate.
	await _pose(player, site + Vector3(-5.0, 0.0, 2.0), E, "06_courtyard")
	# 7. Foot of the ramp, looking up it (east).
	await _pose(player, site + Vector3(-8.0, 0.0, 7.4), E, "07_ramp_foot")
	# 8. Upper floor, looking east at the secure door.
	await _pose(player, site + Vector3(-0.2, 4.8, 4.0), E, "08_upper")
	# 9. On the identity pad, as Windman (gate shut).
	await _pose(player, site + Vector3(2.2, 4.8, 0.0), E, "09_identity_shut")
	# 10. Switch to Teibi and open it.
	var index := _hero_index(player, "teibi")
	if index >= 0:
		player.call("set_active_character", index)
	for _i in 200:
		await process_frame
	await _pose(player, site + Vector3(2.2, 4.8, 0.0), E, "10_identity_open")
	# 11. Through the door, at the checkpoint, looking back west through it.
	await _pose(player, site + Vector3(8.2, 4.8, 0.0), W, "11_checkpoint")
	# 12. Back outside: the risen counterweight over the parapet.
	await _pose(player, site + Vector3(40.0, 0.0, 0.0), W, "12_risen_mass")
	# 13. First person inside the hall (C cycles views; call the toggle directly).
	if "view_mode" in player:
		player.set("view_mode", 1)
		player.call("_apply_view_mode")
	await _pose(player, site + Vector3(6.0, 0.0, 0.0), W, "13_hall_firstperson")
	await _pose(player, site + Vector3(1.5, 4.8, 0.0), E, "14_upper_firstperson")

	print("tour done")
	quit(0)


func _hero_index(player: Node3D, want: String) -> int:
	var list: Array = player.get("CHARACTERS")
	for i in list.size():
		if String(list[i]["name"]) == want:
			return i
	return -1


func _pose(player: Node3D, where: Vector3, yaw: float, shot: String) -> void:
	player.global_position = where
	player.rotation = Vector3(0.0, yaw, 0.0)
	player.set("velocity", Vector3.ZERO)
	for croc: Node in get_nodes_in_group("crocodile"):
		croc.queue_free()
	for _i in 45:
		await process_frame
	var image := root.get_texture().get_image()
	var path := "%s/%s.png" % [SHOTS, shot]
	image.save_png(path)
	print("shot %s -> %s" % [shot, ProjectSettings.globalize_path(path)])
