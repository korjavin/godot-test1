class_name CrocSteering
extends RefCounted
## THE PREDATORS' PURE STEERING BLOCK — where a unit AIMS and WHEN it commits,
## lifted whole out of `piglet_crocodile_ai.gd` (bd godot-test1-ftn.16).
##
## THE SPLIT, and why it falls exactly here. The BODY keeps everything that has
## state: the `_behave_*` arms, which read and write `chase_target`, `_hunt_lock`,
## `is_chasing`, `burst_factor`, `velocity` and a dozen more instance vars, and
## the whole of `_update_chase_state`'s detection decision above them. This file
## keeps the eight functions that have NONE — every one takes its quarry, its
## position, its lock Dictionary and its `SPECIES` row as explicit arguments and
## answers a point, a number or a bool. That is the one clean seam in the file:
## an arm re-homed here would be a `croc.`-prefixed copy of itself, ~380 lines
## longer for a worse read (measured 2026-09-05), so the arms did not move.
##
## IT IS ALSO WHY THE SELF-CHECK CAN SEE ANY OF THIS. `enemy_behavior_selfcheck`
## drives all eight statically, with no body in the tree — the pack surround, the
## charge sidestep, the burst and leap races, the ranged cadence and the hunt ring
## are measurements rather than claims precisely because these are pure. Keep them
## pure: a function here that reached for an instance var would take the whole
## behaviour suite down to "instantiate a crocodile and hope".
##
## `PACK_FLANK_TAPER` came with `pack_steer_point()` because it is the only thing
## that reads it, and is aliased back on the body so
## `get_script_constant_map()["PACK_FLANK_TAPER"]` still answers. Every OTHER
## constant these functions mention — `MAX_CHASE_SPEED`, `BOSS_CHASE_SPEED`,
## `GRAVITY`, `CROC_REMOTE_MAX_SPEED` — is mentioned in a DOCSTRING only and
## stays on the body, where the code that reads it lives.
##
## IT IS A MOVE AND NOTHING ELSE. Every rule, every measured number and every
## comment below arrived unchanged; the arms' call sites gained the `CrocSteering.`
## prefix and nothing else changed.


# ----- Pack steering (behavior == "pack") -----
## How much of the remaining distance to the quarry the flank offset is allowed
## to be. It is the ONE number that decides whether a ring is a flank or an
## orbit, and it is a property of the algorithm rather than of any animal, which
## is why it sits here and not in a SPECIES row.
##
## WHAT IT ACTUALLY CONTROLS IS A LEAD ANGLE. pack_steer_point() aims at a point
## `ring` metres to one side of the quarry, where ring = min(flank_radius,
## d * TAPER); once d is inside the flank ceiling, that is a target sitting at a
## CONSTANT angle atan(TAPER) = 37° off the straight line in. A pursuer holding a
## constant lead angle walks a logarithmic spiral, and the arc it sweeps closing
## from d0 to d1 is exactly tan(TAPER's angle) * ln(d0 / d1) — 0.75 * ln(16/3) =
## 68° each way for a wolf committing at 16 m, which is the ~136° of surround
## enemy_spawn_selfcheck measures out of a pack that all started on one bearing.
## Turning this up widens the spiral; the two things that stop it are below.
##
## IT MUST STAY STRICTLY BELOW 1.0, and 1.0 is not a rounding but a singularity.
## A wolf already ON its slot bearing at distance d is handed the target
## quarry + d * TAPER * u, which at TAPER = 1.0 is the point it is standing on:
## every point of its own slot ray becomes a fixed point and the pack freezes in
## a ring around a player who can then stroll away. Below 1.0 the same wolf is
## handed a point d * (1 - TAPER) in front of it and always has somewhere to
## walk; its radial closing rate is v / sqrt(1 + TAPER^2), positive for any
## finite value.
##
## AND THAT RATE IS THE REAL CEILING, because it is the walk-catch contract in
## disguise. At 0.75 a wolf spends cos(37°) = 0.80 of its speed actually closing:
## 6.8 * 0.80 = 5.44 m/s toward you, which is the crocodile's 5.5 almost exactly.
## THAT is the number the wolf's chase_speed was chosen to land on — the extra
## 1.3 m/s over a crocodile is the fare for the angle, not a faster catch. Push
## TAPER to 0.85 and the same wolf closes at 5.18, a hair over WALK_SPEED (5.0),
## and the species quietly stops being able to catch a walking player at all.
const PACK_FLANK_TAPER: float = 0.75


