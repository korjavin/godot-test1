extends RefCounted
## THE AMBIENCE PROXY POOL — a handful of colliders that FOLLOW the nearest few
## MultiMesh instances, so the crowd and the traffic are solid without a single
## citizen or car ever becoming a node.
##
## OWNER (bead godot-test1-8gw.21): "our hero can run through crowd and cars,
## shouldn't be so" — refined by the steer that settled 8gw.22: "it is better to
## find a way how not to kill performance with cars/crowds, at the same time i
## want this natural. And we may use the same trick - only those moving who we
## can see."
##
## Shared by BOTH ambience managers (crowd_manager.gd, traffic_manager.gd) for
## exactly the reason `ambience_lod.gd` is: the rule and its numbers must be ONE
## copy — two drift, and the two managers are the same problem twice. Nothing
## else may use it; this is scenery collision, never a gameplay body.
##
## ----------------------------------------------------------------------------
## WHY A POOL AND NOT A BODY PER INSTANCE — the thing this file exists to refuse
## ----------------------------------------------------------------------------
## 120 citizens + 32 cars is 152 `StaticBody3D`s in the broadphase, and the
## managers' whole design (CLAUDE.md, "Budapest citizen crowds" and the fauna
## precedent it copies) is that the instances are TRANSFORMS IN A BUFFER, in no
## group, with no node at all. So the instances keep exactly that, and the
## MANAGER owns a small fixed pool of bodies that is moved onto the nearest few
## instances every frame. The player can only ever touch what is within a couple
## of metres of them, so the pool is the whole reachable set and its size does
## not grow with the crowd. Draw calls are untouched — a pool body carries a
## collision shape and NO mesh.
##
## THE LOCALITY IS 8gw.22'S, NOT A SECOND SCAN. Each manager already walks every
## instance once a frame to write the MultiMesh buffer, and that loop already has
## the world position in hand; `offer()` is called from inside it. There is no
## second nearest-N pass anywhere.
##
## ----------------------------------------------------------------------------
## THE ISOLATION IS THE PHYSICS LAYER, and it is the fauna precedent verbatim
## ----------------------------------------------------------------------------
## `fauna_manager.gd`'s rideable quadrupeds already solved "collide with the
## player and with absolutely nothing else": layer 3 (bit value 4). The player's
## `CharacterBody3D` masks layers 1 and 3 (`scenes/player.tscn`,
## `collision_mask = 5`); every predator is layer 2 / mask 3 (layers 1 and 2), so
## a crocodile, a hunter and a tower guard never see this layer at all. A pool
## body therefore joins NO group, is chased by nobody, is slept by nobody and is
## scattered by no Stink Wave — the isolation contract is unchanged and it is
## enforced by the layer rather than by absence. Putting these on layer 1 would
## silently undo all of it, because every predator mask includes layer 1.
##
## ----------------------------------------------------------------------------
## THE TWO WAYS A SOLID CROWD GOES WRONG, both handled here
## ----------------------------------------------------------------------------
##  * **THE PLAYER MUST NEVER BE TRAPPED — AND THAT IS A CROWD PROBLEM, WHICH IS
##    WHY IT IS A FLAG.** Citizens walk their waypoints and do not look where
##    they are going, so a solid crowd can pin a hero against a facade and keep
##    him there. CARS CANNOT: one brakes YIELD_DISTANCE (18 m) out and stops
##    STOP_DISTANCE (6.7 m) short of a hero, it only ever stands on a
##    carriageway, and an 8 m half-width avenue leaves 5.6 m of open road past
##    its far flank — so a car is exactly what the owner asked for, something you
##    bump into and slide along, and a car you could walk through after a beat
##    would be strictly worse. So the yield below is the CROWD's (`yields` true)
##    and the traffic declares it off; `crowd_selfcheck` and `traffic_selfcheck`
##    each assert their own answer, with the other as the control.
##    `commit()` runs a pool-wide STUCK
##    window: it opens the moment the player is in contact range of the nearest
##    proxy, and when it closes STUCK_SECONDS later it asks how far he actually
##    got. Less than `STUCK_TRAVEL` and the WHOLE pool goes soft for
##    `SOFT_SECONDS` and he walks through. That is "citizens yield", implemented
##    as the one thing that cannot be defeated by a citizen shuffling between
##    pool slots — the window is the POOL's, not a slot's, so re-ordering the
##    nearest few never resets it.
##    `ponytail:` the ceiling is that standing deliberately still beside a
##    citizen for `STUCK_SECONDS` also softens it, and the pedestrian walks
##    through the hero. Reading real intent needs the input stack, which is a
##    seam this file has no business opening for a cosmetic edge case.
##  * **NOTHING MAY PUSH THE PLAYER.** A pool body is teleported, so a body
##    placed ON TOP of the player would be resolved by `move_and_slide`'s
##    depenetration — a shove. `_player_inside()` is the guard: a proxy whose
##    VOLUME already contains the player is not solid this frame. It
##    can never fire during ordinary contact (contact holds the centre a player
##    radius clear of the footprint on every axis), so it costs nothing and
##    covers every way a pose can land on a hero.
##    **THE TEST IS 3-D, AND THAT IS BEAD `godot-test1-d5f`.** It used to be the
##    FOOTPRINT alone — an XZ centre containment — and a hero standing on a car
##    roof has his centre inside the footprint by definition, so the box he was
##    standing on switched itself off and he fell through it to the road. Worse,
##    the same rule met him on the way DOWN: measured on a real `player.tscn`
##    running at a parked car and jumping, the proxy went soft the frame he
##    crossed the bumper and stayed soft for the whole arc, so he sailed through
##    the car instead of landing on it — the owner's "I can run through the car,
##    but if I jump on it, I go through it to the ground", one bug with two
##    symptoms. The vertical half is `ROOF_GRACE`: feet at or above the roof are
##    STANDING ON IT and keep it solid; only feet genuinely below the roof — the
##    pose a teleport lands you in, and the only one depenetration would launch —
##    turn it off. For CARS the stronger promise
##    is upstream and is pure arithmetic: half the car's width plus a player
##    radius (0.925 + 0.5) is far inside `traffic_manager.LATERAL_TOLERANCE`
##    (3.2 m), so every car that could reach the player has already yielded to
##    him — a car that has stopped never advances at all. `traffic_selfcheck`
##    asserts that margin and drives the stop.

