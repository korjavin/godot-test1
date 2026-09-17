extends SceneTree
"""
COIN ROAD SELFCHECK — choreographed figures on the coin scatter (lfpz).

The road scatter takes a figure every few blocks (slalom / lightning / needle)
with ZERO new RNG draws: `_road_figure()` is a reverse hash lookup on the block
index, and the four station draws (chance, lat, lon, gem) are REINTERPRETED
through it. What each check guards, in check order:

  draw_parity    — per station over -50..600 x 3 seeds, on and off agree on the
                   COUNT and the GEM SEQUENCE. This is the zero-draws proof: a
                   fifth draw anywhere upstream would slide both.
  plain_identical — in NONE blocks the positions are EXACTLY equal on/off.
  bounds         — every on-leg coin stays inside |lat| <= half_band and
                   |lon| <= LONG_JITTER * spacing, measured off the shipped
                   station cache (`_road_station`) and the shipped `_road_width`
                   / `_road_spacing`. Figures never touch the seam pad.
  holdable       — slalom centres move <= 0.6 * spacing between consecutive
                   stations (measured 0.54 worst case); lightning side runs are
                   all >= 3 stations, read off surviving coins' lateral signs
                   against the bead's run rule.
  streak         — per figure block, the largest ALONG-ROAD gap between
                   consecutive surviving coins stays within 1.1x the same
                   block's plain gap. Along-road and not XZ, deliberately:
                   lateral movement IS the figure (slaloms weave, lightning
                   cuts), so an XZ max is dominated by empty-run endpoint phase
                   — seed 900913 fails it 30.9 vs 27.7 on unmutated code —
                   while the lon scatter is what figures promise to tighten
                   (0.35x) and the mutation promises to explode (3.0x). (Also
                   deliberately no absolute 25 m bound: empty stations are a
                   deterministic property of the shipped scatter — seed 11
                   leaves stations 150-153 bare in BOTH legs for a 36 m plain
                   gap no figure-preserving implementation can close, since
                   figures move coins but add none.)
  ids            — `Coin.id_at` is unique over every coin on -50..600, per seed.
  mix            — over 400 blocks every figure occurs and NONE holds 35-65%.
  text           — `_road_coins_at` holds exactly four `rng.randf` call sites
                   (landmark_sites' text-scan idiom): a fifth draw fails here.

The probes call the real `_road_coins_at` through the terrain forwarder on real
(detached, never-in-tree) terrains, the way budapest_selfcheck's road probes do.
Sentinel contract: isolate first, done() last in every check (including before
early returns), finish() at the report site.
"""

const Sentinel = preload("res://scripts/selfcheck_sentinel.gd")
const CoinRoad = preload("res://scripts/coin_road.gd")
const Coin = preload("res://scripts/coin.gd")

const TERRAIN_SCRIPT: String = "res://scripts/endless_terrain.gd"
const COIN_ROAD_SOURCE: String = "res://scripts/coin_road.gd"
const SEEDS: Array[int] = [11, 7331, 900913]
const K_MIN: int = -50
const K_MAX: int = 600
const PAD_TOL: float = 0.0001
const FIGURE_MAX_SLOPE: float = 0.6
const STREAK_RATIO: float = 1.1
const MIX_BLOCKS: int = 400
const MIX_NONE_LO: float = 0.35
const MIX_NONE_HI: float = 0.65

var _failures: Array = []


func _initialize() -> void:
	Sentinel.isolate_user_state()
	_run()


func _run() -> void:
	_check_draw_parity()
	_check_plain_identical()
	_check_bounds()
	_check_holdable()
	_check_streak()
	_check_ids()
	_check_mix()
	_check_text()
	_report()


func _make_terrain(run_seed: int) -> Node3D:
	"""A terrain that never joins the tree, for the checks that only ask it pure
	questions (the road cache). Detached like budapest_selfcheck's, and THE
	CALLER FREES IT."""
	var terrain := Node3D.new()
	terrain.set_script(load(TERRAIN_SCRIPT))
	terrain.set_run_seed(run_seed)
	terrain._road_extend_to_x(-500.0, 4000.0)
	return terrain


