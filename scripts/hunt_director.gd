extends Node
## ============================================================================
## HUNT ENCOUNTER DIRECTOR — mercy BEFORE contact, never during it
## ============================================================================
##
## One node in main.tscn, group "hunt_director". The hunt arm in
## `piglet_crocodile_ai.gd` (`_hunt_close_granted()`) asks this node, once per
## escalation edge, whether a hunter that has already smelled the player may
## stop shadowing and walk in. The answer is a bool. That bool is the entire
## output of this file.
##
## ----------------------------------------------------------------------------
## THE HARD RULES (session-02's sharpest design ruling, restated here because
## this is the file that would break it)
## ----------------------------------------------------------------------------
##
##   1. THE DIRECTOR NEVER TOUCHES GRAB RANGE, COLLISION, SPEED, DETECTION, OR
##      ANY VALUE AFTER CONTACT. It owns exactly one verb — "you may begin
##      closing" — and its own bookkeeping. Once a hunter has honestly earned a
##      grab, the grab lands at full cost through the same `hit_by_crocodile()`
##      call a crocodile's bite uses. Nothing in this file can soften that, and
##      nothing added to this file may be allowed to: mercy is tuned in escape
##      routes, approach angles, how many chase at once and cooldowns — NEVER by
##      a hunter visibly pulling its punch. What the player learns from a hunter
##      is mastery, not a tell.
##
##   2. A DENIED HUNTER SHADOWS VISIBLY. Denial routes back through
##      `hunt_steer_point(..., closing = false, ...)`, which parks the unit on
##      its standoff ring. It never despawns, never stands down invisibly, never
##      loses interest. The mercy must be invisible AS MERCY; a robot pacing you
##      at 10 m is the point of the class.
##
##   3. ABSENT DIRECTOR = GRANTED. `_hunt_close_granted()` answers true when
##      nothing is in group "hunt_director", so the standalone
##      `hunter_robot.tscn`, every self-check and every headless harness behave
##      exactly as they did before this file existed. That degrade is DEBUG-ONLY
##      in spirit: with no director there is no cap, no lull and no escape-sector
##      guarantee, and hunters are exempt from the Stink Wave and uncrushable by
##      a giant Teibi, so a shipped scene without this node has removed the
##      hunter class's entire fairness budget. main.tscn carries the node; keep
##      it there.
##
## ----------------------------------------------------------------------------
## SHAPE — modelled on `crocodile_lod_manager.gd`
## ----------------------------------------------------------------------------
## No hard references (group discovery only), a throttled tick (2 Hz — an
## engagement decision is not a per-frame decision), and a PURE DECISION CORE:
## `grant_engagement()` and `escape_sector_open()` are static and pure, so
## `hunt_director_selfcheck.gd` drives the geometry the game ships rather than a
## restatement of it that can drift apart from it. Same discipline as
## `hunt_steer_point`, `pack_steer_point` and `charge_steer_point`.
##
## ----------------------------------------------------------------------------
## MULTIPLAYER — verified, not built. Zero new netcode.
## ----------------------------------------------------------------------------
## Non-master peers drive hunters through `set_remote_state()` and never reach
## the behaviour dispatch, so this node is consulted only where simulation runs.
## The one thing that had to be got right is that the caps are PER QUARRY and
## not global: group "player" is by definition the LOCAL player, so a global cap
## would let two hunters on a teammate 200 m away starve every hunter here. The
## engagement state is therefore a small list of QUARRY BUCKETS, matched by
## proximity (`QUARRY_BUCKET_RADIUS`) rather than by identity — which is what
## lets it work without knowing whether the quarry is the local player, a room
## member, or (headless) nothing at all.
##
## ----------------------------------------------------------------------------
## DETERMINISM — deliberately outside the contract, and needs no RNG
## ----------------------------------------------------------------------------
## Whether a given hunter is engaged is session pacing, exactly like `is_chasing`
## already is; spawn POSITIONS stay deterministic and untouched. The weather /
## fauna precedent. Note this file rolls no dice at all: every rule below is a
## deterministic function of engagement state, so there is not even an RNG to
## keep out of the chunk stream.
##
## PROVISIONAL NUMBERS. The tunables below are held for the predator-density
## epic. They are declared here so that epic has one place to turn; do not tune
## them from inside a hunter bead.

