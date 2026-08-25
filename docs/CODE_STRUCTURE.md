# Code Structure and Architecture Guide 🏗️

This document explains the architecture, design patterns, and code organization of the CrimeKickers project.

## Table of Contents

- [Project Philosophy](#project-philosophy)
- [Architecture Overview](#architecture-overview)
- [Scene Hierarchy](#scene-hierarchy)
- [Script Structure](#script-structure)
- [Design Patterns](#design-patterns)
- [Data Flow](#data-flow)
- [Best Practices](#best-practices)
- [Extending the Project](#extending-the-project)

---

## Project Philosophy

### Educational Focus

This project prioritizes **learning** over complexity:

1. **Readability First**: Code is written to be understood, not to be clever
2. **Extensive Comments**: Every section explains the "why", not just the "what"
3. **Clear Naming**: Variables and functions have descriptive names
4. **Gradual Complexity**: Start simple, add features incrementally
5. **Self-Documenting**: Code structure mirrors game concepts

### Godot Best Practices

We follow Godot's recommended patterns:
- **Scene Composition**: Build complex objects from simple scenes
- **Signal-Driven**: Use signals for loose coupling (when needed)
- **Node Lifecycle**: Respect `_ready()`, `_process()`, `_physics_process()`
- **@export Variables**: Make values tweakable in the editor
- **Type Hints**: Use GDScript's static typing for clarity and performance

---

## Architecture Overview

### High-Level Architecture

```
Main Scene (World)
│
├── Player (CharacterBody3D)
│   ├── MeshInstance3D (Visual representation)
│   ├── CollisionShape3D (Physics boundary)
│   └── CameraPivot (Node3D)
│       └── Camera3D (Player's viewpoint)
│
├── EndlessTerrain (Node3D)
│   └── [Dynamic Chunks] (MeshInstance3D)
│       └── StaticBody3D (Terrain collision)
│
├── DirectionalLight3D (Sun/lighting)
└── WorldEnvironment (Sky, fog, ambience)
```

### Component Breakdown

#### 1. Main Scene (`scenes/main.tscn`)
**Purpose**: Root container for the entire game world

**Responsibilities**:
- Initialize the game environment
- Set up lighting and atmosphere
- Load player and terrain systems
- Manage global game state (future: UI, menus)

**Why This Design?**
- Central orchestration point
- Easy to add new systems (enemies, items, UI)
- Clear entry point for understanding the game

#### 2. Player (`scenes/player.tscn` + `scripts/player_controller.gd`)
**Purpose**: The player character and its behavior

**Responsibilities**:
- Handle player input (WASD, jump, etc.)
- Apply physics (gravity, movement, collision)
- Control camera based on mouse input
- Manage character states (walking, running, ducking)

**Why This Design?**
- Self-contained: Player scene can be reused or tested independently
- CharacterBody3D provides built-in physics features
- Camera is child of player for automatic following

#### 3. Endless Terrain (`scripts/endless_terrain.gd`)
**Purpose**: Generate and manage terrain chunks

**Responsibilities**:
- Track player position
- Create terrain chunks in view distance
- Remove chunks that are too far away
- Handle chunk collision

**Why This Design?**
- Scalability: Can render "infinite" worlds without using infinite memory
- Performance: Only render what's visible
- Extensibility: Easy to add procedural generation later

---

## Scene Hierarchy

### Understanding Godot's Scene System

Godot uses a **scene tree** where:
- Each scene is a collection of **nodes**
- Nodes have parent-child relationships
- Children inherit transformations from parents
- Scenes can be **instanced** into other scenes

### Player Scene Structure

```
Player (CharacterBody3D) [Root]
│   ↳ Script: player_controller.gd
│   ↳ Group: "player"
│
├── MeshInstance3D
│   ↳ Mesh: CapsuleMesh
│   ↳ Transform: (0, 1, 0) - Raised above origin
│   └─ Purpose: Visual representation
│
├── CollisionShape3D
│   ↳ Shape: CapsuleShape3D
│   ↳ Transform: (0, 1, 0) - Matches mesh
│   └─ Purpose: Physics collision boundary
│
└── CameraPivot (Node3D)
    ↳ Transform: (0, 1.5, 0) - At head height
    └─ Purpose: Rotation point for camera
    │
    └── Camera3D
        ↳ Transform: (0, 2, 8) - Behind and above player
        ↳ FOV: 75°
        └─ Purpose: Player's view into the world
```

**Key Design Decisions:**

1. **Why CapsuleMesh?**
   - Realistic for humanoid characters
   - Smooth collision (no getting stuck on edges)
   - Efficient physics calculations

2. **Why separate CameraPivot?**
   - Allows camera to rotate independently
   - Prevents camera roll/tilt issues
   - Clean separation of concerns

3. **Why Transform (0, 1, 0) for mesh?**
   - CharacterBody3D's origin is at feet
   - Mesh is raised so it doesn't clip through ground
   - Makes collision shape intuitive

### Main Scene Structure

```
Main (Node3D) [Root]
│
├── Player (Instance of player.tscn)
│   └─ Starting position: (0, 2, 0)
│
├── EndlessTerrain (Node3D)
│   ↳ Script: endless_terrain.gd
│   └─ Purpose: Manages terrain generation
│
├── DirectionalLight3D
│   ↳ Rotation: Angled for realistic shadows
│   ↳ Shadows: Enabled
│   └─ Purpose: Primary light source (sun)
│
└── WorldEnvironment
    ↳ Environment: Sky with procedural material
    └─ Purpose: Ambient lighting and atmosphere
```

**Why This Organization?**

1. **Flat Hierarchy**: Easy to find components
2. **Clear Responsibilities**: Each node has one job
3. **Extensibility**: Easy to add new systems
4. **Testing**: Components can be tested in isolation

---

## Script Structure

### player_controller.gd Architecture

#### Section-Based Organization

The script is divided into clear sections:

```
1. Class Documentation
   ↓
2. Constants (WALK_SPEED, JUMP_VELOCITY, etc.)
   ↓
3. Variables (gravity, is_ducking, etc.)
   ↓
4. Node References (@onready var camera, etc.)
   ↓
5. Lifecycle Methods (_ready, _input, _physics_process)
   ↓
6. Helper Functions (get_input_direction, etc.)
   ↓
7. Debug/Utility Functions (_to_string, etc.)
```

**Why This Order?**

1. **Top-Down Reading**: Most important information first
2. **Constants Before Variables**: Configuration visible upfront
3. **Main Logic in Middle**: Core behavior after setup
4. **Helpers at End**: Implementation details last

#### Key Methods Explained

##### `_ready()` - Initialization
```gdscript
func _ready() -> void:
    # Called once when node enters scene tree
    # Purpose: One-time setup

    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)  # Capture mouse
    if mesh_instance:
        original_scale_y = mesh_instance.scale.y  # Store default height
```

**When to Use**: Initialize variables, connect signals, configure settings

##### `_input(event)` - Input Events
```gdscript
func _input(event: InputEvent) -> void:
    # Called whenever input event occurs (mouse, keyboard, etc.)
    # Purpose: Handle input that shouldn't miss any events

    if event is InputEventMouseMotion:
        # Immediate camera rotation
```

**When to Use**: Mouse movement, UI input, events that need immediate response

##### `_physics_process(delta)` - Physics Updates
```gdscript
func _physics_process(delta: float) -> void:
    # Called every physics frame (fixed 60 FPS)
    # Purpose: Movement, physics, collision

    # Apply gravity
    # Handle jumping
    # Calculate movement
    # Apply velocity with move_and_slide()
```

**When to Use**: Movement, physics calculations, collision detection

**Why Not `_process()`?**
- `_physics_process()` runs at fixed 60 FPS
- `_process()` runs at variable frame rate
- Physics needs consistency for accurate simulation

#### Code Organization Principles

**1. Single Responsibility**
Each function does ONE thing:

```gdscript
# ✅ Good: Each function has one job
func get_input_direction() -> Vector2:
    # Only reads input, returns direction

func calculate_current_speed() -> float:
    # Only calculates speed based on state

func handle_ducking() -> void:
    # Only handles ducking logic
```

```gdscript
# ❌ Bad: Function does too much
func do_everything() -> void:
    # Read input
    # Calculate speed
    # Handle ducking
    # Apply movement
    # ... this is hard to understand!
```

**2. Clear Naming**

```gdscript
# ✅ Good: Names explain what they do
func get_input_direction() -> Vector2
func calculate_current_speed() -> float
func handle_ducking() -> void

# ❌ Bad: Unclear names
func get_dir() -> Vector2
func speed() -> float
func duck() -> void
```

**3. Constants for Magic Numbers**

```gdscript
# ✅ Good: Named constants
const WALK_SPEED: float = 5.0
const JUMP_VELOCITY: float = 8.0

velocity.x = direction.x * WALK_SPEED

# ❌ Bad: Magic numbers
velocity.x = direction.x * 5.0  # What is 5.0?
```

### endless_terrain.gd Architecture

#### Chunk Management System

**Data Structure:**
```gdscript
# Dictionary mapping chunk coordinates to mesh instances
var active_chunks: Dictionary = {}
# Key: Vector2i (chunk_x, chunk_z)
# Value: MeshInstance3D (the actual chunk)

# Example:
# {
#   Vector2i(0, 0): MeshInstance3D,
#   Vector2i(1, 0): MeshInstance3D,
#   Vector2i(0, 1): MeshInstance3D,
# }
```

**Why a Dictionary?**
- **Fast Lookup**: O(1) access by coordinates
- **Easy Management**: Add/remove chunks by coordinates
- **Memory Efficient**: Only stores what's loaded

#### Update Loop

```
Every Frame:
  1. Get player position (world coordinates)
  2. Convert to chunk coordinates
  3. Has player moved to new chunk?
     ├─ No  → Do nothing (efficiency!)
     └─ Yes → Update chunks:
              ├─ Calculate which chunks should be loaded
              ├─ Remove chunks outside render distance
              └─ Create new chunks in range
```

**Optimization: Only Update on Chunk Change**

```gdscript
if player_chunk != last_player_chunk:
    update_chunks(player_chunk)  # Only update when needed!
    last_player_chunk = player_chunk
```

This prevents recalculating chunks every frame (60 times per second!)

#### Coordinate System Conversion

**World → Chunk:**
```gdscript
func world_to_chunk(world_pos: Vector3) -> Vector2i:
    # Convert continuous world position to discrete chunk coordinates
    return Vector2i(
        int(floor(world_pos.x / chunk_size)),
        int(floor(world_pos.z / chunk_size))
    )

# Examples (chunk_size = 50):
# World (0, 0, 0)    → Chunk (0, 0)
# World (25, 0, 25)  → Chunk (0, 0) - Still in origin chunk
# World (50, 0, 0)   → Chunk (1, 0) - Next chunk over
# World (-25, 0, 0)  → Chunk (-1, 0) - Previous chunk
```

**Chunk → World:**
```gdscript
func chunk_to_world(chunk_pos: Vector2i) -> Vector3:
    # Convert discrete chunk coordinates to center of chunk
    return Vector3(
        chunk_pos.x * chunk_size + chunk_size / 2.0,
        terrain_height,
        chunk_pos.y * chunk_size + chunk_size / 2.0
    )

# Examples (chunk_size = 50):
# Chunk (0, 0)  → World (25, 0, 25) - Center of chunk
# Chunk (1, 0)  → World (75, 0, 25)
# Chunk (-1, 0) → World (-25, 0, 25)
```

---

## Design Patterns

### Pattern 1: Component-Based Architecture

**What**: Game objects are composed of reusable components (nodes)

**Example**:
```
Player = CharacterBody3D + Mesh + Collision + Camera + Script
```

**Benefits**:
- Reusability: Camera system can be reused for other entities
- Flexibility: Easy to add/remove features
- Testability: Components can be tested independently

### Pattern 2: State Machine (Implicit)

**What**: Character has different states affecting behavior

**Implementation**:
```gdscript
# State variables
var is_ducking: bool = false
var is_running: bool = false

# State affects behavior
func calculate_current_speed() -> float:
    if is_ducking:
        return DUCK_SPEED
    elif is_running:
        return RUN_SPEED
    else:
        return WALK_SPEED
```

**Why Implicit?**
- Simple for this project
- Easy to understand
- Can evolve to explicit state machine later if needed

### Pattern 3: Object Pooling (Chunk Management)

**What**: Reuse objects instead of constantly creating/destroying

**Implementation**:
```gdscript
# Don't create ALL chunks at once
# Create only what's needed, remove what's not

func update_chunks(player_chunk: Vector2i) -> void:
    # Determine what should exist
    var chunks_to_load = calculate_visible_chunks()

    # Remove old chunks
    for chunk in active_chunks:
        if chunk not in chunks_to_load:
            remove_chunk(chunk)  # Free memory

    # Create new chunks
    for chunk in chunks_to_load:
        if chunk not in active_chunks:
            create_chunk(chunk)  # Only create if needed
```

**Benefits**:
- Memory efficient
- Performance: No lag from mass creation/destruction
- Scalable: Can have "infinite" terrain

### Pattern 4: Separation of Concerns

**What**: Each script/node has a single, clear responsibility

**Example**:
```
player_controller.gd → Controls player movement only
endless_terrain.gd   → Generates terrain only
main.tscn            → Orchestrates the world
```

**Why Important?**
- Maintainability: Easy to find where to make changes
- Debugging: Isolated problems are easier to fix
- Collaboration: Multiple people can work on different systems

---

## Data Flow

### Input Flow

```
1. User Input (Keyboard/Mouse)
   ↓
2. Godot Input System
   ↓
3. _input() or _physics_process()
   ↓
4. Input Processing Functions
   ├─ get_input_direction() → Movement vector
   ├─ Mouse motion → Camera rotation
   └─ Action presses → Jump, duck, run
   ↓
5. State Changes
   ├─ is_running = true
   ├─ is_ducking = false
   └─ velocity.y = JUMP_VELOCITY
   ↓
6. Physics Application
   └─ move_and_slide() → Actual movement
```

### Terrain Generation Flow

```
1. Player Position Change
   ↓
2. Terrain Script Detects (_process)
   ↓
3. Calculate Required Chunks
   ├─ Player chunk coordinates
   └─ Render distance (square around player)
   ↓
4. Chunk Management
   ├─ Compare with active chunks
   ├─ Remove far chunks → free memory
   └─ Create new chunks → add to scene
   ↓
5. Chunk Creation
   ├─ Create MeshInstance3D
   ├─ Generate PlaneMesh
   ├─ Add StaticBody3D for collision
   └─ Position in world
```

### Physics Frame Flow

```
Every Physics Frame (1/60th second):

1. _physics_process(delta) called
   ↓
2. Apply Gravity (if not on floor)
   └─ velocity.y -= gravity * delta
   ↓
3. Handle Jump (if on floor + space pressed)
   └─ velocity.y = JUMP_VELOCITY
   ↓
4. Handle Ducking
   └─ Adjust mesh scale
   ↓
5. Calculate Movement Direction
   └─ Read input, apply rotation
   ↓
6. Calculate Speed
   └─ Based on state (walk/run/duck)
   ↓
7. Apply Velocity
   └─ velocity.x/z = direction * speed
   ↓
8. Move Character
   └─ move_and_slide()
       ├─ Applies velocity
       ├─ Handles collisions
       └─ Updates is_on_floor()
```

---

## Best Practices

### 1. Use Type Hints

```gdscript
# ✅ Good: Types are explicit
func calculate_speed(multiplier: float) -> float:
    return WALK_SPEED * multiplier

# ❌ Bad: Types are unclear
func calculate_speed(multiplier):
    return WALK_SPEED * multiplier
```

**Benefits**: Better performance, catches errors early, clearer code

### 2. Use @export for Tweakable Values

```gdscript
# ✅ Good: Can adjust in editor without code changes
@export var max_stamina: float = 100.0
@export var render_distance: int = 3

# ❌ Less flexible: Must edit code to change
var max_stamina: float = 100.0
```

### 3. Comment WHY, Not WHAT

```gdscript
# ✅ Good: Explains reasoning
# We clamp pitch to prevent camera from flipping upside-down
pitch = clamp(pitch, CAMERA_PITCH_MIN, CAMERA_PITCH_MAX)

# ❌ Bad: Obvious from code
# Clamp the pitch variable
pitch = clamp(pitch, CAMERA_PITCH_MIN, CAMERA_PITCH_MAX)
```

### 4. Use @onready for Node References

```gdscript
# ✅ Good: Initialized when scene is ready
@onready var camera: Camera3D = $CameraPivot/Camera3D

# ❌ Bad: Might be null if accessed too early
var camera: Camera3D = $CameraPivot/Camera3D
```

### 5. Group Nodes for Finding Them

```gdscript
# In player.tscn, add player to "player" group

# In terrain script:
player = get_tree().get_first_node_in_group("player")
```

**Benefits**: No need to pass references around, flexible architecture

---

## Extending the Project

### Adding a New Feature: Example - Health System

#### Step 1: Define Data

```gdscript
# In player_controller.gd
@export var max_health: float = 100.0
var current_health: float = 100.0
```

#### Step 2: Add Functions

```gdscript
func take_damage(amount: float) -> void:
    current_health -= amount
    current_health = max(0, current_health)

    if current_health <= 0:
        die()

func heal(amount: float) -> void:
    current_health += amount
    current_health = min(max_health, current_health)

func die() -> void:
    print("Player died!")
    # Reset position or show game over screen
```

#### Step 3: Create Damage Source

```gdscript
# New script: damage_zone.gd
extends Area3D

@export var damage_per_second: float = 10.0

func _on_body_entered(body: Node3D) -> void:
    if body.has_method("take_damage"):
        # Damage over time while in zone
        while overlaps_body(body):
            body.take_damage(damage_per_second)
            await get_tree().create_timer(1.0).timeout
```

#### Step 4: Integrate into Scene

1. Create Area3D node in main scene
2. Add CollisionShape3D (box, sphere, etc.)
3. Attach damage_zone.gd script
4. Connect body_entered signal

### Adding a New Feature: Example - Enemy AI

#### Step 1: Create Enemy Scene

```
Enemy (CharacterBody3D)
├── MeshInstance3D (Different color/shape)
├── CollisionShape3D
└── NavigationAgent3D (For pathfinding)
```

#### Step 2: Create Enemy Script

```gdscript
extends CharacterBody3D

@export var move_speed: float = 3.0
@export var detection_range: float = 15.0

var player: Node3D
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

func _ready() -> void:
    player = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
    if not player:
        return

    var distance = global_position.distance_to(player.global_position)

    if distance < detection_range:
        # Chase player
        nav_agent.target_position = player.global_position
        var next_pos = nav_agent.get_next_path_position()
        var direction = (next_pos - global_position).normalized()

        velocity = direction * move_speed
        velocity.y -= 9.8 * delta  # Gravity

        move_and_slide()
```

#### Step 3: Add to Main Scene

1. Instance enemy scene in main.tscn
2. Set up NavigationRegion3D for pathfinding
3. Adjust detection_range in inspector

---

## Performance Considerations

### Optimization Strategies Used

1. **Chunk-Based Terrain**
   - Only render nearby chunks
   - Reduces draw calls and memory usage

2. **Update Only on Change**
   - Terrain only updates when player changes chunks
   - Avoids unnecessary recalculations

3. **Simple Collision Shapes**
   - Capsule for player (efficient)
   - Box for terrain (fast)

4. **Static Typing**
   - GDScript type hints improve performance
   - Compiler can optimize better

### When to Optimize

**Don't Optimize Prematurely!**
- Build functionality first
- Measure performance
- Optimize bottlenecks only

**When to Optimize:**
- FPS drops below 60
- Loading takes too long
- Memory usage is excessive

---

## Summary

### Key Takeaways

1. **Clear Structure**: Scene hierarchy mirrors game logic
2. **Separation of Concerns**: Each script has one job
3. **Extensibility**: Easy to add new features
4. **Documentation**: Code explains itself and provides context
5. **Best Practices**: Type hints, exports, onready, groups

### Learning Path

1. Read scripts top to bottom
2. Experiment with constants
3. Add simple features (health, stamina)
4. Create new systems (enemies, items)
5. Optimize when needed

---

**Remember**: Good architecture makes the code a joy to work with. Take time to understand the patterns, and you'll be able to build amazing games! 🎮✨
