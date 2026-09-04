# Windman 3D Model Integration

## Overview
The Windman character has been upgraded from simple primitive shapes to a high-resolution 3D model with full skeletal animation support.

## Files Involved

### Model Files
- `assets/models/characters/windman.glb` - High-resolution 3D model (4,838 vertices, 9,488 faces)
- `assets/models/characters/windman.skeleton.json` - Skeleton structure documentation
- `assets/models/characters/README.md` - Complete model specifications

### Scene Files
- `scenes/characters/windman_updated.tscn` - **Active player character scene** (used by player controller)
- `scenes/characters/windman_3d.tscn` - Standalone scene with full skeleton setup
  (the legacy primitive-based `windman.tscn` was deleted in bead godot-test1-y1o.19 —
  nothing referenced it)

### Scripts
- `scripts/windman_animator.gd` - Animation bridge script
- `scripts/player_controller.gd` - Updated to use new Windman model
- `scripts/generate_windman_model.py` - Model generation script
- `scripts/generate_windman_rigged.py` - Rigged model generation script

## How It Works

### Animation System Integration

The new Windman model uses a **hybrid animation approach**:

1. **High-Resolution Visual Model**: The GLB file contains a detailed mesh with proper proportions, colors, and accessories
2. **Skeleton Structure**: 20-bone skeleton for full articulation (see windman.skeleton.json)
3. **Proxy Animation Nodes**: Empty Node3D nodes (LeftArm, RightArm, LeftLeg, RightLeg) that interface with the player controller
4. **Animation Bridge**: The `windman_animator.gd` script transfers rotations from proxy nodes to skeleton bones

### Scene Hierarchy

```
Windman (Node3D) [windman_animator.gd]
├── Body (Node3D)
│   └── WindmanModel (GLB instance)
│       └── Skeleton3D (20 bones)
├── LeftArm (Node3D) - Proxy for animation
├── RightArm (Node3D) - Proxy for animation
├── LeftLeg (Node3D) - Proxy for animation
└── RightLeg (Node3D) - Proxy for animation
```

### Animation Flow

1. **Player Controller** applies procedural animations to proxy nodes (LeftArm, RightArm, etc.)
2. **Windman Animator** reads proxy node rotations
3. **Skeleton Bones** are updated to match proxy rotations
4. **Visual Model** deforms based on skeleton pose

## Usage

### In Player Controller

The player controller now automatically uses the new Windman model:

```gdscript
const CHARACTERS: Array[Dictionary] = [
    {
        "name": "windman",
        "scene_path": "res://scenes/characters/windman_updated.tscn"  # Uses new model
    },
    # ... other characters
]
```

### Switching Characters

Press **E** during gameplay to cycle through characters. Windman will now appear with:
- Detailed head with bandage covering eyes
- Blue shirt with "W/M" lettering
- Brown shorts and black boots
- Handheld fan with colored blades
- Full procedural limb animations

## Model Features

### Visual Details
- **Height**: 1.69 meters (~180cm character)
- **Polygons**: 4,838 vertices, 9,488 faces
- **Colors**: Baked vertex colors (no external textures needed)
- **Details**: Bandage, shirt letters, fan with 3 colored blades

### Skeleton Bones
```
Root → Hips → Spine → Chest → Neck → Head
              ├── Shoulders → Upper Arms → Lower Arms → Hands
              └── Upper Legs → Lower Legs → Feet
```

### Supported Animations
- ✅ Walking/Running (leg and arm swinging)
- ✅ Jumping (arms raised, legs together)
- ✅ Idle (subtle breathing)
- ✅ Landing (crouch impact)
- 🔄 **Future**: Custom skeletal animations in AnimationPlayer

## Regenerating the Model

If you need to modify the model:

```bash
python3 scripts/generate_windman_rigged.py
```

This will regenerate:
- `windman.glb` - The 3D model
- `windman.skeleton.json` - Skeleton documentation

## Animation System Compatibility

### Current System (Procedural)
The player controller uses simple procedural animations that work with all characters:
- Sine wave-based limb swinging
- Simple rotation animations
- Compatible with both primitive and skeletal models

### Future Enhancements
To create custom skeletal animations:
1. Open `windman_3d.tscn` in Godot
2. Use the AnimationPlayer node
3. Keyframe individual bone rotations/positions
4. Export animations as .tres resources
5. Update `windman_animator.gd` to blend between procedural and keyframed animations

## Comparison: Old vs New

| Aspect | Old (primitive placeholder, since deleted) | New (windman_updated.tscn) |
|--------|-------------------|----------------------------|
| Vertices | ~200 | 4,838 |
| Visual Quality | Basic primitives | High-detail mesh |
| Animation | Direct node rotation | Skeleton-based |
| Customization | Limited | Full skeletal control |
| File Size | Small | Moderate (~1MB) |
| Performance | Fast | Good (optimized) |

## Troubleshooting

### Model doesn't appear
- Check that `windman.glb` exists in `assets/models/characters/`
- Verify the scene path in player_controller.gd is correct
- Ensure Godot has imported the GLB file

### Animations don't work
- Check that `windman_animator.gd` is attached to the Windman root node
- Verify proxy nodes (LeftArm, RightArm, etc.) exist in the scene
- Look for errors in Godot's output console

### Model is too small/large
- Adjust the transform scale in `windman_updated.tscn`
- Or modify the generation script and regenerate

## Credits
- Character design: Based on `docs/characters/windman.md`
- Model generation: Python + Trimesh library
- Integration: Hybrid animation system

## Next Steps
1. ✅ Basic integration complete
2. 🔄 Create custom walk/run animations using AnimationPlayer
3. 🔄 Add fan rotation animation
4. 🔄 Create attack/ability animations (wind powers)
5. 🔄 Add facial expressions (blend shapes)
6. 🔄 Texture mapping for enhanced detail