static func hunt_steer_point(quarry: Vector3, from: Vector3, closing: bool,
		standoff: float) -> Vector3:
	"""
	Where one hunter steers: at the quarry when closing, at the RING when not.

	    closing    -> quarry                       (walk in and take it)
	    shadowing  -> quarry + standoff * away     (hold the ring, either way)

	`away` is the flat unit vector FROM the quarry TO this unit, so the one
	expression covers both halves of shadowing with no branch: a hunter outside
	the ring walks in to it, and one inside the ring — the state a grab leaves it
	in, standing on top of the player — walks OUT to it. That is what makes
	"withdraw after the grab" and "pace before the grab" the same line of code,
	and it is why the disengage needs no geometry of its own.

	STATIC AND PURE for the same reason `pack_steer_point`, `charge_steer_point`
	and `burst_cycle_factor` are: enemy_spawn_selfcheck's shadow/close probe
	drives THIS function, so the ring it measures is the ring the game ships
	rather than a restatement of it that can drift apart from it.

	Three properties follow from that, each a requirement rather than an accident:

	  * LOD-SAFE. It has no memory at all — no lock, no integrator, no phase. A
	    waking hunter recomputes the identical point from where it is standing
	    now, so the first frame back is the frame it would have produced had it
	    never slept. (The arm's two timers are the part with memory, and the note
	    on `_hunt_lock` covers those.)
	  * MULTIPLAYER-SAFE. `quarry` is whatever _update_chase_state resolved, which
	    in a room is the nearest ROOM MEMBER. This only bends that point; it can
	    neither widen who is hunted nor reach past the detection radius.
	  * SPEED-LATTICE-SAFE. It returns a POINT. Nothing here touches
	    `chase_speed_instance`, which _ready() already clamped to MAX_CHASE_SPEED.
	    A hunter is frightening because it commits and does not stop, never
	    because it is fast; running escapes it in every phase.

	@param quarry: where the chase currently wants to go
	@param from: this hunter's own position
	@param closing: true once the telegraph is spent and the director has granted
	@param standoff: metres of ring to hold while shadowing (the row's hunt_standoff)
	@return the point to steer at this frame

	A standoff of zero or less answers `quarry` — a hunter with no ring is an
	ordinary chaser rather than a body dividing by zero — as does standing exactly
	on the quarry, where there is no bearing to hold a ring on. Same
	degrade-don't-crash rule as everywhere else in this file.
	"""
	if closing or standoff <= 0.0:
		return quarry
	var away := from - quarry
	away.y = 0.0
	if away.length() < 0.01:
		return quarry
	return quarry + away.normalized() * standoff


static func ranged_shot_due(distance: float, delta: float, lock: Dictionary,
		row: Dictionary) -> bool:
	"""
	May a ranged predator release a shot this frame? Advances its cooldown.

	    each frame  cooldown -= delta            (always, even out of band)
	    fire when   cooldown <= 0 AND min_fire_range <= distance <= max_fire_range
	    on firing   cooldown := fire_cooldown

	@param distance: flat distance from the shooter to its quarry, metres
	@param delta: seconds since the last call (the physics tick)
	@param lock: this shooter's `_ranged_lock`, MUTATED here. Empty = ready now.
	@param row: the species row's "ranged" dict
	@return true exactly on the frames a shot should be launched

	STATIC AND PURE for the same reason `burst_cycle_factor` and
	`pack_steer_point` are: enemy_spawn_selfcheck's cadence probe drives THIS
	function, so the measured cadence is the shipped cadence and not a
	restatement of it that can drift.

	THE COOLDOWN TICKS EVEN WHILE OUT OF BAND, which is a decision and not an
	accident: an archer that had to stand still for its full cooldown after you
	stepped out of range and back in would reward yo-yoing across the 10 m floor,
	and the floor exists to make closing the distance the counterplay rather than
	a way to disarm the boss for three seconds. It never accumulates CREDIT —
	the clamp at zero means the longest wait is one full cooldown and the reward
	for a long walk between engagements is one immediate shot, not five.
	"""
	var left: float = float(lock.get("cooldown", 0.0)) - delta
	lock["cooldown"] = maxf(left, 0.0)
	if distance < float(row["min_fire_range"]) or distance > float(row["max_fire_range"]):
		return false
	if left > 0.0:
		return false
	lock["cooldown"] = float(row["fire_cooldown"])
	return true


