# Windman Separate Mesh System

## Overview
Windman is built from **11 separate mesh parts** that are animated independently.
That gives full limb articulation with no skeletal rig -- the project has no
`Skeleton3D` and no `AnimationPlayer` anywhere.

## Architecture

### Mesh Parts
Each part is its own GLB file in `assets/models/characters/windman_parts/`:

| File | Covers | Written by |
|---|---|---|
| `windman_head_authored.glb` | head, hair, eye bandage | **authored** -- Blender + MPFB2, bead z3e.2, shipped 2026-09-08. Has a `PROVENANCE.md` row plus its `.blend` and albedo PNG. No generator touches it. |
| `windman_torso.glb` | neck, chest, "W" emblem, pelvis | `scripts/generate_windman_separate.py` |
| `windman_left_upper_arm.glb` | left shoulder/bicep | generator |
| `windman_left_lower_arm.glb` | left forearm + hand | generator |
| `windman_right_upper_arm.glb` | right shoulder/bicep | generator |
| `windman_right_lower_arm.glb` | right forearm + hand | generator |
| `windman_left_upper_leg.glb` | left thigh | generator |
| `windman_left_lower_leg.glb` | left calf + boot | generator |
| `windman_right_upper_leg.glb` | right thigh | generator |
| `windman_right_lower_leg.glb` | right calf + boot | generator |
| `windman_fan.glb` | handheld fan, 3 coloured blades | generator |

Measured 2026-09-11: **34,947 vertices across the 11 GLBs**. That is the
*faceted-export* count -- `export_faceted()` in `scripts/predator_parts.py` splits
every face's vertices so the flat-shaded look survives the GLB round trip, so it
is several times the source mesh's vertex count and is not a polygon budget.

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

`scripts/player_animation.gd` finds these nodes **by exact name** under `Body` and rotates them:
- **Body/LeftArm** - Rotates at shoulder
- **Body/RightArm** - Rotates at shoulder
- **Body/LeftLeg** - Rotates at hip
- **Body/RightLeg** - Rotates at hip

**Future enhancement**: Also animate the LowerArm/LowerLeg nodes for elbow/knee bending.

## Advantages

✅ **Individual limb control** - Each limb can rotate independently
✅ **No rig** - No `Skeleton3D`, no `AnimationPlayer`, no weight painting
✅ **Mostly scripted** - The ten limb parts are pure Python/Trimesh; only the
   authored head needs Blender, and it is built once and committed
✅ **Works with existing animation** - Compatible with `player_animation.gd`
✅ **Extensible** - Can add elbow/knee articulation later

## Animation System Compatibility

### Current (Shoulder/Hip Only)
`player_animation.gd` animates the upper pivot points (shoulders/hips):
- Walking: Arms and legs swing from shoulders/hips
- Running: Faster, more pronounced swinging
- Jumping: Arms raised, legs positioned
- Idle: Subtle swaying

### Future Enhancement (Add Elbows/Knees)
To add forearm and calf movement:

```gdscript
# In player_animation.gd, after animating upper limbs:
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

That rewrites the **ten generated** parts in
`assets/models/characters/windman_parts/`. It does not write
`windman_head_authored.glb` -- the head is authored, and regenerating it would
destroy an authored asset. CI rebuilds the generated models and fails on a dirty
tree, so a generator change and its regenerated `.glb` belong in one commit.

## Performance

- **Draw calls**: 11 (one per part) -- negligible next to the world's batched geometry.
- **Disk**: ~1.2 MB for the eleven GLBs.

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
- Ensure `player_animation.gd` finds Body/LeftArm, Body/RightArm, Body/LeftLeg, Body/RightLeg
- Check console for "Limb nodes found" debug output

### Parts missing in Godot
- Run the regeneration script to restore the ten generated parts (it will not
  bring back `windman_head_authored.glb`; that one is only ever restored from
  version control)
- Check that Godot has imported the files (look for .import files)
- Verify paths in windman_updated.tscn match actual file locations
