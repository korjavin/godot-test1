# Windman 3D Character Model

## Overview
High-resolution 3D model of the Windman character, created based on the character description and reference image from `docs/characters/windman.md`.

## Model Specifications

### File Information
- **Format**: GLTF/GLB (Binary GLTF)
- **File**: `windman.glb`
- **Vertices**: 4,838
- **Faces**: 9,488
- **Height**: ~1.69 meters (scaled to match 180cm character height)

### Character Features
The model includes all key features from the character description:

1. **Head & Face**
   - Short brown hair
   - Bandage covering eyes (blue top, red bottom)
   - Rounded face with soft features
   - Skin tone matching reference

2. **Body & Clothing**
   - Blue sleeveless T-shirt with white "W" and "M" letters
   - Brown shorts to knee length
   - Black boots with flat soles
   - Moderately stout, natural proportions

3. **Accessories**
   - Handheld fan in right hand
   - Brown wooden handle (~25cm)
   - Three colored blades (green, blue, red)
   - Semi-transparent blade appearance

## Skeleton Structure

The model is designed with a 20-bone skeleton for animation:

### Bone Hierarchy
```
Root
└── Hips
    ├── Spine
    │   └── Chest
    │       ├── Neck
    │       │   └── Head
    │       ├── LeftShoulder
    │       │   └── LeftUpperArm
    │       │       └── LeftLowerArm
    │       │           └── LeftHand
    │       └── RightShoulder
    │           └── RightUpperArm
    │               └── RightLowerArm
    │                   └── RightHand (Fan attached)
    ├── LeftUpperLeg
    │   └── LeftLowerLeg
    │       └── LeftFoot
    └── RightUpperLeg
        └── RightLowerLeg
            └── RightFoot
```

### Bone Positions
Detailed bone positions are documented in `windman.skeleton.json`.

## Animation Support

The model is fully rigged for animation with separate body parts:
- **Head**: Can rotate independently for looking around
- **Arms**: Full shoulder, elbow, and wrist movement
- **Legs**: Hip, knee, and ankle joints for walking/running
- **Torso**: Spine and chest bones for bending and twisting

### Recommended Animations
- Idle (standing with fan)
- Walk/Run cycle
- Fan waving motion
- Wind attack animations
- Jump/fall animations

## Usage in Godot

### Importing
1. The GLB file is automatically imported by Godot
2. Use `windman_3d.tscn` scene for a pre-configured setup with skeleton

### Scene Structure
The `windman_3d.tscn` includes:
- CharacterBody3D (for physics and movement)
- Skeleton3D (with all 20 bones configured)
- AnimationPlayer (ready for animation setup)
- CollisionShape3D (for collision detection)

### Creating Animations
1. Open `windman_3d.tscn` in Godot
2. Select the AnimationPlayer node
3. Create new animations by keyframing bone rotations/positions
4. The skeleton is fully compatible with Godot's animation system

## Generation Scripts

The model was generated using Python scripts:
- `scripts/generate_windman_model.py` - Basic model generation
- `scripts/generate_windman_rigged.py` - Enhanced version with skeleton info

To regenerate the model:
```bash
python3 scripts/generate_windman_rigged.py
```

## Technical Notes

### Mesh Details
- All body parts use smooth shading for better appearance
- Vertex colors are baked into the mesh
- Materials follow the character color scheme
- Fan blades have transparency for visual effect

### Performance
- Optimized polygon count for real-time rendering
- Suitable for multiple instances in a scene
- LOD (Level of Detail) generation enabled in import settings

### Future Enhancements
- Add texture maps for more detail
- Create blend shapes for facial expressions
- Add cloth simulation for shirt and shorts
- Particle effects for wind abilities

## Credits
- Character design: Based on `docs/characters/windman.md` specification
- 3D model generation: Automated using Trimesh library
- Reference image: `docs/characters/windman.png`