## Physics layer the proxies live on: layer 3, bit value 4 — see the header.
const PROXY_LAYER: int = 4

## Every pool body is named with this prefix. `crowd_selfcheck` and
## `traffic_selfcheck` read it: the ONLY `CollisionObject3D` either manager may
## own is one of these, and there may be at most the declared pool size of them.
const PROXY_NAME_PREFIX: String = "AmbienceProxy"

## Half-width of the player's capsule (`scenes/player.tscn`, the default
## `CapsuleShape3D` radius). Used only to decide "is the hero in contact range",
## which gates the stuck timer — nothing load-bearing hangs off its precision.
const PLAYER_HALF: float = 0.5

## How long the player may make no headway while touching this pool before the
## whole pool goes soft, and how long it stays soft. Half a second is "given a
## moment" — long enough that ordinary bumping-and-sliding never trips it, short
## enough that being pinned is a beat rather than a death.
const STUCK_SECONDS: float = 0.5
const SOFT_SECONDS: float = 1.0

## How far the player must travel HORIZONTALLY across a STUCK_SECONDS window for
## it to count as headway. The gap it has to separate is enormous, which is the
## point: a walking hero covers 2.5 m in that window and a running one 5 m, while
## a hero pinned against a body covers what physics jitter gives him — measured
## at about 4 mm. It is a DISTANCE OVER A WINDOW and deliberately not an
## instantaneous speed: a per-frame speed read of the same pinned hero swings to
## 0.6 m/s on the frames the depenetration nudges him, which resets a threshold
## latch forever and was exactly the bug the first draft of this shipped with.
## Horizontal because the y bob of a body settling on the floor is not headway.
const STUCK_TRAVEL: float = 0.5

## Slack added to the footprint when asking "is the hero in contact range". Only
## the stuck gate reads it.
const CONTACT_PAD: float = 0.35