static func leap_airtime(row: Dictionary) -> float:
	"""
	How long one hop keeps a body off the ground, in seconds.

	    t = 2 * leap_launch_speed / leap_gravity

	The whole of a symmetric ballistic arc: up at `leap_launch_speed`, down under
	`leap_gravity` (the row's own, not the file's GRAVITY — see `_behave_leap`),
	back to the flat world's y = 0. The apex it implies is
	`leap_launch_speed^2 / (2 * leap_gravity)`, which is the number to tune a
	silhouette against.

	@param row: the species row, for the two arc keys
	@return the airtime in seconds, or 0.0 for a row that cannot hop

	A row missing either key answers 0.0 — which makes `leap_reach()` zero and
	`leap_due()` refuse — so a half-finished species degrades to an ordinary
	ground chase instead of dividing by zero. The same degrade-don't-crash rule as
	`burst_cycle_factor`'s missing-distance answer and the unknown-behaviour
	fallback in the dispatch.
	"""
	var launch: float = float(row.get("leap_launch_speed", 0.0))
	var arc_gravity: float = float(row.get("leap_gravity", 0.0))
	if launch <= 0.0 or arc_gravity <= 0.0:
		return 0.0
	return 2.0 * launch / arc_gravity


static func leap_reach(chase_speed: float, row: Dictionary) -> float:
	"""
	How far one hop carries a body across the ground, in metres.

	    reach = leap_airtime(row) * chase_speed * leap_speed_factor

	@param chase_speed: the body's RESOLVED chase speed (already clamped to
	                    MAX_CHASE_SPEED by _ready(); a boss's is BOSS_CHASE_SPEED
	                    scaled by the distance gradient and clamped)
	@param row: the species row
	@return the ground distance the arc covers

	STATIC AND PURE for the reason every helper in this block is: the arm projects
	its landing point with this, and enemy_spawn_selfcheck's leap probe measures
	the cycle with it, so the reach the leash is asked about is the reach that
	ships. It is the horizontal leg of the same arc `leap_airtime` describes,
	assuming the body holds its heading for the hop — which is the OUTERMOST
	landing the leash's steer can produce and therefore the conservative one to
	test a fence against.
	"""
	return leap_airtime(row) * chase_speed * float(row.get("leap_speed_factor", 1.0))


static func leap_due(grounded: bool, landing_ok: bool, delta: float, lock: Dictionary,
		row: Dictionary) -> bool:
	"""
	May a leaping predator launch this frame? Advances its GROUNDED recovery clock.

	    airborne     never (and the clock does not tick — the arc is not recovery)
	    each grounded frame  cooldown -= delta
	    hop when     cooldown <= 0 AND the projected landing is legal
	    on hopping   cooldown := leap_cooldown

	@param grounded: is_on_floor() — the arc runs itself, this only starts one
	@param landing_ok: has the caller's `in_territory()` accepted the landing point
	@param delta: seconds since the last call (the physics tick)
	@param lock: this body's `_leap_lock`, MUTATED here. Empty = ready now.
	@param row: its SPECIES row, for the arc and cooldown keys
	@return true exactly on the frames a launch should happen

	STATIC AND PURE for the same reason `ranged_shot_due` and `burst_cycle_factor`
	are: enemy_spawn_selfcheck's leap probe drives THIS function, so the measured
	cadence and the measured cycle average are the shipped ones and not a
	restatement that can drift.

	THE CLOCK DOES NOT TICK IN THE AIR, unlike the archer's, and that is the
	opposite decision made for the opposite reason. An archer's cooldown ticks even
	out of band so that stepping in and out of range cannot disarm it; a hop's
	recovery is the PRICE of the hop, so letting the airtime pay part of it would
	shorten the recovery leg the escape guarantee is balanced on. `leap_cooldown`
	therefore means exactly "seconds on the ground between one landing and the next
	launch", which is what the probe's cycle arithmetic assumes.

	A REFUSED LANDING COSTS NOTHING. The clock still drains (a boss pinned at its
	fence is not also made to wait) but it is not re-armed, so the hop happens on
	the first frame the leash allows one. It never accumulates credit either — the
	clamp at zero means the longest wait is one full cooldown.
	"""
	if leap_airtime(row) <= 0.0:
		return false
	if not grounded:
		return false
	var left: float = float(lock.get("cooldown", 0.0)) - delta
	lock["cooldown"] = maxf(left, 0.0)
	if left > 0.0 or not landing_ok:
		return false
	lock["cooldown"] = float(row["leap_cooldown"])
	return true


