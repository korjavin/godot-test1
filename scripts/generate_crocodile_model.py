#!/usr/bin/env python3
"""
Generate a 3D model of a Piglet Crocodile character.
Creates a GLB file that can be imported into Godot.
"""

import trimesh
import numpy as np

def create_crocodile_model():
    """Create a complete piglet crocodile 3D model."""

    # Color definitions
    BODY_COLOR = np.array([45, 80, 22, 255]) / 255.0  # Dark green #2d5016
    BELLY_COLOR = np.array([143, 181, 105, 255]) / 255.0  # Light yellowish-green #8fb569
    EYE_COLOR = np.array([255, 255, 0, 255]) / 255.0  # Yellow
    PUPIL_COLOR = np.array([0, 0, 0, 255]) / 255.0  # Black
    TEETH_COLOR = np.array([255, 255, 240, 255]) / 255.0  # Ivory

    meshes = []

    # --- BODY (main torso) ---
    # Elongated ellipsoid, slightly chubby (piglet-like)
    body = trimesh.creation.cylinder(
        radius=0.15,  # Thickness (chubby)
        height=0.6,  # Length of torso
        sections=16
    )
    # Rotate to horizontal (along X-axis)
    body.apply_transform(trimesh.transformations.rotation_matrix(
        np.pi / 2, [0, 1, 0]
    ))
    body.visual.vertex_colors = BODY_COLOR
    body.apply_translation([0, 0.15, 0])  # Lift off ground
    meshes.append(body)

    # --- HEAD ---
    # Elongated snout with wider base
    head_base = trimesh.creation.cylinder(
        radius=0.12,
        height=0.15,
        sections=16
    )
    head_base.apply_transform(trimesh.transformations.rotation_matrix(
        np.pi / 2, [0, 1, 0]
    ))
    head_base.visual.vertex_colors = BODY_COLOR
    head_base.apply_translation([0.4, 0.15, 0])  # Front of body
    meshes.append(head_base)

    # Snout (elongated)
    snout = trimesh.creation.cone(
        radius=0.12,
        height=0.25,
        sections=16
    )
    snout.apply_transform(trimesh.transformations.rotation_matrix(
        -np.pi / 2, [0, 0, 1]
    ))
    snout.apply_transform(trimesh.transformations.rotation_matrix(
        np.pi / 2, [0, 1, 0]
    ))
    snout.visual.vertex_colors = BODY_COLOR
    snout.apply_translation([0.6, 0.15, 0])  # Extend forward
    meshes.append(snout)

    # --- EYES ---
    # Left eye
    left_eye_white = trimesh.creation.icosphere(
        radius=0.04,
        subdivisions=2
    )
    left_eye_white.visual.vertex_colors = EYE_COLOR
    left_eye_white.apply_translation([0.5, 0.25, 0.08])
    meshes.append(left_eye_white)

    left_pupil = trimesh.creation.icosphere(
        radius=0.015,
        subdivisions=1
    )
    left_pupil.visual.vertex_colors = PUPIL_COLOR
    left_pupil.apply_translation([0.52, 0.25, 0.09])
    meshes.append(left_pupil)

    # Right eye
    right_eye_white = trimesh.creation.icosphere(
        radius=0.04,
        subdivisions=2
    )
    right_eye_white.visual.vertex_colors = EYE_COLOR
    right_eye_white.apply_translation([0.5, 0.25, -0.08])
    meshes.append(right_eye_white)

    right_pupil = trimesh.creation.icosphere(
        radius=0.015,
        subdivisions=1
    )
    right_pupil.visual.vertex_colors = PUPIL_COLOR
    right_pupil.apply_translation([0.52, 0.25, -0.09])
    meshes.append(right_pupil)

    # --- TEETH (simple spikes) ---
    for i in range(6):
        tooth = trimesh.creation.cone(
            radius=0.015,
            height=0.04,
            sections=6
        )
        tooth.apply_transform(trimesh.transformations.rotation_matrix(
            -np.pi / 2, [0, 0, 1]
        ))
        tooth.visual.vertex_colors = TEETH_COLOR
        x_pos = 0.55 + (i * 0.03)
        # Alternate top and bottom
        if i % 2 == 0:
            tooth.apply_translation([x_pos, 0.12, 0.05])
        else:
            tooth.apply_translation([x_pos, 0.18, 0.05])
        meshes.append(tooth)

    # --- BELLY (lighter color underside) ---
    belly = trimesh.creation.cylinder(
        radius=0.12,
        height=0.5,
        sections=16
    )
    belly.apply_transform(trimesh.transformations.rotation_matrix(
        np.pi / 2, [0, 1, 0]
    ))
    belly.visual.vertex_colors = BELLY_COLOR
    belly.apply_translation([0, 0.08, 0])  # Lower than body
    meshes.append(belly)

    # --- LEGS (4 short stubby legs) ---
    leg_positions = [
        (0.15, 0.1),   # Front left
        (0.15, -0.1),  # Front right
        (-0.15, 0.1),  # Back left
        (-0.15, -0.1), # Back right
    ]

    for x, z in leg_positions:
        leg = trimesh.creation.cylinder(
            radius=0.05,
            height=0.15,
            sections=8
        )
        leg.visual.vertex_colors = BODY_COLOR
        leg.apply_translation([x, 0.075, z])  # Half height to position on ground
        meshes.append(leg)

        # Add foot (slightly wider)
        foot = trimesh.creation.cylinder(
            radius=0.06,
            height=0.03,
            sections=8
        )
        foot.visual.vertex_colors = BODY_COLOR
        foot.apply_translation([x, 0.015, z])
        meshes.append(foot)

    # --- TAIL (long, tapering) ---
    # Create tail as a series of connected cylinders (tapering)
    tail_segments = 8
    for i in range(tail_segments):
        segment_radius = 0.1 - (i * 0.012)  # Taper from thick to thin
        segment = trimesh.creation.cylinder(
            radius=segment_radius,
            height=0.08,
            sections=12
        )
        segment.apply_transform(trimesh.transformations.rotation_matrix(
            np.pi / 2, [0, 1, 0]
        ))
        # Curve the tail slightly
        y_curve = 0.15 - (i * 0.015)
        segment.visual.vertex_colors = BODY_COLOR
        segment.apply_translation([-0.3 - (i * 0.08), y_curve, 0])
        meshes.append(segment)

    # --- SPINE RIDGES ---
    # Small spikes along the back
    for i in range(10):
        ridge = trimesh.creation.cone(
            radius=0.02,
            height=0.05,
            sections=6
        )
        ridge.visual.vertex_colors = BODY_COLOR
        x_pos = -0.25 + (i * 0.08)
        ridge.apply_translation([x_pos, 0.28, 0])
        meshes.append(ridge)

    # Combine all meshes
    combined_mesh = trimesh.util.concatenate(meshes)

    # Scale to appropriate size (about 0.5 meters long)
    combined_mesh.apply_scale(0.8)

    return combined_mesh


def main():
    """Generate and save the crocodile model."""
    print("Generating Piglet Crocodile 3D model...")

    crocodile = create_crocodile_model()

    # Save as GLB (binary GLTF)
    output_path = "assets/models/characters/piglet_crocodile.glb"
    crocodile.export(output_path)

    print(f"✓ Model saved to: {output_path}")
    print(f"  Vertices: {len(crocodile.vertices)}")
    print(f"  Faces: {len(crocodile.faces)}")
    print(f"  Bounds: {crocodile.bounds}")
    print("\nReady to import into Godot!")


if __name__ == "__main__":
    main()