# ============================================================================
# TUNABLES (provisional — see the note above)
# ============================================================================

## RULE 1 — how many hunters may be CLOSING on one quarry at once. Two is a
## pincer you can still run out of; three is a surround. Counted per quarry
## bucket, never globally.
const MAX_PURSUERS: int = 2

## RULE 2 — seconds of denial for a quarry after a grab lands on it, and after a
## hard chase runs past HARD_CHASE_LIMIT. This is the "hunters frighten
## constantly, take almost never" dial: the hunters already engaged keep
## shadowing (hard rule 2 — nobody stands down), but no NEW unit is allowed to
## commit until it expires.
const ENGAGE_LULL: float = 15.0

## RULE 2 — seconds of continuous engagement on one quarry that counts as a hard
## chase and buys the lull above. A pursuit that has run this long has made its
## point; letting fresh hunters keep rotating in past it is how a chase becomes
## a treadmill nobody escapes.
const HARD_CHASE_LIMIT: float = 20.0

## RULE 3 — the guaranteed open escape sector, in radians (90°). A grant is
## denied if it would leave the quarry with no gap at least this wide between
## the bearings of the hunters around it. This is a HARD INVARIANT, not a
## heuristic: hunters are exempt from the Stink Wave and uncrushable by a giant
## Teibi, so this class has no ability-based counterplay at all and the open
## sector IS the counterplay. No instant surround, ever.
const MIN_ESCAPE_SECTOR: float = PI * 0.5

## Two quarries closer together than this share one bucket, and therefore one
## cap and one lull. Comfortably wider than the hunt standoff ring (10 m) so a
## single player cannot be split across two buckets by the ring's own diameter,
## and far under the spacing of teammates who are playing separately.
const QUARRY_BUCKET_RADIUS: float = 12.0

## Seconds between bookkeeping ticks. 2 Hz. Grants are answered synchronously on
## request with live geometry (see `request_hunt_close`), so this tick only ages
## clocks and reaps engagements — none of which needs frame resolution.
const TICK_INTERVAL: float = 0.5


# ============================================================================
# STATE
# ============================================================================

## The engagement state, and the only state this file has. One entry per quarry:
##
##     {
##       "pos":      Vector3  — where that quarry was last seen (y ignored)
##       "hunters":  Array    — the units this director has GRANTED (rule 1)
##       "lull":     float    — seconds of denial left on it (rule 2)
##       "engaged":  float    — seconds of continuous engagement so far (rule 2)
##     }
##
## A plain Array of plain Dictionaries, the same shape as `SPECIES` and
## `SKILL_TREES`: there is at most a handful of these, so a linear scan matched
## by proximity is cheaper and clearer than any keyed structure — and a key would
## have to be an identity this director deliberately does not have (see the
## multiplayer note in the header).
var _buckets: Array[Dictionary] = []

## Seconds until the next bookkeeping tick.
var _time_until_tick: float = 0.0

## Lifetime counts, public and monotone purely so a self-check (or a future perf
## overlay row) can confirm this node is actually deciding rather than silently
## idle — the same polling discipline as `lod_scans_total`. Never a signal.
var grants_total: int = 0
var denials_total: int = 0


# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Group-based discovery, as everywhere else. `_hunt_close_granted()` finds us
	# through exactly this group and through nothing else.
	add_to_group("hunt_director")


func _process(delta: float) -> void:
	_time_until_tick -= delta
	if _time_until_tick > 0.0:
		return
	# Age by the interval PLUS whatever this frame overshot it (`_time_until_tick`
	# is <= 0 here, so this adds the overshoot), never by `delta` alone: these are
	# wall-clock lulls and a 15 s lull must stay 15 s long at any frame rate and
	# across a frame that ran long.
	var elapsed: float = TICK_INTERVAL - _time_until_tick
	_time_until_tick = TICK_INTERVAL
	_tick(elapsed)