static func burst_cycle_factor(from: Vector3, lock: Dictionary, row: Dictionary) -> float:
	"""
	Which leg of the burst cycle this animal is on, as a speed multiplier.

	    each frame  travelled += |from - lock.last|   (PATH LENGTH, see below)
	    flip when   travelled >= (burst_distance if bursting else recover_distance)
	    on flip     bursting := not bursting, travelled := 0
	    factor      burst_factor while bursting, recover_factor while recovering

	THE CYCLE IS MEASURED IN METRES, NOT SECONDS, and that is the same call
	`charge_steer_point` makes for the same two reasons. `_update_chase_state` has
	no `delta` (see the note on the dispatch), so a timer would have had to be
	plumbed through every arm to serve one of them — and a distance is LOD-SAFE
	for free: a slept predator does not move, so its leg does not drain, and it
	wakes on the leg it slept on. A seconds-based cycle would have run down during
	the sleep and handed the player a cougar that arrives already exhausted, or
	one whose pounce was spent 40 m away where nobody could see it.

	THE METRES ARE PATH LENGTH, NOT DISPLACEMENT FROM WHERE THE LEG STARTED, and
	that distinction is the whole correctness of this function rather than a
	refinement of it. The bear's `charge_steer_point` measures displacement from
	its lock origin, which is right for a bear: what it is asking is "how far have
	I got from where I took aim". Ask a BURST the same question and a predator
	that never gets far from its starting point never finishes its pounce — a
	cougar steered around a massif, or one following a player who circles it
	inside a four-metre radius, stays inside `burst_distance` of its origin
	forever and therefore runs at 11 m/s indefinitely, which is precisely the
	promise this whole species was built to keep. Path length has no such hole:
	every metre the animal actually covers is a metre of pounce spent, whatever
	shape it covered it in. It also gives the pinned-against-a-block case the
	physically honest answer for free — a body that is not moving is not spending
	its burst, and it resumes with the metres it had left.

	Three properties follow from it being a pure function of the lock, and each
	one was a requirement rather than a happy accident:

	  * LOD-SAFE, as above, with no timer to have drained.
	  * MULTIPLAYER-SAFE. It reads only this body's own position and its own lock,
	    and returns a scalar. A remote-driven predator never runs the arm at all —
	    it renders the master's samples, and CROC_REMOTE_MAX_SPEED (40.0) is
	    comfortably above any burst — so there is no second simulation to
	    disagree and no new byte on the wire.
	  * LATTICE-SAFE OVER THE CYCLE, WHICH IS THE ONLY SENSE THAT MATTERS. The
	    factor multiplies `chase_speed_instance`, which _ready() already clamped to
	    MAX_CHASE_SPEED, so the burst is an explicit, auditable multiple of the
	    ceiling rather than an unbounded speed. `burst_factor` is above 1.0 and
	    `recover_factor` below it, and the two legs together average out under the
	    slowest run and over the walk — measured, not asserted, in check 8.

	@param from: this animal's own position
	@param lock: its cycle state, MUTATED here — { "bursting", "origin" }
	@param row: its SPECIES row, for the four burst_* keys
	@return the multiplier to apply to chase_speed_instance this frame

	A row missing either distance answers 1.0 — an ordinary chase — so a
	half-finished species degrades to a crocodile instead of dividing by zero.
	That is the same degrade-don't-crash rule as the unknown-species fallback in
	_ready() and the unknown-behaviour fallback in the dispatch.

	ponytail: a predator pinned against a block covers no path, so it does not
	advance its leg and resumes with the metres it had left. That is the right
	answer rather than a shortcut — a pounce is metres of ground covered, and a
	cat shouldering into stone has covered none of them. The one visible
	consequence is that it comes round the corner still on the leg it arrived on,
	which reads as a cat coiled at the corner. The upgrade path, if it ever
	matters, is the bear's: flip the leg on a blocked feeler.
	"""
	var burst_distance: float = float(row.get("burst_distance", 0.0))
	var recover_distance: float = float(row.get("recover_distance", 0.0))
	if burst_distance <= 0.0 or recover_distance <= 0.0:
		return 1.0

	if not lock.has("last"):
		lock["last"] = from
		lock["travelled"] = 0.0
		lock["bursting"] = true
	# Path length, one frame at a time — see the docstring for why this is not
	# `from.distance_to(origin)`. The step is the ground this body actually
	# covered since the last frame it was chasing, so a curve spends its pounce
	# at the same rate a straight line does.
	var travelled: float = float(lock["travelled"]) + from.distance_to(lock["last"])
	lock["last"] = from
	var bursting: bool = bool(lock["bursting"])
	var leg: float = burst_distance if bursting else recover_distance
	if travelled >= leg:
		bursting = not bursting
		lock["bursting"] = bursting
		travelled = 0.0
	lock["travelled"] = travelled
	return float(row["burst_factor"]) if bursting else float(row["recover_factor"])


