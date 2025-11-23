# Windman Separate Mesh System

## Overview
Windman is now built from **11 separate mesh parts** that can be animated independently. This provides full limb articulation without requiring skeletal rigging in Blender.

## Architecture

### Mesh Parts Generated
Each part is a separate GLB file in `assets/models/characters/windman_parts/`:

1. **windman_head.glb** (820 vertices) - Head, hair, bandage
2. **windman_torso.glb** (260 vertices) - Neck, chest, shirt with W/M letters, pelvis
3. **windman_left_upper_arm.glb** (358 vertices) - Left shoulder/bicep
4. **windman_left_lower_arm.glb** (520 vertices) - Left forearm + hand
5. **windman_right_upper_arm.glb** (358 vertices) - Right shoulder/bicep
6. **windman_right_lower_arm.glb** (520 vertices) - Right forearm + hand
7. **windman_left_upper_leg.glb** (358 vertices) - Left thigh
8. **windman_left_lower_leg.glb** (366 vertices) - Left calf + boot
9. **windman_right_upper_leg.glb** (358 vertices) - Right thigh
10. **windman_right_lower_leg.glb** (366 vertices) - Right calf + boot
11. **windman_fan.glb** (554 vertices) - Handheld fan with 3 colored blades

**Total: 4,838 vertices across 11 parts**

### Scene Hierarchy

```
Windman
└── Body
    ├── Head (static, positioned at neck)
    ├── Torso (static, central body)
    ├── LeftArm (shoulder pivot point)
    │   ├── UpperArm (mesh)
    │   └── LowerArm (elbow pivot point)
    │       └── Mesh (forearm+hand)
    ├── RightArm (shoulder pivot point)
    │   ├── UpperArm (mesh)
    │   └── LowerArm (elbow pivot point)
    │       └── Mesh (forearm+hand)
    │           └── Fan (attached to right hand)
    ├── LeftLeg (hip pivot point)
    │   ├── UpperLeg (mesh)
    │   └── LowerLeg (knee pivot point)
    │       └── Mesh (calf+boot)
    └── RightLeg (hip pivot point)
        ├── UpperLeg (mesh)
        └── LowerLeg (knee pivot point)
            └── Mesh (calf+boot)
```

### Animation Points

The player controller animates these nodes:
- **Body/LeftArm** - Rotates at shoulder
- **Body/RightArm** - Rotates at shoulder
- **Body/LeftLeg** - Rotates at hip
- **Body/RightLeg** - Rotates at hip

**Future enhancement**: Also animate the LowerArm/LowerLeg nodes for elbow/knee bending.

## Advantages

✅ **Individual limb control** - Each limb can rotate independently
✅ **No Blender required** - Pure Python/Trimesh generation
✅ **Works with existing animation** - Compatible with player controller
✅ **High visual quality** - All original details preserved
✅ **Lightweight** - Only loads needed parts
✅ **Extensible** - Can add elbow/knee articulation later

## Animation System Compatibility

### Current (Shoulder/Hip Only)
The player controller animates the upper pivot points (shoulders/hips):
- Walking: Arms and legs swing from shoulders/hips
- Running: Faster, more pronounced swinging
- Jumping: Arms raised, legs positioned
- Idle: Subtle swaying

### Future Enhancement (Add Elbows/Knees)
To add forearm and calf movement:

```gdscript
# In player_controller.gd, after animating upper limbs:
var left_lower_arm = left_arm.get_node_or_null("LowerArm")
if left_lower_arm:
    # Bend elbow slightly when swinging
    left_lower_arm.rotation.x = abs(arm_swing) * 0.3
```

## Regeneration

To regenerate the mesh parts:
```bash
python3 scripts/generate_windman_separate.py
```

This will recreate all 11 GLB files in `assets/models/characters/windman_parts/`.

## Performance

- **Vertices**: 4,838 total (same as single-mesh version)
- **Draw calls**: 11 (one per part) - minimal overhead
- **Memory**: ~1MB total for all parts
- **FPS impact**: Negligible on modern hardware

## Comparison to Other Approaches

| Feature | Separate Meshes | Whole Body | Skeleton Rig |
|---------|----------------|------------|--------------|
| Visual Quality | ✅ High | ✅ High | ✅ High |
| Limb Animation | ✅ Yes | ❌ No | ✅ Yes |
| Elbow/Knee | 🟡 Possible | ❌ No | ✅ Yes |
| Blender Needed | ✅ No | ✅ No | ❌ Yes |
| Setup Time | 🟢 Fast | 🟢 Fast | 🔴 Slow |
| File Count | 🔴 11 files | 🟢 1 file | 🟢 1 file |
| Animation Complexity | 🟢 Simple | 🟢 Simple | 🟡 Moderate |

## Next Steps

1. ✅ **Current**: Arms/legs swing from shoulders/hips
2. 🔄 **Phase 2**: Add elbow/knee bending for more realism
3. 🔄 **Phase 3**: Animate fan rotation
4. 🔄 **Phase 4**: Add head rotation to look at camera
5. 🔄 **Phase 5**: Create custom attack/ability animations

## Troubleshooting

### Limbs appear disconnected
- Check that pivot points (LeftArm, RightArm, etc.) are positioned correctly
- Verify mesh transforms use the -90° X rotation (0,0,1, 0,-1,0)

### Animation doesn't work
- Ensure player controller finds Body/LeftArm, Body/RightArm, Body/LeftLeg, Body/RightLeg
- Check console for "Limb nodes found" debug output

### Parts missing in Godot
- Run regeneration script to ensure all 11 GLB files exist
- Check that Godot has imported the files (look for .import files)
- Verify paths in windman_updated.tscn match actual file locations