# ============================================================================
# THE PURE DECISION CORE
# ============================================================================
# Static, pure, and free of any node reference on purpose: hunt_director_selfcheck
# drives THESE functions, so the rules it measures are the rules the game ships.
# Everything above and below them is bookkeeping that decides what to feed them.

static func grant_engagement(bearings: PackedFloat32Array, closing_count: int,
		lull_left: float, candidate_bearing: float) -> bool:
	"""
	The whole decision, as one pure function of engagement state. All three rules.

	    rule 1  closing_count      — units already CLOSING on this quarry
	    rule 2  lull_left          — seconds of post-grab / post-hard-chase denial
	    rule 3  bearings           — quarry -> every hunter ON this quarry
	            candidate_bearing  — quarry -> the unit asking

	WHY THE TWO SETS ARE DIFFERENT, and it is load-bearing: the CAP counts only
	the units this director has granted, because "how many chase at once" is a
	statement about committed pursuers. The SECTOR counts every hunter standing
	on the quarry, shadowing ones included, because a robot pacing you at 10 m is
	just as much a body between you and open ground as one walking in — and the
	acceptance criterion is "you can always run out through a gap", which is a
	claim about the gap in the RING, not about the gap between the two closers.
	Feeding the sector rule only the granted set would make it VACUOUS at
	MAX_PURSUERS = 2 (two bearings always leave 180° between them), and a rule
	that cannot deny has measured nothing.

	@param bearings: radians, quarry -> each hunter already on this quarry
	@param closing_count: units this director has already granted on this quarry
	@param lull_left: seconds of denial left on this quarry (0 or less = none)
	@param candidate_bearing: radians, quarry -> the unit asking to close
	@return true if this unit may escalate from shadowing to closing
	"""
	# RULE 1 — the pursuer cap.
	if closing_count >= MAX_PURSUERS:
		return false
	# RULE 2 — the lull.
	if lull_left > 0.0:
		return false
	# RULE 3 — the escape-sector guarantee.
	return escape_sector_open(bearings, candidate_bearing)


static func escape_sector_open(bearings: PackedFloat32Array,
		candidate_bearing: float) -> bool:
	"""
	Would adding `candidate_bearing` still leave the quarry an open escape sector?

	Pure geometry over bearings measured FROM THE QUARRY. Sort the whole set
	(existing plus candidate) around the circle and take the widest gap between
	neighbours, wrapping; the answer is whether that gap is at least
	MIN_ESCAPE_SECTOR wide. Nothing else — no distances, no speeds, no memory.

	STATIC AND PURE for the reason `hunt_steer_point` is: the self-check drives
	this function directly with adversarial bearing sets, so the invariant it
	proves is the invariant the game enforces rather than a copy of it.

	Degenerate cases answer the merciful way, which is the direction this class
	is allowed to err in: no existing bearings at all is one lone hunter with the
	whole 360° open, and it is granted.

	@param bearings: radians, quarry -> each hunter already on this quarry
	@param candidate_bearing: radians, quarry -> the unit asking to close
	@return true when the widest neighbour gap is >= MIN_ESCAPE_SECTOR
	"""
	# Normalise into [0, TAU) before sorting: callers get their bearings from
	# atan2, which returns (-PI, PI], and a raw sort of mixed signs would put the
	# wrap in the wrong place and compute gaps that do not exist.
	var ring := PackedFloat32Array()
	for b: float in bearings:
		ring.append(fposmod(b, TAU))
	ring.append(fposmod(candidate_bearing, TAU))
	ring.sort()

	var widest: float = 0.0
	var n: int = ring.size()
	for i: int in range(n):
		# The last entry's neighbour is the first one, one turn around.
		var gap: float = ring[(i + 1) % n] - ring[i]
		if i == n - 1:
			gap += TAU
		widest = maxf(widest, gap)
	return widest >= MIN_ESCAPE_SECTOR