static func charge_steer_point(quarry: Vector3, from: Vector3, lock: Dictionary,
		commit: float) -> Vector3:
	"""
	Where one heavy charger steers, given its own position and its own lock.

	    re-lock when   dir is unset OR |from - lock.origin| >= commit
	    on re-lock     dir := bearing to the quarry, origin := here
	    point          from + dir        (one metre along the committed bearing)

	THE BEHAVIOUR IS THE STALENESS. Every other predator in this game recomputes
	its heading from the quarry's CURRENT position every frame, so it curves onto
	you and a sidestep only ever buys the width of the curve. This one takes that
	reading once and then spends `commit` metres refusing to take another, so a
	sidestep during those metres is not a curve to be out-turned — the bear is
	aiming at a place you are simply not standing any more. That is the entire
	counterplay, and it is why the dodge works at a WALK against an animal faster
	than a walk. enemy_spawn_selfcheck measures it against the same bear with this
	function switched off, because "the player dodged" is also true of a bear that
	merely turns slowly.

	IT RETURNS A POINT ONE METRE AHEAD, not a distant aim point, and the metre is
	arbitrary in the only way that matters: `_chase_player` normalizes
	`chase_target - global_position`, so any positive multiple of `dir` produces
	the identical heading. One metre keeps the value readable in a debugger as
	"just in front of its nose", which is exactly what a charging bear is looking
	at.

	Three properties follow from it being a pure function of the lock, and each
	one was a requirement rather than a happy accident:

	  * LOD-SAFE. A slept bear does not move, so `|from - origin|` does not grow
	    and it wakes still committed to the bearing it slept on — with no timer to
	    have drained meanwhile, which is precisely the bug a seconds-based commit
	    would have had (see the note on `charge_commit` in the SPECIES row).
	  * MULTIPLAYER-SAFE. `quarry` is whatever _update_chase_state resolved, which
	    in a room is the nearest ROOM MEMBER. This only bends that point; it can
	    neither widen who is hunted nor reach past the detection radius. A
	    remote-driven bear never runs the arm at all — it renders the master's
	    samples — so there is no second simulation to disagree.
	  * SPEED-LATTICE-SAFE. It returns a POINT. Nothing here touches
	    chase_speed_instance, which _ready() already clamped to MAX_CHASE_SPEED.
	    A charging bear is dangerous because it does not need to slow down to
	    turn, never because it is fast; running still escapes it.

	@param quarry: where the chase currently wants to go
	@param from: this bear's own position
	@param lock: its committed bearing, MUTATED here — { "dir", "origin" }
	@param commit: metres of straight line before it looks up again
	@return the point to steer at this frame

	ponytail: the lock is cleared by the arm on losing the chase and never
	otherwise, so a bear that is knocked off course by a block finishes its
	committed metres against the wall before re-aiming. That reads as a bear
	shouldering into stone, which is the right animation for the wrong reason;
	the upgrade path, if it ever matters, is to re-lock on a blocked feeler.
	"""
	var dir: Vector3 = lock.get("dir", Vector3.ZERO)
	if dir == Vector3.ZERO or from.distance_to(lock["origin"]) >= commit:
		var aim := quarry - from
		aim.y = 0.0
		if aim.length() < 0.01:
			# Standing on top of the quarry: there is no bearing to commit to, so
			# leave the lock alone and let the plain chase have this frame.
			return quarry
		dir = aim.normalized()
		lock["dir"] = dir
		lock["origin"] = from
	return from + dir