func _station_frame(terrain: Node3D, k: int) -> Array:
	"""[center: Vector2, perp: Vector2, tangent: Vector2, half_band, spacing]
	off the shipped station cache and the shipped width/spacing paths."""
	var st: Dictionary = terrain._road_station(k)
	var center: Vector2 = st["center"]
	var heading: float = st["heading"]
	var tangent := Vector2(cos(heading), sin(heading))
	var perp := Vector2(-sin(heading), cos(heading))
	return [center, perp, tangent,
		terrain._road_width(k) * 0.5, terrain._road_spacing()]


func _lateral(terrain: Node3D, k: int, pos: Vector3) -> float:
	var frame: Array = _station_frame(terrain, k)
	var d: Vector2 = Vector2(pos.x, pos.z) - frame[0]
	return d.dot(frame[1])


func _check_draw_parity() -> void:
	for seed: int in SEEDS:
		var terrain := _make_terrain(seed)
		for k in range(K_MIN, K_MAX + 1):
			terrain.road_figures = true
			var shown: Array = terrain._road_coins_at(k)
			terrain.road_figures = false
			var plain: Array = terrain._road_coins_at(k)
			if shown.size() != plain.size():
				_failures.append("draw_parity: seed %d station %d drops %d "
					% [seed, k, shown.size()] + "figured coins against %d plain "
					% plain.size() + "— a draw moved upstream")
				break
			for i in range(shown.size()):
				if bool(shown[i]["gem"]) != bool(plain[i]["gem"]):
					_failures.append("draw_parity: seed %d station %d gem %d "
						% [seed, k, i] + "flipped under figures")
					break
			if not _failures.is_empty():
				break
		terrain.free()
		if not _failures.is_empty():
			break
	Sentinel.done("draw_parity")


func _check_plain_identical() -> void:
	for seed: int in SEEDS:
		var terrain := _make_terrain(seed)
		for k in range(K_MIN, K_MAX + 1):
			if CoinRoad._road_figure(terrain, k) != CoinRoad.FIGURE_NONE:
				continue
			terrain.road_figures = true
			var shown: Array = terrain._road_coins_at(k)
			terrain.road_figures = false
			var plain: Array = terrain._road_coins_at(k)
			for i in range(shown.size()):
				if shown[i]["pos"] != plain[i]["pos"]:
					_failures.append("plain_identical: seed %d station %d coin "
						% [seed, k] + "%d moved in a NONE block" % i)
					break
			if not _failures.is_empty():
				break
		terrain.free()
		if not _failures.is_empty():
			break
	Sentinel.done("plain_identical")


func _check_bounds() -> void:
	for seed: int in SEEDS:
		var terrain := _make_terrain(seed)
		terrain.road_figures = true
		for k in range(K_MIN, K_MAX + 1):
			var frame: Array = _station_frame(terrain, k)
			var lon_cap: float = CoinRoad.ROAD_COIN_LONG_JITTER * frame[4]
			for coin: Dictionary in terrain._road_coins_at(k):
				var d: Vector2 = Vector2(coin["pos"].x, coin["pos"].z) \
					- frame[0]
				if absf(d.dot(frame[1])) > frame[3] + PAD_TOL:
					_failures.append("bounds: seed %d station %d escapes the "
						% [seed, k] + "band laterally")
					break
				if absf(d.dot(frame[2])) > lon_cap + PAD_TOL:
					_failures.append("bounds: seed %d station %d escapes the "
						% [seed, k] + "along-road pad")
					break
			if not _failures.is_empty():
				break
		terrain.free()
		if not _failures.is_empty():
			break
	Sentinel.done("bounds")


func _slalom_centre(terrain: Node3D, k: int, m: int) -> float:
	"""The bead's slalom centre at station `k` (block-relative `m`), off the
	shipped local half band — the quantity the slope bound constrains."""
	return terrain._road_width(k) * 0.5 * CoinRoad.FIGURE_AMPLITUDE \
		* sin(TAU * float(m) / float(CoinRoad.FIGURE_PERIOD))


