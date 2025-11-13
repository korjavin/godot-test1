# Tutorial: Customizing Your Hero and Understanding Physics 🎨⚡

This tutorial will teach you how to customize your character's appearance and understand the physics behind movement in your Zelda-like game.

## Table of Contents

- [Part 1: Customizing Hero Appearance](#part-1-customizing-hero-appearance)
- [Part 2: Understanding Physics](#part-2-understanding-physics)
- [Part 3: Advanced Customization](#part-3-advanced-customization)
- [Part 4: Experiments to Try](#part-4-experiments-to-try)

---

## Part 1: Customizing Hero Appearance

### Understanding the Current Character

Currently, your hero is a simple **capsule shape**. This is common for prototyping because:
- It's simple to work with
- Collision detection is efficient
- You can focus on mechanics before art

Let's learn how to customize it!

### Method 1: Changing the Basic Shape

#### Step 1.1: Change the Capsule Color

1. Open Godot and load your project
2. In the Scene panel (left side), navigate to:
   ```
   Main → Player → MeshInstance3D
   ```
3. In the Inspector panel (right side), find **Mesh → Material**
4. Click the dropdown next to **Surface Material Override**
5. Select **New StandardMaterial3D**
6. Click on the material icon that appears
7. Expand **Albedo** section
8. Click the **Color** box and choose a color!

**Experiment Ideas:**
- Try red for a heroic look
- Try blue for a magical character
- Try gold for a royal knight

#### Step 1.2: Change the Character Size

1. Select **MeshInstance3D** in the scene tree
2. In the Inspector, find **Transform → Scale**
3. Modify values:
   - `X = 0.8` makes character thinner
   - `Y = 1.2` makes character taller
   - `Z = 0.8` makes character narrower

⚠️ **Important**: If you change the visual size, you should also change the collision size!

4. Select **CollisionShape3D** under Player
5. Find **Shape → Radius** and **Shape → Height**
6. Adjust to match your visual changes

### Method 2: Using a Custom 3D Model

Want to use a real character model? Here's how!

#### Step 2.1: Find a 3D Model

**Free 3D Model Resources:**
- [Kenney.nl](https://kenney.nl/assets) - Free game assets
- [Mixamo](https://www.mixamo.com/) - Free rigged characters
- [Sketchfab](https://sketchfab.com/search?type=models&features=downloadable) - Free downloadable models
- [OpenGameArt](https://opengameart.org/) - Community-created assets

**Supported Formats:**
- `.glb` / `.gltf` (Recommended)
- `.obj`
- `.fbx` (requires import)
- `.blend` (Blender files)

#### Step 2.2: Import the Model

1. Download a 3D model (e.g., `hero.glb`)
2. Copy the file to `assets/models/` in your project folder
3. Godot will automatically detect and import it
4. In the FileSystem panel (bottom-left), find your model
5. Drag it into the scene or click to preview

#### Step 2.3: Replace the Capsule

1. In the Scene panel, select **MeshInstance3D** under Player
2. In the Inspector, find **Mesh**
3. Drag your imported model to the Mesh property
4. Adjust the Transform → Position to center the model (usually Y = 0)

**Common Adjustments:**
```
Transform → Position: (0, 0, 0)
Transform → Rotation: (0, 180, 0)  # If model faces wrong way
Transform → Scale: (0.5, 0.5, 0.5)  # If model is too big
```

### Method 3: Adding Textures and Materials

#### Step 3.1: Create a Textured Material

1. Create or find a texture image (PNG, JPG)
2. Copy it to `assets/textures/`
3. Select your **MeshInstance3D**
4. In Inspector → **Mesh → Surface Material Override**:
   - Create New StandardMaterial3D
   - Click the material to edit it
   - Expand **Albedo** section
   - Click **Texture** dropdown
   - Select **Load** and choose your texture

#### Step 3.2: Adjusting Material Properties

Experiment with these material properties:

**Metallic**: Makes surface look like metal
```
Metallic: 0.0 = Cloth/Organic
Metallic: 1.0 = Shiny Metal
```

**Roughness**: Controls shininess
```
Roughness: 0.0 = Mirror-like
Roughness: 1.0 = Matte/Dull
```

**Normal Map**: Adds surface detail without geometry
- Requires a normal map texture (blue-ish image)
- Expand **Normal Map** → Load texture

### Method 4: Adding a Custom Character Model (Advanced)

For a complete character replacement:

1. **Download an animated character** from Mixamo
2. **Import to Godot**:
   ```
   assets/models/hero.glb
   ```
3. **Create a new scene** from the imported model:
   - In FileSystem, right-click the `.glb`
   - Select "New Inherited Scene"
   - This creates an editable version

4. **Integrate with Player scene**:
   - Open `scenes/player.tscn`
   - Delete the MeshInstance3D
   - Instance your character scene as a child of Player
   - Adjust position/rotation/scale

5. **Important**: Keep the CollisionShape3D! Your character needs collision.

---

## Part 2: Understanding Physics

### What is Physics in Games?

Physics in games simulates real-world forces:
- **Gravity**: Pulls objects down
- **Velocity**: Speed and direction of movement
- **Acceleration**: Rate of change of velocity
- **Collision**: When objects touch

### Gravity: The Force That Pulls You Down

#### How Gravity Works in This Game

Open `scripts/player_controller.gd` and find this section:

```gdscript
## Gravity value (meters per second squared)
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# In _physics_process:
if not is_on_floor():
    velocity.y -= gravity * delta
```

**What's Happening:**
1. Every frame (60 times per second), we check if the player is on the ground
2. If NOT on ground, we subtract gravity from the vertical velocity
3. The `delta` multiplier makes it frame-rate independent
4. This creates the falling effect!

#### Experiment: Change Gravity

**Earth Gravity** (Default):
```gdscript
var gravity: float = 9.8
```

**Moon Gravity** (Weak - Slow, floaty movement):
```gdscript
var gravity: float = 1.6
```

**Jupiter Gravity** (Strong - Fast, heavy feeling):
```gdscript
var gravity: float = 24.8
```

**Zero Gravity** (Space - Float forever!):
```gdscript
var gravity: float = 0.0
```

**Negative Gravity** (What?? Falling upward!):
```gdscript
var gravity: float = -9.8
```

Try each of these and feel the difference!

### Velocity: Speed and Direction

#### Understanding Velocity

Velocity is a **vector** - it has both magnitude (speed) and direction.

```gdscript
velocity = Vector3(x, y, z)
# x: Left (-) or Right (+)
# y: Down (-) or Up (+)
# z: Backward (-) or Forward (+)
```

**Example velocities:**
```gdscript
Vector3(5, 0, 0)   # Moving right at 5 m/s
Vector3(0, 10, 0)  # Moving up at 10 m/s (jumping!)
Vector3(0, -9.8, 0) # Falling due to gravity
Vector3(3, 0, 4)   # Moving diagonally (forward and right)
```

#### How Movement Works

In `player_controller.gd`:

```gdscript
# Get input direction (WASD keys)
var input_dir := Vector2(input_x, input_y)

# Convert to 3D based on character rotation
var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

# Apply speed
velocity.x = direction.x * current_speed
velocity.z = direction.z * current_speed
```

**Step-by-step breakdown:**
1. Read keyboard input → 2D vector
2. Rotate that vector to match character's facing direction
3. Multiply by speed to get velocity
4. Apply velocity with `move_and_slide()`

### Jump Physics

#### How Jumping Works

```gdscript
const JUMP_VELOCITY: float = 8.0

if Input.is_action_just_pressed("jump") and is_on_floor():
    velocity.y = JUMP_VELOCITY
```

**What happens:**
1. When you press Space and are on ground
2. Set vertical velocity to positive value (upward)
3. Gravity pulls you back down each frame
4. You land when collision detects ground

#### Jump Height Calculation

The maximum jump height depends on jump velocity and gravity:

```
Max Height = (JUMP_VELOCITY²) / (2 × gravity)
```

**Examples:**
```
JUMP_VELOCITY = 8.0, gravity = 9.8
Max Height = 64 / 19.6 = 3.27 meters

JUMP_VELOCITY = 15.0, gravity = 9.8
Max Height = 225 / 19.6 = 11.48 meters (Super jump!)

JUMP_VELOCITY = 8.0, gravity = 1.6 (Moon)
Max Height = 64 / 3.2 = 20 meters (Moon jumps are huge!)
```

### Movement Speed and Friction

#### Speed States

The game has three movement speeds:

```gdscript
const WALK_SPEED: float = 5.0   # Normal movement
const RUN_SPEED: float = 10.0   # Holding Shift
const DUCK_SPEED: float = 2.5   # Holding Ctrl
```

**Try these experiments:**

**Super Speed:**
```gdscript
const WALK_SPEED: float = 20.0
const RUN_SPEED: float = 40.0
```

**Slow Motion:**
```gdscript
const WALK_SPEED: float = 1.0
const RUN_SPEED: float = 2.0
```

#### Friction (Stopping Movement)

When you release movement keys, friction slows you down:

```gdscript
# Gradually slow down
velocity.x = move_toward(velocity.x, 0, current_speed * delta * 10.0)
velocity.z = move_toward(velocity.z, 0, current_speed * delta * 10.0)
```

The `10.0` multiplier is the friction coefficient:
- **Higher = Stop faster** (e.g., `20.0` = ice skates off)
- **Lower = Slide more** (e.g., `1.0` = ice skating)

### Collision Detection

#### How Collision Works

Godot uses **physics shapes** for collision:

1. **CollisionShape3D** defines the character's physical boundary
2. **StaticBody3D** on terrain marks it as solid
3. **move_and_slide()** handles collision response automatically

**What `move_and_slide()` does:**
- Tries to move the character by velocity
- If it hits something, slides along the surface
- Prevents going through walls
- Detects floor for `is_on_floor()`

---

## Part 3: Advanced Customization

### Adding a Stamina System

Let's add a stamina system that depletes when running!

#### Step 3.1: Add Stamina Variables

In `scripts/player_controller.gd`, add these after the constants:

```gdscript
# Stamina system
@export var max_stamina: float = 100.0
var current_stamina: float = 100.0
const STAMINA_DRAIN_RATE: float = 20.0  # Per second while running
const STAMINA_REGEN_RATE: float = 15.0  # Per second while not running
```

#### Step 3.2: Modify the Physics Process

In `_physics_process()`, find the running check and replace it:

```gdscript
# Handle Running with stamina
if Input.is_action_pressed("run") and not is_ducking and current_stamina > 0:
    is_running = true
    current_stamina -= STAMINA_DRAIN_RATE * delta
    current_stamina = max(0, current_stamina)  # Don't go below 0
else:
    is_running = false
    current_stamina += STAMINA_REGEN_RATE * delta
    current_stamina = min(max_stamina, current_stamina)  # Don't exceed max

# Debug print (optional)
if is_running:
    print("Stamina: ", current_stamina)
```

Now running depletes stamina, and it regenerates when you stop!

### Adding Air Control

Want to control the character mid-air? Currently you can only move on the ground. Let's fix that!

#### Step 3.3: Add Air Movement

Find this section in `_physics_process()`:

```gdscript
# Apply Movement
if input_dir != Vector2.ZERO:
    var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
    velocity.x = direction.x * current_speed
    velocity.z = direction.z * current_speed
```

Replace it with:

```gdscript
# Apply Movement
if input_dir != Vector2.ZERO:
    var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

    if is_on_floor():
        # Full control on ground
        velocity.x = direction.x * current_speed
        velocity.z = direction.z * current_speed
    else:
        # Reduced control in air (50% effectiveness)
        var air_control: float = 0.5
        velocity.x = lerp(velocity.x, direction.x * current_speed, air_control * delta * 5.0)
        velocity.z = lerp(velocity.z, direction.z * current_speed, air_control * delta * 5.0)
```

Now you can steer mid-air!

### Adding Double Jump

#### Step 3.4: Implement Double Jump

Add a variable to track jumps:

```gdscript
var jumps_remaining: int = 2  # Allow 2 jumps (ground + air)
```

Replace the jump logic:

```gdscript
# Handle Jumping with double jump
if Input.is_action_just_pressed("jump"):
    if is_on_floor():
        # First jump from ground
        velocity.y = JUMP_VELOCITY
        jumps_remaining = 1  # One jump left
    elif jumps_remaining > 0:
        # Second jump in air
        velocity.y = JUMP_VELOCITY
        jumps_remaining -= 1

# Reset jumps when landing
if is_on_floor():
    jumps_remaining = 1
```

Now you can jump twice!

---

## Part 4: Experiments to Try

### Experiment 1: Create Different "Planets"

Create buttons or areas that change gravity:

1. Add this function to `player_controller.gd`:

```gdscript
func set_gravity(new_gravity: float) -> void:
    """
    Change the gravity value dynamically.
    Use this to create different planet zones!
    """
    gravity = new_gravity
    print("Gravity changed to: ", new_gravity)
```

2. Create an Area3D node in your scene:
   - Add CollisionShape3D (box shape)
   - Attach a script
   - On `body_entered` signal, call `player.set_gravity(1.6)` for moon zone!

### Experiment 2: Speed Boost Pickup

Create collectible items that boost speed:

```gdscript
# In a new script for the pickup
func _on_body_entered(body: Node3D) -> void:
    if body.has_method("apply_speed_boost"):
        body.apply_speed_boost(2.0, 5.0)  # 2x speed for 5 seconds
        queue_free()  # Remove pickup
```

```gdscript
# In player_controller.gd
var speed_multiplier: float = 1.0

func apply_speed_boost(multiplier: float, duration: float) -> void:
    speed_multiplier = multiplier
    await get_tree().create_timer(duration).timeout
    speed_multiplier = 1.0

# Modify calculate_current_speed():
func calculate_current_speed() -> float:
    var base_speed: float
    if is_ducking:
        base_speed = DUCK_SPEED
    elif is_running:
        base_speed = RUN_SPEED
    else:
        base_speed = WALK_SPEED

    return base_speed * speed_multiplier
```

### Experiment 3: Wall Running

Advanced physics challenge! Make the character run on walls:

```gdscript
var is_wall_running: bool = false

# In _physics_process, after move_and_slide():
if not is_on_floor() and is_on_wall():
    # Detect if moving along wall
    var wall_normal = get_wall_normal()
    var forward = -transform.basis.z

    if forward.dot(wall_normal) < -0.5:  # Moving into wall
        is_wall_running = true
        velocity.y = 0  # Cancel gravity
        # Add upward force
        velocity.y = 2.0
```

### Experiment 4: Dash Ability

Add a quick dash move:

```gdscript
const DASH_SPEED: float = 30.0
const DASH_DURATION: float = 0.2
var is_dashing: bool = false

# Add to _input:
if event.is_action_pressed("ui_accept") and not is_dashing:
    perform_dash()

func perform_dash() -> void:
    is_dashing = true
    var dash_direction = -transform.basis.z  # Forward direction
    velocity = dash_direction * DASH_SPEED

    await get_tree().create_timer(DASH_DURATION).timeout
    is_dashing = false
```

### Experiment 5: Adjustable Terrain

Modify terrain generation to create hills:

In `scripts/endless_terrain.gd`, modify the `create_chunk` function:

```gdscript
# Add noise for height variation
var noise = FastNoiseLite.new()
noise.seed = 12345
noise.frequency = 0.05

# In create_chunk, when creating vertices:
for vertex in plane_mesh.get_mesh_arrays()[0]:
    var height = noise.get_noise_2d(vertex.x, vertex.z) * 5.0  # 5m variation
    vertex.y = height
```

---

## Summary: Key Concepts Learned

### Appearance Customization
- ✅ Changing colors and materials
- ✅ Scaling and transforming meshes
- ✅ Importing custom 3D models
- ✅ Applying textures

### Physics Understanding
- ✅ Gravity and how it affects movement
- ✅ Velocity vectors and direction
- ✅ Jump physics and height calculations
- ✅ Collision detection basics
- ✅ Friction and deceleration

### Advanced Concepts
- ✅ Stamina systems
- ✅ Air control
- ✅ Double jumping
- ✅ Dynamic physics changes

---

## Next Steps

1. **Experiment with all the values** - Break things and see what happens!
2. **Combine modifications** - Create your own unique character
3. **Read the code comments** - Every line in `player_controller.gd` is explained
4. **Try the experiments** - They teach advanced concepts
5. **Create something new** - Add your own mechanics!

## Additional Resources

- **Godot Physics Documentation**: https://docs.godotengine.org/en/stable/tutorials/physics/
- **3D Model Sites**: See Part 1 for free resources
- **GDScript Reference**: https://docs.godotengine.org/en/stable/classes/

---

**Remember**: Game development is all about experimentation! Don't be afraid to change values, break things, and see what happens. That's how you learn! 🎮✨