static func pack_steer_point(quarry: Vector3, from: Vector3, id: int,
		pack_size: int, flank_radius: float) -> Vector3:
	"""
	Where one pack hunter steers, given only ITS OWN id and ITS OWN position.

	    slot  = id modulo pack_size          -> this animal's compass point
	    ring  = min(flank_radius, d * TAPER) -> how wide the swing still is
	    point = quarry + ring * (sin, 0, cos) of TAU * slot / pack_size

	THE SURROUND IS EMERGENT, AND "EMERGENT" HERE HAS A PRECISE MEANING: nothing
	in this function can see another wolf. There is no coordinator, no leader, no
	registry, no group scan and not one byte of inter-agent communication — six
	wolves each running this arrive on six different bearings for the same reason
	six people each told to stand at a different hour of a clock face end up in a
	circle. What they share is the CLOCK (this function), never a message.

	Three properties follow from it being PURE, and each one is a requirement
	this bead had to meet rather than a happy accident:

	  * LOD-SAFE. The LOD manager sleeps distant crocodiles by zeroing velocity
	    and switching off _physics_process. A slept wolf therefore stops steering
	    — and cannot corrupt the pack's shape, because no other wolf was ever
	    reading it. A waking one recomputes this from where it is standing NOW,
	    with no integrator, no accumulated phase and no remembered target to
	    catch up to, so it rejoins its slot with no lurch: the first frame back
	    produces exactly the point it would have produced had it never slept.
	  * MULTIPLAYER-SAFE. `quarry` is whatever _update_chase_state resolved,
	    which in a room is the nearest ROOM MEMBER (a RemoteAvatar is in no
	    group, so it is found through presence, never through group "player").
	    This function only bends that point; it cannot widen who is hunted or
	    reach past the detection radius, and every peer computing it gets the
	    same answer from the same id.
	  * SPEED-LATTICE-SAFE. It returns a POINT. Nothing here touches
	    chase_speed_instance, which _ready() already clamped to MAX_CHASE_SPEED.
	    A flanking wolf covers more ground than a charging one at the SAME speed,
	    which is the entire trick: the pack is dangerous because it cuts angles,
	    and running still escapes it.

	The ring is anchored to WORLD compass bearings rather than to the quarry's
	facing, deliberately. A ring that rotated with the player would swing every
	wolf sideways the instant the player turned around — a pack that pirouettes
	on camera input. World-anchored, a wolf holds its bearing and the player is
	the one who has to keep turning to face it.

	ponytail: slots are claimed by `id % pack_size` with nobody arbitrating, so
	two wolves CAN draw the same bearing (see pack_size for why the ring is wider
	than the pack). They are solid to one another (collision_mask 3) and simply
	jostle, which reads as two wolves fighting over an angle. The upgrade path,
	if it ever matters, is the one thing this bead was told not to build: a
	claim, which needs a coordinator.
	"""
	if pack_size <= 0 or flank_radius <= 0.0:
		return quarry

	var to_quarry := quarry - from
	to_quarry.y = 0.0
	# The taper is what turns a ring into a spiral — see PACK_FLANK_TAPER for the
	# proof that it converges. Note it uses the wolf's CURRENT distance, so the
	# offset shrinks continuously rather than switching off at a threshold; there
	# is no radius at which a wolf visibly changes its mind.
	var ring := minf(flank_radius, to_quarry.length() * PACK_FLANK_TAPER)
	var angle := TAU * float(posmod(id, pack_size)) / float(pack_size)
	return quarry + Vector3(sin(angle), 0.0, cos(angle)) * ring