# ============================================================================
# THE PUBLIC API — what the hunt arm calls
# ============================================================================

func request_hunt_close(hunter: Node) -> bool:
	"""
	The seam. `_hunt_close_granted()` calls exactly this, once per escalation edge.

	Answered SYNCHRONOUSLY off live geometry rather than off the tick's snapshot,
	because a grant is rare (one per engagement) and its geometry is the thing
	being judged — a half-second-stale ring is a half-second-stale fairness
	guarantee.

	Degrades to a GRANT on anything it cannot measure — a hunter that is not a
	Node3D, one with no `chase_target` — for the same reason the absent director
	grants: the absence of information about an encounter is never a reason to
	freeze a unit on its ring forever.

	@param hunter: the unit asking (a PigletCrocodile on the hunt arm)
	@return true if it may begin closing
	"""
	if not is_instance_valid(hunter) or not (hunter is Node3D):
		grants_total += 1
		return true
	var body := hunter as Node3D
	# `chase_target` is whatever `_update_chase_state` resolved THIS frame — in a
	# room, the nearest room member — and the hunt arm asks us before it bends
	# that point through `hunt_steer_point`, so this really is the quarry and not
	# the ring point. Guarded like every other cross-system read in this project.
	if not ("chase_target" in body):
		grants_total += 1
		return true
	var quarry: Vector3 = body.chase_target

	var bucket: Dictionary = _bucket_for(quarry)
	_reap(bucket)

	# Already granted and still closing: idempotent yes. The arm latches its
	# answer so this should not happen, but a re-ask must never cost a second cap
	# slot.
	var closers: Array = bucket["hunters"]
	if closers.has(body):
		return true

	# RULE 3's input: every hunter standing on this quarry, shadowing ones
	# included (see grant_engagement's docstring for why), minus the asker.
	var bearings := _bearings_around(quarry, body)
	var candidate := _bearing_from(quarry, body.global_position)

	if not grant_engagement(bearings, closers.size(), float(bucket["lull"]),
			candidate):
		denials_total += 1
		return false

	closers.append(body)
	grants_total += 1
	return true


func report_grab(hunter: Node) -> void:
	"""
	A retrieval landed. Drop the unit and put the quarry into its lull (rule 2).

	This is the pacing verb, and it paces the NEXT engagement only — the grab it
	is told about has already been paid in full by the ordinary collision path
	before anything here runs. See hard rule 1.

	The unit that grabbed is removed from the cap: the arm has already put
	`hunt_disengage_time` on its own clock and dropped it back to the standoff
	ring, so holding a cap slot for a robot that is walking away would spend the
	encounter's whole pursuer budget on nothing. It re-asks when its clock
	expires and is judged fresh — against the lull this call just started.
	"""
	if not is_instance_valid(hunter) or not (hunter is Node3D):
		return
	var bucket: Dictionary = _bucket_for(_quarry_of(hunter as Node3D))
	(bucket["hunters"] as Array).erase(hunter)
	bucket["lull"] = ENGAGE_LULL
	bucket["engaged"] = 0.0


func report_disengage(hunter: Node) -> void:
	"""
	A unit stopped closing for a reason that is NOT a grab (it lost the quarry,
	was slept by the LOD manager, or was freed with its chunk). Give the cap slot
	back, and start no lull — nothing was taken, so nothing is owed.

	Swept across every bucket rather than looked up by position: a unit that has
	lost its quarry no longer has a `chase_target` worth trusting, so the only
	reliable way to find its slot is to look everywhere. There are a handful of
	buckets holding at most MAX_PURSUERS each.
	"""
	if hunter == null:
		return
	for bucket: Dictionary in _buckets:
		(bucket["hunters"] as Array).erase(hunter)


# ============================================================================
# BOOKKEEPING
# ============================================================================