## How far BELOW a proxy's roof the hero's feet may be and still count as
## STANDING ON IT rather than being stuck inside it. It bounds the only shove
## this file still permits: a hero whose feet are within this much of the roof
## keeps the box solid, so the very worst `move_and_slide` can lift him is
## ROOF_GRACE metres — a fifth of a step, against the 1.15 m launch that "his
## centre is in the footprint, switch it off" was trading it for. It has to be
## more than the few millimetres of penetration a landing at 8 m/s leaves and
## less than a step-up, and anything in that range is the same rule.
const ROOF_GRACE: float = 0.15

var _bodies: Array[StaticBody3D] = []
var _shapes: Array[CollisionShape3D] = []

## Footprint half-extents in the proxy's OWN frame: x lateral, z longitudinal.
var _half := Vector2(0.3, 0.3)

## The shape's full height, base at y = 0 — so the ROOF is at exactly this world
## y, since `commit()` seats every body at y = 0. Kept because the no-shove guard
## is 3-D and a rule about a roof needs to know where the roof is.
var _height: float = 1.0

## Does this pool yield to a pinned player? See the header — the crowd does, the
## traffic deliberately does not.
var _yields: bool = true

## How far from the player an instance must be to be worth a body. Big enough
## that a proxy is always in place well before anything can touch the hero, small
## enough that the pool covers everything inside it — see each manager's call.
var _reach: float = 3.0

# --- per-frame candidate buffer (the nearest few, nearest first) -------------
var _cand_pos: Array[Vector3] = []
var _cand_yaw: Array[float] = []
var _cand_d2: Array[float] = []
var _open: bool = false
var _player := Vector3.ZERO

# --- the anti-trap latch, pool-wide ----------------------------------------
## The open window: how long the player has been in contact, and where he was
## when it opened. `_watching` false means no window is open.
var _watching: bool = false
var _watch_time: float = 0.0
var _watch_from := Vector3.ZERO
## Seconds of softness left. While positive NOTHING in this pool is solid.
var _soft: float = 0.0


func build(parent: Node3D, count: int, half: Vector2, height: float, reach: float,
		yields: bool = true) -> void:
	"""Create the pool under `parent`. `half` is the footprint half-extents in the
	proxy's own frame (x lateral, z longitudinal, front is local -Z — the
	convention both car and citizen meshes are modelled in); `height` is the
	shape's full height with its base at y = 0."""
	_half = half
	_height = height
	_reach = reach
	_yields = yields
	for i in count:
		var body := StaticBody3D.new()
		body.name = "%s%d" % [PROXY_NAME_PREFIX, i]
		body.collision_layer = PROXY_LAYER
		body.collision_mask = 0  # a proxy asks nothing of the world; the player asks it.
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(half.x * 2.0, height, half.y * 2.0)
		cs.shape = box
		cs.position = Vector3(0.0, height * 0.5, 0.0)
		cs.disabled = true
		body.add_child(cs)
		parent.add_child(body)
		_bodies.append(body)
		_shapes.append(cs)


func begin(player_pos: Vector3) -> void:
	"""Open the frame's candidate buffer. Called once per frame before the
	manager's existing instance loop."""
	_player = player_pos
	_cand_pos.clear()
	_cand_yaw.clear()
	_cand_d2.clear()
	_open = true


func offer(world_pos: Vector3, yaw: float) -> void:
	"""Offer one instance from inside the manager's existing draw loop. Rejects on
	a box test before any square root, then keeps the nearest `pool size` in
	order — an insertion into an array of at most a handful, per instance that
	survived the reject, which is why this adds no measurable pass of its own.
	A no-op when the frame was never opened, so a harness driving the manager's
	update function directly behaves exactly as it did before."""
	if not _open or _bodies.is_empty():
		return
	var dx: float = world_pos.x - _player.x
	var dz: float = world_pos.z - _player.z
	if absf(dx) > _reach or absf(dz) > _reach:
		return
	var d2: float = dx * dx + dz * dz
	if d2 > _reach * _reach:
		return
	var n: int = _cand_d2.size()
	if n >= _bodies.size() and d2 >= _cand_d2[n - 1]:
		return
	var at: int = n
	for i in n:
		if d2 < _cand_d2[i]:
			at = i
			break
	_cand_d2.insert(at, d2)
	_cand_pos.insert(at, world_pos)
	_cand_yaw.insert(at, yaw)
	if _cand_d2.size() > _bodies.size():
		_cand_d2.resize(_bodies.size())
		_cand_pos.resize(_bodies.size())
		_cand_yaw.resize(_bodies.size())


