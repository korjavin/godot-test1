extends Area3D
## Collectible Golden Coin
##
## A coin spins in place (and bobs gently so the mid-air ones catch the eye).
## When the player walks or jumps into it, it bumps the player's coin counter and
## removes itself.
##
## EDUCATIONAL NOTES:
## - Collection is event-driven: an Area3D fires `body_entered` when a physics
##   body overlaps it. We only react to bodies in the "player" group.
## - Coins are spawned by the endless terrain and parented to their chunk, so
##   they unload automatically when the chunk does (same as blocks/crocodiles).

# ============================================================================
# CONSTANTS
# ============================================================================

## How fast the coin spins around the vertical axis (radians/sec)
const SPIN_SPEED: float = 3.0

## Permanent rest lean off vertical (~15°) so the spin alternately shows the
## coin's face AND its edge instead of a dead-upright disc. Applied as a fixed
## basis composed with the spin each frame (see _process).
const TILT_BASIS: Basis = Basis(Vector3.RIGHT, deg_to_rad(15.0))

## Gem variant: worth this many coins, drawn this much bigger, and tinted purple.
## Gems are rolled by the terrain's road scatter (see _road_coins_at) — a coin
## becomes a gem only when the spawner calls make_gem() right after instantiate.
const GEM_VALUE: int = 10
const GEM_SCALE: float = 1.6
const GEM_COLOR: Color = Color(0.65, 0.25, 0.95)

## The self-freeing expanding wave used for the pickup pop (same script the
## player's abilities use — see _spawn_ability_effect in player_controller.gd).
const ABILITY_EFFECT := preload("res://scripts/ability_effect.gd")

## Gentle up/down bob so coins feel lively and mid-air ones are easy to spot
const BOB_SPEED: float = 2.0
const BOB_AMOUNT: float = 0.12

## Multiplayer coin identity: how many id cells there are per metre. 8.0 means a
## 12.5 cm cell — see id_at() for the whole scheme and its two ceilings.
const COIN_ID_QUANT: float = 8.0

# ============================================================================
# STATE
# ============================================================================

## The spinning visual. We rotate this child, leaving the collision shape steady.
@onready var mesh: Node3D = $Mesh

## The ONE purple gem material, shared by every gem that will ever spawn. Built
## lazily in make_gem() from the coin scene's own material so an art change in
## coin.tscn still carries through. Static — one per process, never per gem.
static var _gem_material: StandardMaterial3D = null

## Guard so a coin can only ever be collected once.
var collected: bool = false

## How many coins this pickup is worth (1 for a plain coin, GEM_VALUE for a gem).
var value: int = 1

## Bob animation phase and the rest height we bob around.
var bob_phase: float = 0.0
var base_y: float = 0.0

## Accumulated spin angle (radians) and the mesh's scene-authored rest basis.
## We rebuild the mesh basis from scratch each frame — spin-around-world-up
## composed with the fixed tilt on top of the authored pose — because a plain
## `rotate_y` cannot express "spin upright while permanently leaning 15°" once
## the mesh is tilted (it would spin around the *tilted* local axis instead).
var spin_angle: float = 0.0
var mesh_base_basis: Basis

# ============================================================================
# IDENTITY (multiplayer)
# ============================================================================

static func id_at(pos: Vector3) -> int:
	"""
	The stable id of the coin standing at `pos`, as a pure function of position.

	Every coin in the world is spawned by one of THREE deterministic spawners in
	endless_terrain.gd (the road scatter, the artifact reward ring and the camp
	fire coins), all seeded from run_seed — so two peers sharing a seed put the
	same coin at the same place, and the position alone identifies it. Deriving
	the id here rather than threading one through three call sites is why none of
	those spawners needed a single edit.

	ponytail: two ceilings, both cosmetic by construction.
	  1. Two DISTINCT coins landing inside the same 12.5 cm cell share an id, so a
	     joiner would despawn one coin too many. The road scatter makes that
	     vanishingly rare and the cost is one missing coin, never a wrong bank.
	  2. A coin sitting exactly on a cell boundary can round the other way on a
	     peer whose float arithmetic differs by an ulp; its id then does not match
	     and the coin is simply NOT despawned — a duplicate, not a crash.
	The upgrade path for both is threading an explicit (k, slot) / (chunk, index)
	id out of the three spawners.
	"""
	return hash(Vector3i(
		roundi(pos.x * COIN_ID_QUANT),
		roundi(pos.y * COIN_ID_QUANT),
		roundi(pos.z * COIN_ID_QUANT)
	))


func coin_id() -> int:
	"""This coin's id. Valid from _ready on — every spawner sets the coin's
	position BEFORE add_child, so global_position is already final."""
	return id_at(global_position)


# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	add_to_group("coin")

	# Remember where we were placed so the bob oscillates around it.
	base_y = position.y

	# MULTIPLAYER: a coin an incumbent already banked must not exist for a peer
	# that joined mid-run. The MP manager holds the collected set replayed to us
	# on join; offline the group lookup finds nothing and this is one failed
	# lookup per coin AT SPAWN — never per frame. Done before body_entered is
	# connected, so a coin freed here can never fire a pickup on its way out.
	var mp := get_tree().get_first_node_in_group("mp")
	if mp and mp.has_method("is_coin_collected") and mp.is_coin_collected(coin_id()):
		queue_free()
		return

	# Cache the scene-authored mesh pose; the spin/tilt compose on top of it.
	mesh_base_basis = mesh.basis

	# Offset the bob per-coin so a field of coins doesn't pulse in lockstep.
	bob_phase = randf() * TAU

	# React when something enters our collection volume.
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	# Spin the coin face: rotate around WORLD up, with the permanent 15° lean
	# and the authored pose composed in (leftmost transform applies last).
	spin_angle += SPIN_SPEED * delta
	if mesh:
		mesh.basis = Basis(Vector3.UP, spin_angle) * TILT_BASIS * mesh_base_basis

	# Bob up and down a little around the spawn height.
	bob_phase += delta * BOB_SPEED
	position.y = base_y + sin(bob_phase) * BOB_AMOUNT


# ============================================================================
# GEM UPGRADE
# ============================================================================

func make_gem() -> void:
	"""
	Upgrade this coin into a rare purple GEM worth GEM_VALUE coins.

	Called by the terrain right after instantiate (BEFORE this node enters the
	tree), so we fetch $Mesh with get_node here rather than relying on the
	@onready `mesh` var, which is only assigned at _ready.

	EDUCATIONAL NOTE — duplicate, never mutate, the shared material: every coin
	instance shares the material resource baked into coin.tscn. Recolouring it
	in place would turn EVERY coin in the world purple (same defensive-duplicate
	pattern as _setup_fog in endless_terrain.gd).
	"""
	value = GEM_VALUE

	# Bigger all over — scaling the Area3D grows the visual AND the pickup
	# sphere together, so the rarer, juicier pickup is also a little easier to grab.
	scale = Vector3.ONE * GEM_SCALE

	var gem_mesh: MeshInstance3D = get_node("Mesh")
	if _gem_material == null:
		var mat := gem_mesh.get_surface_override_material(0)
		if not (mat is StandardMaterial3D):
			return
		# Build the purple variant ONCE for the whole process and share it. Every
		# gem wants the identical material (GEM_COLOR is a const), and gems are
		# rebuilt on every chunk reload all along the road, so duplicating per gem
		# was pure churn — same static-cache discipline as ToonShading's styled
		# materials and fauna's "never duplicate a material per animal" rule.
		_gem_material = (mat as StandardMaterial3D).duplicate()
		_gem_material.albedo_color = GEM_COLOR
		_gem_material.emission = GEM_COLOR
	gem_mesh.set_surface_override_material(0, _gem_material)


# ============================================================================
# COLLECTION
# ============================================================================

func _on_body_entered(body: Node) -> void:
	"""Collect the coin when the player touches it (ignore everything else)."""
	if collected:
		return
	if not body.is_in_group("player"):
		return

	collected = true
	if body.has_method("collect_coin"):
		body.collect_coin(value)

	# MULTIPLAYER: tell the room this coin is gone, so a peer joining later never
	# sees it. Null-safe group lookup like the sound manager below; the manager
	# records only while in a room, so offline this is a no-op.
	var mp := get_tree().get_first_node_in_group("mp")
	if mp and mp.has_method("report_coin_collected"):
		mp.report_coin_collected(coin_id())

	# Pickup blip. The MANAGER owns the audio players — this coin queue_free()s
	# itself right below, so a sound attached to this dying node would be cut off.
	var sm := get_tree().get_first_node_in_group("sound_manager")
	if sm and sm.has_method("play_coin"):
		sm.play_coin()

	# Pickup pop: a quick gold wave at the coin's spot. Parented to the COIN'S
	# PARENT (the chunk), not the coin — we queue_free() ourselves right below,
	# and a child effect would die with us. The wave frees itself when done and
	# unloads with the chunk, so nothing leaks (same pattern as the abilities).
	var fx_parent := get_parent()
	if fx_parent:
		var fx := MeshInstance3D.new()
		fx.set_script(ABILITY_EFFECT)
		fx_parent.add_child(fx)
		fx.global_position = global_position
		fx.setup(Color(1.0, 0.85, 0.2, 0.5), 1.2, 0.25)

	# Remove the coin now that it's been picked up.
	queue_free()