func _tick(elapsed: float) -> void:
	## Age the clocks, follow the quarries, reap finished engagements, and drop
	## buckets that have nothing left to remember. Everything here is state the
	## grant decision reads; none of it IS the decision.
	var focus := _focus_points()

	for i: int in range(_buckets.size() - 1, -1, -1):
		var bucket: Dictionary = _buckets[i]

		# FOLLOW THE QUARRY. A bucket whose hunters have all withdrawn (the state
		# a grab leaves it in) still owns a lull, and that lull has to travel with
		# the player — otherwise running 20 m outruns the mercy as well as the
		# robot, and the post-grab lull the acceptance criteria ask you to FEEL
		# would only be felt by a player who stood still. Snapped to the nearest
		# known member position, and left alone when none is near (headless
		# harnesses have no player at all).
		var nearest: Vector3 = _nearest_point(focus, bucket["pos"])
		if nearest.is_finite():
			bucket["pos"] = nearest

		_reap(bucket)

		bucket["lull"] = maxf(float(bucket["lull"]) - elapsed, 0.0)

		var closers: Array = bucket["hunters"]
		if closers.is_empty():
			# Continuous engagement means continuous. A quarry that shook everyone
			# off starts its next chase from zero.
			bucket["engaged"] = 0.0
		else:
			bucket["engaged"] = float(bucket["engaged"]) + elapsed
			if float(bucket["engaged"]) >= HARD_CHASE_LIMIT:
				# RULE 2, second half: this pursuit has made its point. The units
				# already closing are NOT called off (hard rule 2 — nobody stands
				# down invisibly, and the arm latches its grant anyway), but the
				# next hunter to ask is refused until the lull expires.
				bucket["lull"] = ENGAGE_LULL
				bucket["engaged"] = 0.0

		if closers.is_empty() and float(bucket["lull"]) <= 0.0:
			_buckets.remove_at(i)


func _reap(bucket: Dictionary) -> void:
	## Drop every granted unit that is no longer closing, routing each drop
	## through the rule that fits it — which is what makes the grab lull and the
	## plain slot-return live bookkeeping rather than API nobody exercises.
	##
	## HOW A GRAB IS SEEN. The hunt arm owns one dictionary, `_hunt_lock`, and the
	## bite path writes `disengage` into it — that write is the ONLY signal a
	## retrieval landed, and there is no other observable difference between "it
	## took you and withdrew" and "it lost you". So a unit that has dropped out of
	## `closing` with time left on `disengage` is counted as a grab, and
	## everything else as a plain disengage.
	##
	## ponytail: reading another script's underscore-prefixed dictionary is the
	## price of the arm being frozen (it shipped in the previous bead and this one
	## must not edit it). Guarded at every step, so a rename over there degrades
	## to "no grabs are ever detected" — merciful, never a crash. The upgrade path
	## is one line in that bite path calling `report_grab(self)`, at which point
	## this function keeps only the lost-the-quarry half.
	var closers: Array = bucket["hunters"]
	for i: int in range(closers.size() - 1, -1, -1):
		var unit: Variant = closers[i]
		if not is_instance_valid(unit):
			closers.remove_at(i)
			continue
		var lock: Variant = unit.get("_hunt_lock") if ("_hunt_lock" in unit) else null
		if lock is Dictionary and bool((lock as Dictionary).get("closing", false)):
			continue
		closers.remove_at(i)
		if lock is Dictionary and float((lock as Dictionary).get("disengage", 0.0)) > 0.0:
			bucket["lull"] = ENGAGE_LULL
			bucket["engaged"] = 0.0


func _bucket_for(quarry: Vector3) -> Dictionary:
	## The nearest bucket within QUARRY_BUCKET_RADIUS of this quarry, created if
	## there is none. Proximity rather than identity — see the multiplayer note in
	## the header. Flat distance: two players at different heights over the same
	## spot are the same encounter, and the world is flat at y = 0 anyway.
	var best: Dictionary = {}
	var best_d: float = QUARRY_BUCKET_RADIUS * QUARRY_BUCKET_RADIUS
	for bucket: Dictionary in _buckets:
		var d: float = _flat_dist_sq(bucket["pos"], quarry)
		if d <= best_d:
			best_d = d
			best = bucket
	if not best.is_empty():
		best["pos"] = quarry
		return best
	var fresh: Dictionary = {
		"pos": quarry, "hunters": [], "lull": 0.0, "engaged": 0.0,
	}
	_buckets.append(fresh)
	return fresh


