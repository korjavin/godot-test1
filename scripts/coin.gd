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

## Gentle up/down bob so coins feel lively and mid-air ones are easy to spot
const BOB_SPEED: float = 2.0
const BOB_AMOUNT: float = 0.12

# ============================================================================
# STATE
# ============================================================================

## The spinning visual. We rotate this child, leaving the collision shape steady.
@onready var mesh: Node3D = $Mesh

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
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	add_to_group("coin")

	# Remember where we were placed so the bob oscillates around it.
	base_y = position.y

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
	var mat := gem_mesh.get_surface_override_material(0)
	if mat is StandardMaterial3D:
		var gem_mat: StandardMaterial3D = mat.duplicate()
		gem_mat.albedo_color = GEM_COLOR
		gem_mat.emission = GEM_COLOR
		gem_mesh.set_surface_override_material(0, gem_mat)


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

	# Pickup blip. The MANAGER owns the audio players — this coin queue_free()s
	# itself right below, so a sound attached to this dying node would be cut off.
	var sm := get_tree().get_first_node_in_group("sound_manager")
	if sm and sm.has_method("play_coin"):
		sm.play_coin()

	# Remove the coin now that it's been picked up.
	queue_free()
