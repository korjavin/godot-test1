extends Label
## In-game performance overlay (debug HUD) — our measurement "safety net".
##
## This is Task 1 of the web-performance-optimization plan. Before we change
## anything about how the world renders or how the crocodiles simulate, we need a
## way to *prove* each later change actually helps (numbers move the right way)
## and that nothing regressed. There is no automated test suite in this project,
## so this live overlay is how we measure on the real (web) build.
##
## What it shows, refreshed a few times a second:
##   * FPS                — frames per second (higher is smoother).
##   * Process ms         — CPU time spent in the main (per-frame) logic.
##   * Physics ms         — CPU time spent in the fixed-step physics loop
##                          (this is where the ~1,200 crocodiles cost us today).
##   * Draw calls         — how many separate "draw this" commands the GPU got
##                          this frame. Thousands of unique block meshes blow this
##                          up; MultiMesh batching (Task 4) collapses it.
##   * Primitives         — rendered triangles/lines this frame (geometry load).
##   * Nodes              — total nodes alive in the scene tree (consolidating
##                          per-block collision in Task 5 should drop this hard).
##   * Crocodiles         — how many crocodiles exist, and (once Task 3 lands)
##                          how many are actually *simulating* vs frozen by LOD.
##
## It lives in the HUD CanvasLayer as a plain Label. It does not touch gameplay:
## it only reads counters and prints them. It ignores mouse input and starts
## hidden in release builds so it never ends up in a player's face.

## Key that toggles the overlay on/off. F3 is the conventional "debug stats" key
## and does not collide with any of our gameplay input actions (move/jump/run/
## duck/switch_character) defined in project.godot.
const TOGGLE_KEYCODE: Key = KEY_F3

## How often (seconds) we recompute the text. We deliberately do NOT update every
## frame: counting nodes / iterating the crocodile group every frame would itself
## cost performance and bias the very numbers we are trying to measure. ~4 Hz is
## smooth enough to read while staying cheap.
const REFRESH_INTERVAL: float = 0.25

## Seconds left until the next text refresh (counts down each frame).
var _time_until_refresh: float = 0.0

## Cached player reference, re-fetched via the "player" group if it goes away
## (e.g. after a respawn). Matches the rest of the project's group-based lookup.
var _player: Node = null


func _ready() -> void:
	# Add to a group so other systems could find/toggle us later if needed.
	add_to_group("perf_overlay")

	# Never let this debug label eat mouse clicks meant for the game/UI.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Make the readout legible over the bright sky: pale text with a dark outline,
	# pinned to the top-left so it never overlaps the top-right coin counter.
	add_theme_color_override("font_color", Color(0.9, 1.0, 0.9, 1.0))
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	add_theme_constant_override("outline_size", 6)
	add_theme_font_size_override("font_size", 18)

	# Start hidden by default. In a debug build (running from the editor or a
	# debug export) we show it immediately so we always have numbers while
	# developing; in a release build it stays hidden until the player presses F3.
	# This guarantees the overlay never ships "in the player's face".
	visible = OS.is_debug_build()

	# Seed the first refresh so text appears right away rather than after a delay.
	_time_until_refresh = 0.0


func _input(event: InputEvent) -> void:
	# Toggle visibility on the configured key. We read the raw key here (rather
	# than a named input action) on purpose: this is a developer/debug toggle, not
	# a gameplay control, so it intentionally lives outside the project's input map.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == TOGGLE_KEYCODE:
			visible = not visible
			# Re-fetching the player and forcing an immediate refresh makes the
			# overlay feel instant the moment it is shown.
			if visible:
				_time_until_refresh = 0.0


func _process(delta: float) -> void:
	# Cheap-return while hidden so the overlay costs essentially nothing when off.
	if not visible:
		return

	# Throttle the (relatively expensive) stat gathering to REFRESH_INTERVAL.
	_time_until_refresh -= delta
	if _time_until_refresh > 0.0:
		return
	_time_until_refresh = REFRESH_INTERVAL

	_update_text()


## Gather all the counters and rebuild the label text.
func _update_text() -> void:
	# --- Frame timing ------------------------------------------------------
	# FPS straight from the engine. Performance.TIME_PROCESS / TIME_PHYSICS_PROCESS
	# report the last frame's CPU time in *seconds*, so multiply by 1000 for ms,
	# which is the unit everyone reasons about for frame budget (16.6 ms = 60 FPS).
	var fps: float = Engine.get_frames_per_second()
	var process_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	# --- GPU / render load -------------------------------------------------
	# Draw calls are the headline number for the MultiMesh batching task: today
	# every decorative block is its own MeshInstance3D + material = its own draw
	# call. Primitives is the raw geometry (triangles) submitted this frame.
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var primitives: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))

	# --- Scene size --------------------------------------------------------
	# Total nodes alive. Consolidating per-block StaticBody3D collision into one
	# body per chunk (Task 5) should make this fall sharply.
	var node_count: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

	# --- Crocodile simulation count ---------------------------------------
	# Count crocodiles via the "crocodile" group (the same group the future LOD
	# manager will use). We also count how many are "active" (simulating). Until
	# Task 3 adds the `lod_active` flag, every crocodile is treated as active, so
	# active == total and the line still reads sensibly.
	var crocodiles: Array = get_tree().get_nodes_in_group("crocodile")
	var croc_total: int = crocodiles.size()
	var croc_active: int = 0
	for croc in crocodiles:
		# `"lod_active" in croc` is true once the property exists (Task 3); before
		# that, or if the flag is true, the crocodile counts as actively simulating.
		if not ("lod_active" in croc) or croc.lod_active:
			croc_active += 1

	# --- Compose the readout ----------------------------------------------
	# Using a multi-line string keeps each metric on its own row, easy to read
	# and easy to screenshot for the before/after measurement table in the plan.
	text = "PERF (F3)\n"
	text += "FPS: %d\n" % int(roundf(fps))
	text += "Process: %.2f ms\n" % process_ms
	text += "Physics: %.2f ms\n" % physics_ms
	text += "Draw calls: %d\n" % draw_calls
	text += "Primitives: %d\n" % primitives
	text += "Nodes: %d\n" % node_count
	text += "Crocs (active/total): %d / %d" % [croc_active, croc_total]