func _check_holdable() -> void:
	var spacing: float = 0.0
	for seed: int in SEEDS:
		var terrain := _make_terrain(seed)
		if spacing <= 0.0:
			spacing = terrain._road_spacing()
		var first_block: int = CoinRoad._road_block(K_MIN)
		var last_block: int = CoinRoad._road_block(K_MAX)
		for b in range(first_block, last_block + 1):
			var fig: int = CoinRoad._road_figure(
				terrain, b * CoinRoad.FIGURE_BLOCK_STATIONS)
			if fig == CoinRoad.FIGURE_SLALOM:
				for m in range(0, CoinRoad.FIGURE_BLOCK_STATIONS - 1):
					var k: int = b * CoinRoad.FIGURE_BLOCK_STATIONS + m
					if k < K_MIN or k + 1 > K_MAX:
						continue
					var step: float = absf(_slalom_centre(terrain, k + 1, m + 1)
						- _slalom_centre(terrain, k, m))
					if step > FIGURE_MAX_SLOPE * spacing:
						_failures.append("holdable: seed %d slalom centre "
							% seed + "jumps %.2f m at station %d" % [step, k])
						break
			elif fig == CoinRoad.FIGURE_LIGHTNING:
				_check_lightning_runs(terrain, seed, b)
			if not _failures.is_empty():
				break
		terrain.free()
		if not _failures.is_empty():
			break
	Sentinel.done("holdable")


func _check_lightning_runs(terrain: Node3D, seed: int, b: int) -> void:
	"""Every side run inside lightning block `b` holds >= 3 stations. The side
	is READ off surviving coins' lateral signs — the residual can never flip
	one (|0.15| < |0.8| structurally) — against the bead's run rule, so this
	discriminates implementations instead of copying one."""
	terrain.road_figures = true
	for m in range(0, CoinRoad.FIGURE_BLOCK_STATIONS):
		var k: int = b * CoinRoad.FIGURE_BLOCK_STATIONS + m
		if k < K_MIN or k > K_MAX:
			continue
		var run: int = mini(m / CoinRoad.FIGURE_LIGHTNING_RUN, 5)
		var want: float = 1.0 if posmod(run, 2) == 0 else -1.0
		for coin: Dictionary in terrain._road_coins_at(k):
			var lat: float = _lateral(terrain, k, coin["pos"])
			if absf(lat) < 0.000000001:
				continue
			var got: float = 1.0 if lat > 0.0 else -1.0
			if got != want:
				_failures.append("holdable: seed %d lightning block %d "
					% [seed, b] + "station %d on the wrong side" % k)
				return


func _block_gaps(terrain: Node3D, b: int, figures: bool) -> Array:
	"""Largest ALONG-ROAD gap between consecutive surviving coins in block `b`
	(k order), each coin projected on its own station tangent — or -1 when the
	block holds fewer than two coins. Along-road because lateral movement is
	the figure's purpose (asserted bounded in `bounds`/`holdable` instead);
	what the figure owes the streak is concentration along the run."""
	terrain.road_figures = figures
	var pts: Array = []
	for m in range(0, CoinRoad.FIGURE_BLOCK_STATIONS):
		var k: int = b * CoinRoad.FIGURE_BLOCK_STATIONS + m
		if k < K_MIN or k > K_MAX:
			continue
		var frame: Array = _station_frame(terrain, k)
		for coin: Dictionary in terrain._road_coins_at(k):
			var d: Vector2 = Vector2(coin["pos"].x, coin["pos"].z) - frame[0]
			pts.append([k, d.dot(frame[2])])
	pts.sort_custom(func(a: Array, c: Array) -> bool:
		return a[0] < c[0] or (a[0] == c[0] and a[1] < c[1]))
	if pts.size() < 2:
		return [-1.0]
	var worst := 0.0
	for i in range(1, pts.size()):
		worst = maxf(worst, absf(float(pts[i][1]) - float(pts[i - 1][1])))
	return [worst]


