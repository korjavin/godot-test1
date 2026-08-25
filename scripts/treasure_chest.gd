extends Area3D
## The open-trigger of one deterministic treasure chest.
##
## The chest's WOOD AND BRASS ARE NOT HERE — they are plain create_box entries in
## the generating chunk's single block MultiMesh and single BlockCollision body
## (see spawn_chest_in_chunk in endless_terrain.gd). This node is the chest's ONE
## non-batched cost: a trigger volume with no mesh and no material, so a chest
## adds ZERO draw calls. At ~1 chest per 13 chunks that is a handful of Area3Ds
## alive at once.
##
## HOW THE REWARD IS PAID — read this before changing it. The chest does NOT
## spawn coin nodes and does NOT call collect_coin(N) once. It calls
## `player.collect_coin(1)` N times, spread over CHEST_BURST_DURATION, because
## the coin economy counts PICKUPS, not value:
##   - the streak multiplier (player_controller.get_streak_multiplier) steps every
##     STREAK_COINS_PER_STEP *pickups*, so one collect_coin(12) is one link in the
##     chain and a chest would never light the streak up at all;
##   - each pickup refreshes the STREAK_WINDOW (2.5 s), and the whole burst fits
##     inside one window, so a chest reliably pushes the multiplier up a step;
##   - the extra-life threshold, the HUD and the coin blip all come along for free,
##     because they already hang off collect_coin.
## Staggering is therefore mechanical, not decorative: it is what makes a chest
## read (and score) as a coin *shower* rather than a single fat pickup.
##
## Spawned exactly like ability_effect.gd — a bare node, `set_script`, `add_child`,
## then `setup()` — so there is no .tscn to keep in step with this file.
##
## ponytail: the burst is driven by this node's own `_process`, not by a spawned
## one-shot helper. The chest is already a node parented to the chunk and already
## lives exactly as long as the reward needs to be paid; a second node would be a
## second thing to keep alive for nothing.

## Radius of the "you touched the chest" sphere, metres. Comfortably bigger than
## the chest box itself so it opens on a brush past rather than needing a nudge.
const TRIGGER_RADIUS: float = 2.0

## The pop when the lid comes off: the same self-freeing wave every ability and
## every coin pickup uses. It is the ONLY visual the opening gets — the chest
## geometry itself is baked into the chunk MultiMesh and cannot be animated per
## instance. ponytail: a real lid swing needs the lid lifted out of the MultiMesh
## into its own MeshInstance3D, i.e. a draw call per chest; not worth it for a
## quarter-second of motion.
const ABILITY_EFFECT := preload("res://scripts/ability_effect.gd")
const OPEN_FLASH_COLOR: Color = Color(1.0, 0.82, 0.35, 0.55)
const OPEN_FLASH_RADIUS: float = 2.4
const OPEN_FLASH_LIFETIME: float = 0.35

## The ONE sphere shape every chest trigger that will ever spawn shares. Same
## static lazy-getter discipline as ability_effect._get_shared_sphere_mesh() and
## endless_terrain._get_shared_unit_box_mesh(): every chest wants the identical
## radius, and chests are rebuilt on every chunk reload.
static var _shared_shape: SphereShape3D = null

## Guard so a chest can only ever be opened once (the deferred `monitoring` write
## below does not take effect until the end of the physics step, so a second body
## in the same step could otherwise re-enter).
var _opened: bool = false

## Burst state: how many single-coin awards are still owed, the gap between them,
## and the countdown to the next one.
var _remaining: int = 0
var _interval: float = 0.0
var _timer: float = 0.0

## The player that opened us. Held only for the length of the burst and always
## re-checked with is_instance_valid — a respawn or a restart can free things
## underneath a running effect.
var _player: Node = null


static func _get_shared_shape() -> SphereShape3D:
	if _shared_shape == null:
		_shared_shape = SphereShape3D.new()
		_shared_shape.radius = TRIGGER_RADIUS
	return _shared_shape


func setup(coin_count: int, burst_duration: float) -> void:
	"""
	Build the trigger and arm the reward. Safe to call right after add_child():
	everything is created here rather than in _ready, so the node is fully formed
	immediately (same contract as ability_effect.setup).

	@param coin_count: How many single-coin awards this chest pays out. Drawn from
	                   the chest's own seeded RNG by the terrain, so it is
	                   deterministic within a run like everything else about the
	                   chest.
	@param burst_duration: Seconds the payout is spread over.
	"""
	_remaining = maxi(1, coin_count)
	# Spread across the window rather than dividing into it: the first coin is paid
	# on contact and the rest follow, so a 1-coin chest degenerates gracefully.
	_interval = maxf(0.01, burst_duration) / float(_remaining)
	_timer = _interval

	# Same collision setup as coin.tscn's Area3D: on NO layer (nothing needs to
	# detect a chest) and masking layer 1 (the player). Crocodiles are layer 2 and
	# rideable fauna layer 3, so neither can ever trip a chest open.
	collision_layer = 0
	collision_mask = 1
	monitorable = false

	var shape := CollisionShape3D.new()
	shape.shape = _get_shared_shape()
	add_child(shape)

	# Idle until opened — a closed chest costs one physics-server area and no
	# script dispatch at all.
	set_process(false)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _opened:
		return
	if not body.is_in_group("player"):
		return
	_opened = true
	_player = body

	# Stop listening. MUST be deferred: Godot blocks direct property writes to a
	# monitoring Area3D from inside its own body_entered signal ("Function blocked
	# during in/out signal") — the same reason coin.gd reaches for queue_free
	# rather than switching itself off.
	set_deferred("monitoring", false)

	# The lid pop, parented to the CHUNK (our parent) rather than to us: we free
	# ourselves when the burst ends and a child effect would die with us. Same
	# rule, same reason, as coin.gd's pickup sparkle.
	var fx_parent := get_parent()
	if fx_parent:
		var fx := MeshInstance3D.new()
		fx.set_script(ABILITY_EFFECT)
		fx_parent.add_child(fx)
		fx.global_position = global_position
		fx.setup(OPEN_FLASH_COLOR, OPEN_FLASH_RADIUS, OPEN_FLASH_LIFETIME)

	# First coin lands on contact; _process pays out the rest.
	_award_one()
	set_process(true)


func _process(delta: float) -> void:
	_timer -= delta
	# A `while`, not an `if`: at CHEST_COINS_MAX over CHEST_BURST_DURATION the gap
	# is ~53 ms, which a frame hitch (or a browser tab regaining focus) can easily
	# overrun — paying only one coin per frame would silently stretch the burst
	# past the streak window on a slow frame.
	while _remaining > 0 and _timer <= 0.0:
		_timer += _interval
		_award_one()
	if _remaining <= 0:
		set_process(false)
		queue_free()


func _award_one() -> void:
	"""
	One ordinary coin, through the ordinary path — the whole point of the burst.
	"""
	_remaining -= 1
	if is_instance_valid(_player) and _player.has_method("collect_coin"):
		_player.collect_coin(1)

	# The pickup blip, through the manager's own player pool (we free ourselves at
	# the end of the burst, so a sound attached to this node would be cut off).
	# Null-safe group lookup + has_method, so a scene without SoundManager stays
	# silent instead of erroring, and the manager's own web unlock gate still
	# applies — play_coin early-returns until the first user gesture.
	var sm := get_tree().get_first_node_in_group("sound_manager")
	if sm and sm.has_method("play_coin"):
		sm.play_coin()
