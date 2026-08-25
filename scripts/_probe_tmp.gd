extends SceneTree

func _initialize() -> void:
	var prog := Progression.new()
	prog.persistence_enabled = false
	root.add_child(prog)
	var panel: Control = Control.new()
	panel.set_script(load("res://scripts/skill_tree_ui.gd"))
	root.add_child(panel)
	_run()

func _run() -> void:
	await process_frame
	var panel: Control = root.get_node("Control")
	print("card child0 = ", panel._card.get_child(0).get_class(),
		" children=", panel._card.get_child_count())
	var prog: Node = root.get_first_node_in_group("progression")
	prog.lifetime_coins = 100000
	prog.level = Progression.level_for(prog.lifetime_coins)
	panel._set_panel_open(true)
	panel._view_hero = "teibi"
	panel._rebuild()
	print("columns=", panel._columns.get_child_count(),
		" tabs=", panel._tab_row.get_child_count())
	# rebuild twice in one frame: queue_free'd children still present?
	panel._rebuild()
	print("after 2nd rebuild same frame: columns=", panel._columns.get_child_count(),
		" tabs=", panel._tab_row.get_child_count())
	for c in panel._columns.get_children():
		print("  col ", c.name, " visible=", c.visible, " children=", c.get_child_count())
	await process_frame
	print("next frame: columns=", panel._columns.get_child_count(),
		" tabs=", panel._tab_row.get_child_count())
	panel._set_panel_open(false)
	print("paused=", root.get_tree().paused)
	quit()