func _check_streak() -> void:
	for seed: int in SEEDS:
		var terrain := _make_terrain(seed)
		var first_block: int = CoinRoad._road_block(K_MIN)
		var last_block: int = CoinRoad._road_block(K_MAX)
		for b in range(first_block, last_block + 1):
			if CoinRoad._road_figure(
					terrain, b * CoinRoad.FIGURE_BLOCK_STATIONS) \
					== CoinRoad.FIGURE_NONE:
				continue
			var fig_gap: float = _block_gaps(terrain, b, true)[0]
			if fig_gap < 0.0:
				continue
			var plain_gap: float = _block_gaps(terrain, b, false)[0]
			if plain_gap >= 0.0 and fig_gap > STREAK_RATIO * plain_gap:
				_failures.append("streak: seed %d figure block %d along-road "
					% [seed, b] + "gap %.1f m exceeds 1.1x its plain %.1f m"
					% [fig_gap, plain_gap])
				break
		terrain.free()
		if not _failures.is_empty():
			break
	Sentinel.done("streak")


func _check_ids() -> void:
	for seed: int in SEEDS:
		var terrain := _make_terrain(seed)
		terrain.road_figures = true
		var seen := {}
		for k in range(K_MIN, K_MAX + 1):
			for coin: Dictionary in terrain._road_coins_at(k):
				var id: int = Coin.id_at(coin["pos"])
				if seen.has(id):
					_failures.append("ids: seed %d duplicate coin id at "
						% seed + "station %d" % k)
					break
				seen[id] = true
			if not _failures.is_empty():
				break
		terrain.free()
		if not _failures.is_empty():
			break
	Sentinel.done("ids")


func _check_mix() -> void:
	var terrain := _make_terrain(SEEDS[0])
	var counts := [0, 0, 0, 0]
	for b in range(0, MIX_BLOCKS):
		var fig: int = CoinRoad._road_figure(
			terrain, b * CoinRoad.FIGURE_BLOCK_STATIONS)
		counts[fig] += 1
	terrain.free()
	for f in range(0, 4):
		if counts[f] == 0:
			_failures.append("mix: figure %d never dealt over %d blocks"
				% [f, MIX_BLOCKS])
	var none_share: float = float(counts[CoinRoad.FIGURE_NONE]) \
		/ float(MIX_BLOCKS)
	if none_share < MIX_NONE_LO or none_share > MIX_NONE_HI:
		_failures.append("mix: NONE holds %.0f%% of blocks, want 35-65"
			% (none_share * 100.0))
	Sentinel.done("mix")


func _check_text() -> void:
	var source: String = FileAccess.get_file_as_string(COIN_ROAD_SOURCE)
	if source.is_empty() or not source.contains("ROAD_GEM_CHANCE"):
		_failures.append("text: could not read coin_road.gd — the draw scan "
			+ "would pass vacuously")
		Sentinel.done("text")
		return
	var start: int = source.find("static func _road_coins_at")
	var rest: String = source.substr(start)
	var next_fn: int = rest.find("\nstatic func ", 1)
	var body: String = rest if next_fn < 0 else rest.substr(0, next_fn)
	var draws := 0
	var cursor := 0
	while true:
		cursor = body.find("rng.randf", cursor)
		if cursor < 0:
			break
		draws += 1
		cursor += 1
	if draws != 4:
		_failures.append("text: _road_coins_at holds %d rng.randf call sites, "
			% draws + "want exactly 4 (chance, lat, lon, gem)")
	Sentinel.done("text")


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("FAIL: " + message)


func _checklist() -> Array:
	return ["draw_parity", "plain_identical", "bounds", "holdable", "streak",
		"ids", "mix", "text"]


func _report() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
	else:
		for message: String in _failures:
			printerr("FAIL: " + message)
		printerr("SELFCHECK FAILED (%d)" % _failures.size())
		quit(1)
