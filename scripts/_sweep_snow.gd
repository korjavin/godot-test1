extends SceneTree
## THROWAWAY sweep: measure biome band area shares + snow cadence along +X for
## candidate 6-band threshold sets. Not shipped — deleted before the PR.
##   godot --headless --path . --script res://scripts/_sweep_snow.gd

const TERRAIN_SCRIPT: String = "res://scripts/endless_terrain.gd"

# [label, desert_max, plains_max, city_max, forest_max, mountain_max]
# mountain_max == 1.01 means "no snow band", i.e. the shipped 5-band layout.
const CANDIDATES: Array = [
	["shipped 5-band       ", 0.34, 0.575, 0.66, 0.82, 1.01],
	["H 76/84              ", 0.34, 0.575, 0.66, 0.76, 0.84],
	["I 75/83              ", 0.34, 0.575, 0.66, 0.75, 0.83],
	["J 74/83              ", 0.34, 0.575, 0.66, 0.74, 0.83],
	["K 76/85              ", 0.34, 0.575, 0.66, 0.76, 0.85],
	["L 74/82              ", 0.34, 0.575, 0.66, 0.74, 0.82],
	["M 77/85              ", 0.34, 0.575, 0.66, 0.77, 0.85],
	["N 75/84              ", 0.34, 0.575, 0.66, 0.75, 0.84],
	["O 76/83              ", 0.34, 0.575, 0.66, 0.76, 0.83],
]

const SEEDS: int = 16
const GRID: int = 300
const STEP: float = 15.0

const LANE_LEN: float = 20000.0
const LANE_STEP: float = 5.0
const LANES: int = 6


func _initialize() -> void:
	var terrain := Node3D.new()
	terrain.set_script(load(TERRAIN_SCRIPT))

	var totals: Array = []
	for _c in CANDIDATES:
		totals.append([0, 0, 0, 0, 0, 0])   # desert, plains, city, forest, mtn, snow
	var river_hits := 0
	var samples := 0

	for s in SEEDS:
		terrain.call("set_run_seed", hash(Vector3i(s, 991, 7)))
		for ix in GRID:
			for iz in GRID:
				var n: float = terrain.call("_biome_noise", float(ix) * STEP, float(iz) * STEP)
				samples += 1
				if absf(n - 0.5) < 0.007:
					river_hits += 1
				for ci in CANDIDATES.size():
					var c: Array = CANDIDATES[ci]
					var t: Array = totals[ci]
					if n < float(c[1]):
						t[0] += 1
					elif n < float(c[2]):
						t[1] += 1
					elif n < float(c[3]):
						t[2] += 1
					elif n < float(c[4]):
						t[3] += 1
					elif n < float(c[5]):
						t[4] += 1
					else:
						t[5] += 1

	print("samples: %d over %d seeds   river share: %.2f%%" % [samples, SEEDS, 100.0 * float(river_hits) / float(samples)])
	print("%s  desert  plains    city  forest     mtn    snow" % "candidate            ")
	for ci in CANDIDATES.size():
		var c: Array = CANDIDATES[ci]
		var t: Array = totals[ci]
		print("%s %6.2f%% %6.2f%% %6.2f%% %6.2f%% %6.2f%% %6.2f%%" % [
			c[0],
			100.0 * float(t[0]) / float(samples),
			100.0 * float(t[1]) / float(samples),
			100.0 * float(t[2]) / float(samples),
			100.0 * float(t[3]) / float(samples),
			100.0 * float(t[4]) / float(samples),
			100.0 * float(t[5]) / float(samples),
		])

	# --- Cadence: run +X and measure snow-region run lengths + the gap between
	# consecutive snow regions.
	print("")
	for ci in CANDIDATES.size():
		var c: Array = CANDIDATES[ci]
		if float(c[5]) > 1.0:
			continue
		var runs: Array[float] = []
		var gaps: Array[float] = []
		for s in SEEDS:
			terrain.call("set_run_seed", hash(Vector3i(s, 991, 7)))
			for lane in LANES:
				var z := float(lane) * 733.0
				var inside := false
				var run_start := 0.0
				var last_end := -1.0
				var x := 0.0
				while x < LANE_LEN:
					var n: float = terrain.call("_biome_noise", x, z)
					var is_snow: bool = n >= float(c[5])
					if is_snow and not inside:
						inside = true
						run_start = x
						if last_end >= 0.0:
							gaps.append(x - last_end)
					elif not is_snow and inside:
						inside = false
						runs.append(x - run_start)
						last_end = x
					x += LANE_STEP
		print("%s snow regions crossed: %d   run len mean %.0f m median %.0f m   gap mean %.0f m median %.0f m" % [
			c[0], runs.size(), _mean(runs), _median(runs), _mean(gaps), _median(gaps)
		])
	quit(0)


func _mean(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v in a:
		t += v
	return t / float(a.size())


func _median(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[b.size() / 2]
