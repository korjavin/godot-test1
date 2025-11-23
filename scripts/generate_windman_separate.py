#!/usr/bin/env python3
"""
Generate Windman 3D model with SEPARATE body parts for individual animation.
Each limb is exported as a separate GLB file that can be animated independently.
"""

import numpy as np
import trimesh
from trimesh.creation import cylinder, box, icosphere
from trimesh.transformations import rotation_matrix
from pathlib import Path

class WindmanSeparateMeshGenerator:
    def __init__(self):
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
        cyl_height = max(0.01, height - 2 * radius)
        cylinder_mesh = cylinder(radius=radius, height=cyl_height, sections=segments)

        top_sphere = icosphere(subdivisions=2, radius=radius)
        top_sphere.apply_translation([0, 0, cyl_height/2 + radius])

        bottom_sphere = icosphere(subdivisions=2, radius=radius)
        bottom_sphere.apply_translation([0, 0, -cyl_height/2 - radius])

        return trimesh.util.concatenate([cylinder_mesh, top_sphere, bottom_sphere])

    def create_head_assembly(self):
        """Create head with hair and bandage as one piece"""
        meshes = []

        # Head sphere
        head = icosphere(subdivisions=3, radius=0.12)
        head.visual.vertex_colors = self.colors['skin']
        meshes.append(head)

        # Hair
        hair = icosphere(subdivisions=2, radius=0.125)
        hair.apply_translation([0, 0, 0.06])
        hair.apply_scale([1.0, 1.0, 0.6])
        hair.visual.vertex_colors = self.colors['hair']
        meshes.append(hair)

        # Bandage - top part (blue)
        bandage_top = box(extents=[0.26, 0.05, 0.06])
        bandage_top.apply_translation([0, 0.11, 0.0])
        bandage_top.visual.vertex_colors = self.colors['bandage_blue']
        meshes.append(bandage_top)

        # Bandage - bottom part (red)
        bandage_bottom = box(extents=[0.26, 0.05, 0.03])
        bandage_bottom.apply_translation([0, 0.11, -0.03])
        bandage_bottom.visual.vertex_colors = self.colors['bandage_red']
        meshes.append(bandage_bottom)

        return trimesh.util.concatenate(meshes)

    def create_torso_assembly(self):
        """Create torso with shirt and letters"""
        meshes = []

        # Neck
        neck = cylinder(radius=0.05, height=0.08, sections=16)
        neck.apply_translation([0, 0, 0.16])
        neck.visual.vertex_colors = self.colors['skin']
        meshes.append(neck)

        # Main torso
        torso = icosphere(subdivisions=2, radius=0.15)
        torso.apply_scale([0.93, 0.6, 1.5])
        torso.visual.vertex_colors = self.colors['shirt_blue']
        meshes.append(torso)

        # Letter "W" - simplified as boxes
        w_parts = [
            (box(extents=[0.02, 0.01, 0.12]), [-0.06, 0.091, 0.11]),
            (box(extents=[0.02, 0.01, 0.08]), [0, 0.091, 0.08]),
            (box(extents=[0.02, 0.01, 0.12]), [0.06, 0.091, 0.11]),
        ]
        for mesh, pos in w_parts:
            mesh.apply_translation(pos)
            mesh.visual.vertex_colors = self.colors['letter_white']
            meshes.append(mesh)

        # Line separator
        line = box(extents=[0.14, 0.01, 0.01])
        line.apply_translation([0, 0.091, 0.01])
        line.visual.vertex_colors = self.colors['letter_white']
        meshes.append(line)

        # Letter "M"
        m_parts = [
            (box(extents=[0.02, 0.01, 0.10]), [-0.05, 0.091, -0.05]),
            (box(extents=[0.02, 0.01, 0.10]), [0.05, 0.091, -0.05]),
            (box(extents=[0.02, 0.01, 0.06]), [0, 0.091, -0.04]),
        ]
        for mesh, pos in m_parts:
            mesh.apply_translation(pos)
            mesh.visual.vertex_colors = self.colors['letter_white']
            meshes.append(mesh)

        # Pelvis/Hips
        pelvis = box(extents=[0.26, 0.16, 0.14])
        pelvis.apply_translation([0, 0, -0.29])
        pelvis.visual.vertex_colors = self.colors['shorts_brown']
        meshes.append(pelvis)

        return trimesh.util.concatenate(meshes)

    def create_upper_arm(self):
        """Create upper arm segment"""
        upper_arm = self.create_capsule(height=0.28, radius=0.045, segments=16)
        upper_arm.visual.vertex_colors = self.colors['shirt_blue']
        return upper_arm

    def create_lower_arm(self):
        """Create lower arm (forearm) with hand"""
        meshes = []

        # Forearm
        lower_arm = self.create_capsule(height=0.26, radius=0.04, segments=16)
        lower_arm.visual.vertex_colors = self.colors['skin']
        meshes.append(lower_arm)

        # Hand
        hand = icosphere(subdivisions=2, radius=0.05)
        hand.apply_scale([0.8, 1.0, 1.2])
        hand.apply_translation([0, 0, -0.15])
        hand.visual.vertex_colors = self.colors['skin']
        meshes.append(hand)

        return trimesh.util.concatenate(meshes)

    def create_upper_leg(self):
        """Create upper leg (thigh)"""
        upper_leg = self.create_capsule(height=0.35, radius=0.07, segments=16)
        upper_leg.visual.vertex_colors = self.colors['shorts_brown']
        return upper_leg

    def create_lower_leg(self):
        """Create lower leg (calf) with boot"""
        meshes = []

        # Calf
        lower_leg = self.create_capsule(height=0.40, radius=0.055, segments=16)
        lower_leg.visual.vertex_colors = self.colors['skin']
        meshes.append(lower_leg)

        # Boot
        boot = box(extents=[0.09, 0.20, 0.10])
        boot.apply_translation([0, 0.04, -0.30])
        boot.visual.vertex_colors = self.colors['boots_black']
        meshes.append(boot)

        return trimesh.util.concatenate(meshes)

    def create_fan(self):
        """Create the handheld fan"""
        meshes = []

        # Handle
        handle = cylinder(radius=0.012, height=0.25, sections=16)
        handle.visual.vertex_colors = self.colors['fan_handle']
        meshes.append(handle)

        # Hub
        hub = cylinder(radius=0.03, height=0.02, sections=16)
        hub.apply_transform(rotation_matrix(np.radians(90), [1, 0, 0]))
        hub.apply_translation([0, 0.12, 0.10])
        hub.visual.vertex_colors = [0.2, 0.2, 0.2, 1.0]
        meshes.append(hub)

        # Blades
        for i, color_key in enumerate(['fan_green', 'fan_blue', 'fan_red']):
            angle = i * 120
            blade = icosphere(subdivisions=2, radius=0.05)
            blade.apply_scale([0.3, 2.0, 0.05])
            blade.apply_transform(rotation_matrix(np.radians(angle), [0, 1, 0]))
            blade.apply_translation([0, 0.12, 0.10])
            blade.visual.vertex_colors = self.colors[color_key]
            meshes.append(blade)

        return trimesh.util.concatenate(meshes)

    def generate_and_save(self, output_dir):
        """Generate all body parts and save them"""
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        print("Generating Windman separate mesh parts...")

        parts = {
            'head': self.create_head_assembly(),
            'torso': self.create_torso_assembly(),
            'left_upper_arm': self.create_upper_arm(),
            'left_lower_arm': self.create_lower_arm(),
            'right_upper_arm': self.create_upper_arm(),
            'right_lower_arm': self.create_lower_arm(),
            'left_upper_leg': self.create_upper_leg(),
            'left_lower_leg': self.create_lower_leg(),
            'right_upper_leg': self.create_upper_leg(),
            'right_lower_leg': self.create_lower_leg(),
            'fan': self.create_fan(),
        }

        for name, mesh in parts.items():
            filename = output_dir / f"windman_{name}.glb"
            print(f"  Saving {name}... ({len(mesh.vertices)} vertices)")
            mesh.export(str(filename))

        print(f"\n✓ All parts saved to {output_dir}")
        print(f"  Total parts: {len(parts)}")

def main():
    output_dir = Path("/home/user/godot-test1/assets/models/characters/windman_parts")
    generator = WindmanSeparateMeshGenerator()
    generator.generate_and_save(output_dir)

    print("\n✓ Windman separate mesh parts generated successfully!")
    print("  Next: Create Godot scene that assembles and animates the parts")

if __name__ == "__main__":
    main()