func _bearings_around(quarry: Vector3, asker: Node3D) -> PackedFloat32Array:
	## Bearings from `quarry` to every hunter currently chasing it, excluding the
	## unit doing the asking. Group-scanned live: hunters are rare (one per few
	## chunks) and this runs once per escalation, so the scan is far cheaper than
	## a registry that could go stale — and it needs no cooperation at all from
	## the hunter script, which this bead must not edit.
	var out := PackedFloat32Array()
	var radius_sq: float = QUARRY_BUCKET_RADIUS * QUARRY_BUCKET_RADIUS
	for unit: Node in get_tree().get_nodes_in_group("crocodile"):
		if unit == asker or not is_instance_valid(unit) or not (unit is Node3D):
			continue
		# Defensive membership reads, the same style as the LOD manager's: a group
		# member that is not a hunt-arm predator is simply not our business.
		if not ("spec" in unit) or not ("is_chasing" in unit) or not ("chase_target" in unit):
			continue
		if not unit.is_chasing:
			continue
		var row: Variant = unit.spec
		if not (row is Dictionary) or (row as Dictionary).get("behavior", "") != "hunt":
			continue
		var body := unit as Node3D
		# Only hunters on THIS quarry. A hunter chasing a teammate across the map
		# is not standing between this player and open ground.
		if _flat_dist_sq(body.chase_target, quarry) > radius_sq:
			continue
		out.append(_bearing_from(quarry, body.global_position))
	return out


func _focus_points() -> Array[Vector3]:
	## Every position that could be a quarry: the local player plus, in a room,
	## the other members. Exactly the set `crocodile_lod_manager` builds, for
	## exactly the same reason — group "player" is the LOCAL player, so on its own
	## it would strand a teammate's bucket. Null-safe: a scene with neither (every
	## headless harness) yields an empty array and the buckets simply stop being
	## snapped.
	var out: Array[Vector3] = []
	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D:
		out.append((player as Node3D).global_position)
	var mp := get_tree().get_first_node_in_group("mp")
	if mp != null and mp.has_method("peer_positions"):
		var remotes: Variant = mp.peer_positions()
		if remotes is Array:
			for p: Variant in remotes:
				if p is Vector3:
					out.append(p)
	return out


func _quarry_of(hunter: Node3D) -> Vector3:
	## Where this unit thinks its quarry is, falling back to its own position when
	## it cannot say — which buckets it near itself rather than at the origin,
	## where it would collide with every other unknown.
	if "chase_target" in hunter:
		return hunter.chase_target
	return hunter.global_position


static func _nearest_point(points: Array[Vector3], to: Vector3) -> Vector3:
	## The closest of `points` to `to` within QUARRY_BUCKET_RADIUS, or an infinite
	## vector when there is none — `is_finite()` is the caller's "no answer" test,
	## which keeps this a plain value rather than a nullable.
	var best := Vector3.INF
	var best_d: float = QUARRY_BUCKET_RADIUS * QUARRY_BUCKET_RADIUS
	for p: Vector3 in points:
		var d: float = _flat_dist_sq(p, to)
		if d <= best_d:
			best_d = d
			best = p
	return best


static func _bearing_from(quarry: Vector3, unit: Vector3) -> float:
	## Flat bearing, quarry -> unit, in radians. Flat because the world is flat.
	return atan2(unit.z - quarry.z, unit.x - quarry.x)


static func _flat_dist_sq(a: Vector3, b: Vector3) -> float:
	## Squared XZ distance — no sqrt, and y deliberately ignored (see _bucket_for).
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return dx * dx + dz * dz
