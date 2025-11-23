#!/usr/bin/env python3
"""
Generate a detailed 3D model of Windman character for Godot.
Creates a GLTF model with proper body parts for animation.
"""

import numpy as np
import trimesh
from trimesh.creation import cylinder, box, icosphere, uv_sphere
from trimesh.transformations import translation_matrix, rotation_matrix, concatenate_matrices
import json
from pathlib import Path

class WindmanModelGenerator:
    def __init__(self):
        self.meshes = []
        self.mesh_names = []
        self.colors = {
            'skin': [0.95, 0.76, 0.65, 1.0],
            'hair': [0.4, 0.26, 0.13, 1.0],
            'bandage_blue': [0.2, 0.4, 0.8, 1.0],
            'bandage_red': [0.8, 0.2, 0.2, 1.0],
            'shirt_blue': [0.15, 0.4, 0.7, 1.0],
            'letter_white': [0.95, 0.95, 0.95, 1.0],
            'shorts_brown': [0.5, 0.35, 0.2, 1.0],
            'boots_black': [0.1, 0.1, 0.1, 1.0],
            'fan_handle': [0.4, 0.26, 0.13, 1.0],
            'fan_green': [0.2, 0.7, 0.3, 0.7],
            'fan_blue': [0.2, 0.5, 0.8, 0.7],
            'fan_red': [0.8, 0.3, 0.2, 0.7],
        }

    def create_capsule(self, height, radius, segments=16):
        """Create a capsule (cylinder with hemisphere caps)"""
        cyl_height = height - 2 * radius
        cylinder_mesh = cylinder(radius=radius, height=cyl_height, sections=segments)

        top_sphere = icosphere(subdivisions=2, radius=radius)
        top_sphere.apply_translation([0, 0, cyl_height/2 + radius])

        bottom_sphere = icosphere(subdivisions=2, radius=radius)
        bottom_sphere.apply_translation([0, 0, -cyl_height/2 - radius])

        return trimesh.util.concatenate([cylinder_mesh, top_sphere, bottom_sphere])

    def create_head(self):
        """Create the head with proper proportions"""
        # Head sphere
        head = icosphere(subdivisions=3, radius=0.12)
        head.apply_translation([0, 0, 1.62])
        head.visual.vertex_colors = self.colors['skin']

        # Hair
        hair = icosphere(subdivisions=2, radius=0.125)
        hair.apply_translation([0, 0, 1.68])
        hair.apply_scale([1.0, 1.0, 0.6])
        hair.visual.vertex_colors = self.colors['hair']

        # Bandage - top part (blue)
        bandage_top = box(extents=[0.26, 0.05, 0.06])
        bandage_top.apply_translation([0, 0.11, 1.62])
        bandage_top.visual.vertex_colors = self.colors['bandage_blue']

        # Bandage - bottom part (red)
        bandage_bottom = box(extents=[0.26, 0.05, 0.03])
        bandage_bottom.apply_translation([0, 0.11, 1.59])
        bandage_bottom.visual.vertex_colors = self.colors['bandage_red']

        # Combine head parts
        head_combined = trimesh.util.concatenate([head, hair, bandage_top, bandage_bottom])
        return head_combined

    def create_neck(self):
        """Create neck"""
        neck = cylinder(radius=0.05, height=0.08, sections=16)
        neck.apply_translation([0, 0, 1.46])
        neck.visual.vertex_colors = self.colors['skin']
        return neck

    def create_torso(self):
        """Create torso with T-shirt and letters"""
        # Main torso body
        torso_body = box(extents=[0.28, 0.18, 0.45])
        torso_body.apply_translation([0, 0, 1.17])
        torso_body.visual.vertex_colors = self.colors['shirt_blue']

        # Add slight rounding to torso
        torso_round = icosphere(subdivisions=2, radius=0.15)
        torso_round.apply_scale([0.93, 0.6, 1.5])
        torso_round.apply_translation([0, 0, 1.17])
        torso_round.visual.vertex_colors = self.colors['shirt_blue']

        # Letter "W" - create using boxes
        w_left = box(extents=[0.02, 0.01, 0.12])
        w_left.apply_translation([-0.06, 0.091, 1.28])
        w_left.visual.vertex_colors = self.colors['letter_white']

        w_middle = box(extents=[0.02, 0.01, 0.08])
        w_middle.apply_translation([0, 0.091, 1.25])
        w_middle.visual.vertex_colors = self.colors['letter_white']

        w_right = box(extents=[0.02, 0.01, 0.12])
        w_right.apply_translation([0.06, 0.091, 1.28])
        w_right.visual.vertex_colors = self.colors['letter_white']

        w_connect_left = box(extents=[0.04, 0.01, 0.02])
        w_connect_left.apply_translation([-0.03, 0.091, 1.23])
        w_connect_left.apply_transform(rotation_matrix(np.radians(30), [0, 1, 0]))
        w_connect_left.visual.vertex_colors = self.colors['letter_white']

        w_connect_right = box(extents=[0.04, 0.01, 0.02])
        w_connect_right.apply_translation([0.03, 0.091, 1.23])
        w_connect_right.apply_transform(rotation_matrix(np.radians(-30), [0, 1, 0]))
        w_connect_right.visual.vertex_colors = self.colors['letter_white']

        # Horizontal line separator
        line = box(extents=[0.14, 0.01, 0.01])
        line.apply_translation([0, 0.091, 1.18])
        line.visual.vertex_colors = self.colors['letter_white']

        # Letter "M"
        m_left = box(extents=[0.02, 0.01, 0.10])
        m_left.apply_translation([-0.05, 0.091, 1.12])
        m_left.visual.vertex_colors = self.colors['letter_white']

        m_right = box(extents=[0.02, 0.01, 0.10])
        m_right.apply_translation([0.05, 0.091, 1.12])
        m_right.visual.vertex_colors = self.colors['letter_white']

        m_middle = box(extents=[0.02, 0.01, 0.06])
        m_middle.apply_translation([0, 0.091, 1.13])
        m_middle.visual.vertex_colors = self.colors['letter_white']

        m_connect_left = box(extents=[0.03, 0.01, 0.02])
        m_connect_left.apply_translation([-0.025, 0.091, 1.155])
        m_connect_left.apply_transform(rotation_matrix(np.radians(30), [0, 1, 0]))
        m_connect_left.visual.vertex_colors = self.colors['letter_white']

        m_connect_right = box(extents=[0.03, 0.01, 0.02])
        m_connect_right.apply_translation([0.025, 0.091, 1.155])
        m_connect_right.apply_transform(rotation_matrix(np.radians(-30), [0, 1, 0]))
        m_connect_right.visual.vertex_colors = self.colors['letter_white']

        torso = trimesh.util.concatenate([
            torso_round, w_left, w_middle, w_right, w_connect_left, w_connect_right,
            line, m_left, m_right, m_middle, m_connect_left, m_connect_right
        ])
        return torso

    def create_arm(self, side='left'):
        """Create arm (upper arm, lower arm, hand)"""
        sign = 1 if side == 'left' else -1

        # Upper arm
        upper_arm = self.create_capsule(height=0.28, radius=0.045, segments=16)
        upper_arm.apply_translation([sign * 0.18, 0, 1.28])
        upper_arm.visual.vertex_colors = self.colors['shirt_blue']

        # Lower arm (forearm)
        lower_arm = self.create_capsule(height=0.26, radius=0.04, segments=16)
        lower_arm.apply_translation([sign * 0.18, 0, 1.01])
        lower_arm.visual.vertex_colors = self.colors['skin']

        # Hand
        hand = icosphere(subdivisions=2, radius=0.05)
        hand.apply_scale([0.8, 1.0, 1.2])
        hand.apply_translation([sign * 0.18, 0, 0.86])
        hand.visual.vertex_colors = self.colors['skin']

        arm = trimesh.util.concatenate([upper_arm, lower_arm, hand])
        return arm

    def create_leg(self, side='left'):
        """Create leg (upper leg, lower leg, foot)"""
        sign = 1 if side == 'left' else -1

        # Upper leg (in shorts)
        upper_leg = self.create_capsule(height=0.35, radius=0.07, segments=16)
        upper_leg.apply_translation([sign * 0.09, 0, 0.77])
        upper_leg.visual.vertex_colors = self.colors['shorts_brown']

        # Lower leg
        lower_leg = self.create_capsule(height=0.40, radius=0.055, segments=16)
        lower_leg.apply_translation([sign * 0.09, 0, 0.40])
        lower_leg.visual.vertex_colors = self.colors['skin']

        # Boot
        boot = box(extents=[0.09, 0.20, 0.10])
        boot.apply_translation([sign * 0.09, 0.04, 0.10])
        boot.visual.vertex_colors = self.colors['boots_black']

        leg = trimesh.util.concatenate([upper_leg, lower_leg, boot])
        return leg

    def create_pelvis(self):
        """Create pelvis/hip area"""
        pelvis = box(extents=[0.26, 0.16, 0.14])
        pelvis.apply_translation([0, 0, 0.88])
        pelvis.visual.vertex_colors = self.colors['shorts_brown']
        return pelvis

    def create_fan(self):
        """Create the handheld fan with colored blades"""
        # Handle
        handle = cylinder(radius=0.012, height=0.25, sections=16)
        handle.apply_translation([0.18, 0.04, 0.96])
        handle.visual.vertex_colors = self.colors['fan_handle']

        # Central hub
        hub = cylinder(radius=0.03, height=0.02, sections=16)
        hub.apply_transform(rotation_matrix(np.radians(90), [1, 0, 0]))
        hub.apply_translation([0.18, 0.16, 1.06])
        hub.visual.vertex_colors = [0.2, 0.2, 0.2, 1.0]

        # Create three fan blades at 120-degree intervals
        blades = []
        colors = ['fan_green', 'fan_blue', 'fan_red']

        for i, color_key in enumerate(colors):
            angle = i * 120
            # Blade shape - elongated ellipsoid
            blade = icosphere(subdivisions=2, radius=0.05)
            blade.apply_scale([0.3, 2.0, 0.05])

            # Position and rotate blade
            blade.apply_transform(rotation_matrix(np.radians(angle), [0, 1, 0]))
            blade.apply_translation([0.18, 0.16, 1.06])

            blade.visual.vertex_colors = self.colors[color_key]
            blades.append(blade)

        fan = trimesh.util.concatenate([handle, hub] + blades)
        return fan

    def generate_model(self):
        """Generate the complete Windman model"""
        print("Generating Windman 3D model...")

        # Create all body parts
        print("  Creating head...")
        head = self.create_head()
        self.meshes.append(head)
        self.mesh_names.append("Head")

        print("  Creating neck...")
        neck = self.create_neck()
        self.meshes.append(neck)
        self.mesh_names.append("Neck")

        print("  Creating torso...")
        torso = self.create_torso()
        self.meshes.append(torso)
        self.mesh_names.append("Torso")

        print("  Creating pelvis...")
        pelvis = self.create_pelvis()
        self.meshes.append(pelvis)
        self.mesh_names.append("Pelvis")

        print("  Creating arms...")
        left_arm = self.create_arm('left')
        self.meshes.append(left_arm)
        self.mesh_names.append("LeftArm")

        right_arm = self.create_arm('right')
        self.meshes.append(right_arm)
        self.mesh_names.append("RightArm")

        print("  Creating legs...")
        left_leg = self.create_leg('left')
        self.meshes.append(left_leg)
        self.mesh_names.append("LeftLeg")

        right_leg = self.create_leg('right')
        self.meshes.append(right_leg)
        self.mesh_names.append("RightLeg")

        print("  Creating fan...")
        fan = self.create_fan()
        self.meshes.append(fan)
        self.mesh_names.append("Fan")

        # Combine all meshes
        print("  Combining meshes...")
        full_model = trimesh.util.concatenate(self.meshes)

        return full_model

    def save_model(self, output_path):
        """Save the model as GLTF"""
        model = self.generate_model()

        print(f"\nSaving model to {output_path}...")
        model.export(output_path)
        print("Model saved successfully!")

        # Print model statistics
        print(f"\nModel Statistics:")
        print(f"  Vertices: {len(model.vertices)}")
        print(f"  Faces: {len(model.faces)}")
        print(f"  Bounding box: {model.bounds}")
        print(f"  Height: {model.bounds[1][2] - model.bounds[0][2]:.2f} meters")

        return model

def main():
    # Create output directory if it doesn't exist
    output_dir = Path("/home/user/godot-test1/assets/models/characters")
    output_dir.mkdir(parents=True, exist_ok=True)

    # Generate the model
    generator = WindmanModelGenerator()
    model = generator.save_model(str(output_dir / "windman.glb"))

    print("\n✓ Windman 3D model generated successfully!")
    print(f"  Location: {output_dir / 'windman.glb'}")
    print(f"  Format: GLTF/GLB (Binary GLTF)")
    print(f"  Ready for import into Godot!")

if __name__ == "__main__":
    main()