func commit(delta: float, player_pos: Vector3) -> void:
	"""Place the pool on this frame's nearest few and decide, for each, whether it
	is solid. Closes the frame."""
	_open = false
	var n: int = _cand_pos.size()

	# --- THE ANTI-TRAP LATCH, pool-wide (see the header) --------------------
	# Open a window the moment the player is in contact range, and when it closes
	# ask how far he actually got. Less than STUCK_TRAVEL is "pinned", and the
	# WHOLE pool yields for SOFT_SECONDS.
	var touching: bool = _yields and n > 0 \
		and _cand_d2[0] <= _contact_range() * _contact_range()
	if touching:
		if not _watching:
			_watching = true
			_watch_time = 0.0
			_watch_from = player_pos
		_watch_time += delta
		if _watch_time >= STUCK_SECONDS:
			var moved := Vector2(player_pos.x - _watch_from.x,
					player_pos.z - _watch_from.z).length()
			if moved < STUCK_TRAVEL:
				_soft = SOFT_SECONDS
			_watching = false
	else:
		_watching = false
	_soft = maxf(0.0, _soft - delta)

	for i in _bodies.size():
		if i >= n:
			_shapes[i].disabled = true
			continue
		var pos: Vector3 = _cand_pos[i]
		var yaw: float = _cand_yaw[i]
		_bodies[i].global_position = Vector3(pos.x, 0.0, pos.z)
		_bodies[i].rotation.y = yaw
		# Soft while the pool is yielding, and never solid over the hero himself.
		_shapes[i].disabled = _soft > 0.0 or _player_inside(pos, yaw, player_pos)


func _contact_range() -> float:
	return maxf(_half.x, _half.y) + PLAYER_HALF + CONTACT_PAD


func _player_inside(pos: Vector3, yaw: float, player_pos: Vector3) -> bool:
	"""Is the player's body inside this proxy's own VOLUME? Only a body that
	landed ON the hero can answer true — ordinary contact holds his centre a
	player radius clear of every side face, and a hero on the roof is above it —
	so this is the no-shove guard and never a way through.

	THE VERTICAL HALF FIRST, because it is what bead `godot-test1-d5f` fixed:
	`player_pos` is the hero's FEET (`player.tscn`'s capsule is offset a metre up
	from its origin) and `commit()` seats every body at y = 0, so the roof is at
	`_height` in the same frame. Feet at or above it, less ROOF_GRACE, are
	standing ON the box — the box stays solid and he walks around on it. Only
	feet BELOW the roof can be the pose depenetration would launch.

	`ponytail:` there is no lower bound (feet below the box's base) and no capsule
	radius here. Both proxied things stand on the y = 0 street the hero does, so
	"below the base" is not a pose this game has, and the XZ test is deliberately
	the CENTRE — widening it by a player radius would switch the box off during
	ordinary contact, which is the through-the-car bug spelled the other way.

	`Basis.rotated(UP, yaw)` sends local +X to (cos, 0, -sin) and local +Z to
	(sin, 0, cos); front is local -Z, the mesh convention."""
	if player_pos.y >= _height - ROOF_GRACE:
		return false
	var d := Vector2(player_pos.x - pos.x, player_pos.z - pos.z)
	var ax := Vector2(cos(yaw), -sin(yaw))
	var az := Vector2(sin(yaw), cos(yaw))
	return absf(d.dot(ax)) < _half.x and absf(d.dot(az)) < _half.y


func solid_count() -> int:
	"""How many pool bodies are solid right now — the self-checks' read."""
	var live: int = 0
	for cs: CollisionShape3D in _shapes:
		if not cs.disabled:
			live += 1
	return live


func yielding() -> bool:
	"""True while the pool is soft because the player was making no headway."""
	return _soft > 0.0


func yields_to_pinned_player() -> bool:
	"""Whether this pool has the anti-trap yield at all — the crowd's, not the
	traffic's. The self-checks read it as each other's control."""
	return _yields


func sleep() -> void:
	"""Everything off — the managers' `_hide_all()` path (outside Budapest, or no
	local player at all)."""
	for cs: CollisionShape3D in _shapes:
		cs.disabled = true
	_open = false
	_watching = false
	_watch_time = 0.0
	_soft = 0.0
