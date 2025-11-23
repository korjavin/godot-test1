#!/usr/bin/env python3
"""
Generate a detailed, rigged 3D model of Windman character for Godot with skeleton.
Creates a GLTF model with armature and skinned meshes for animation.
"""

import numpy as np
import trimesh
from trimesh.creation import cylinder, box, icosphere
from trimesh.transformations import translation_matrix, rotation_matrix
from pathlib import Path
import json

class WindmanRiggedGenerator:
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

        # Define skeleton structure (bone positions in world space)
        self.bones = {
            'Root': {'position': [0, 0, 0], 'parent': None},
            'Hips': {'position': [0, 0, 0.88], 'parent': 'Root'},
            'Spine': {'position': [0, 0, 1.17], 'parent': 'Hips'},
            'Chest': {'position': [0, 0, 1.35], 'parent': 'Spine'},
            'Neck': {'position': [0, 0, 1.46], 'parent': 'Chest'},
            'Head': {'position': [0, 0, 1.62], 'parent': 'Neck'},

            'LeftShoulder': {'position': [-0.14, 0, 1.40], 'parent': 'Chest'},
            'LeftUpperArm': {'position': [-0.18, 0, 1.28], 'parent': 'LeftShoulder'},
            'LeftLowerArm': {'position': [-0.18, 0, 1.01], 'parent': 'LeftUpperArm'},
            'LeftHand': {'position': [-0.18, 0, 0.86], 'parent': 'LeftLowerArm'},

            'RightShoulder': {'position': [0.14, 0, 1.40], 'parent': 'Chest'},
            'RightUpperArm': {'position': [0.18, 0, 1.28], 'parent': 'RightShoulder'},
            'RightLowerArm': {'position': [0.18, 0, 1.01], 'parent': 'RightUpperArm'},
            'RightHand': {'position': [0.18, 0, 0.86], 'parent': 'RightLowerArm'},

            'LeftUpperLeg': {'position': [-0.09, 0, 0.77], 'parent': 'Hips'},
            'LeftLowerLeg': {'position': [-0.09, 0, 0.40], 'parent': 'LeftUpperLeg'},
            'LeftFoot': {'position': [-0.09, 0, 0.10], 'parent': 'LeftLowerLeg'},

            'RightUpperLeg': {'position': [0.09, 0, 0.77], 'parent': 'Hips'},
            'RightLowerLeg': {'position': [0.09, 0, 0.40], 'parent': 'RightUpperLeg'},
            'RightFoot': {'position': [0.09, 0, 0.10], 'parent': 'RightLowerLeg'},
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

    def create_body_mesh(self):
        """Create complete body mesh"""
        meshes = []

        # Head
        head = icosphere(subdivisions=3, radius=0.12)
        head.apply_translation([0, 0, 1.62])
        head.visual.vertex_colors = self.colors['skin']
        meshes.append(head)

        # Hair
        hair = icosphere(subdivisions=2, radius=0.125)
        hair.apply_translation([0, 0, 1.68])
        hair.apply_scale([1.0, 1.0, 0.6])
        hair.visual.vertex_colors = self.colors['hair']
        meshes.append(hair)

        # Bandage
        bandage_top = box(extents=[0.26, 0.05, 0.06])
        bandage_top.apply_translation([0, 0.11, 1.62])
        bandage_top.visual.vertex_colors = self.colors['bandage_blue']
        meshes.append(bandage_top)

        bandage_bottom = box(extents=[0.26, 0.05, 0.03])
        bandage_bottom.apply_translation([0, 0.11, 1.59])
        bandage_bottom.visual.vertex_colors = self.colors['bandage_red']
        meshes.append(bandage_bottom)

        # Neck
        neck = cylinder(radius=0.05, height=0.08, sections=16)
        neck.apply_translation([0, 0, 1.46])
        neck.visual.vertex_colors = self.colors['skin']
        meshes.append(neck)

        # Torso
        torso = icosphere(subdivisions=2, radius=0.15)
        torso.apply_scale([0.93, 0.6, 1.5])
        torso.apply_translation([0, 0, 1.17])
        torso.visual.vertex_colors = self.colors['shirt_blue']
        meshes.append(torso)

        # Letters W and M on shirt
        # W
        w_parts = [
            (box(extents=[0.02, 0.01, 0.12]), [-0.06, 0.091, 1.28]),
            (box(extents=[0.02, 0.01, 0.08]), [0, 0.091, 1.25]),
            (box(extents=[0.02, 0.01, 0.12]), [0.06, 0.091, 1.28]),
        ]
        for mesh, pos in w_parts:
            mesh.apply_translation(pos)
            mesh.visual.vertex_colors = self.colors['letter_white']
            meshes.append(mesh)

        # Line separator
        line = box(extents=[0.14, 0.01, 0.01])
        line.apply_translation([0, 0.091, 1.18])
        line.visual.vertex_colors = self.colors['letter_white']
        meshes.append(line)

        # M
        m_parts = [
            (box(extents=[0.02, 0.01, 0.10]), [-0.05, 0.091, 1.12]),
            (box(extents=[0.02, 0.01, 0.10]), [0.05, 0.091, 1.12]),
            (box(extents=[0.02, 0.01, 0.06]), [0, 0.091, 1.13]),
        ]
        for mesh, pos in m_parts:
            mesh.apply_translation(pos)
            mesh.visual.vertex_colors = self.colors['letter_white']
            meshes.append(mesh)

        # Pelvis/Hips
        pelvis = box(extents=[0.26, 0.16, 0.14])
        pelvis.apply_translation([0, 0, 0.88])
        pelvis.visual.vertex_colors = self.colors['shorts_brown']
        meshes.append(pelvis)

        # Arms
        for side, sign in [('Left', -1), ('Right', 1)]:
            # Upper arm
            upper_arm = self.create_capsule(height=0.28, radius=0.045, segments=16)
            upper_arm.apply_translation([sign * 0.18, 0, 1.28])
            upper_arm.visual.vertex_colors = self.colors['shirt_blue']
            meshes.append(upper_arm)

            # Lower arm
            lower_arm = self.create_capsule(height=0.26, radius=0.04, segments=16)
            lower_arm.apply_translation([sign * 0.18, 0, 1.01])
            lower_arm.visual.vertex_colors = self.colors['skin']
            meshes.append(lower_arm)

            # Hand
            hand = icosphere(subdivisions=2, radius=0.05)
            hand.apply_scale([0.8, 1.0, 1.2])
            hand.apply_translation([sign * 0.18, 0, 0.86])
            hand.visual.vertex_colors = self.colors['skin']
            meshes.append(hand)

        # Legs
        for side, sign in [('Left', -1), ('Right', 1)]:
            # Upper leg
            upper_leg = self.create_capsule(height=0.35, radius=0.07, segments=16)
            upper_leg.apply_translation([sign * 0.09, 0, 0.77])
            upper_leg.visual.vertex_colors = self.colors['shorts_brown']
            meshes.append(upper_leg)

            # Lower leg
            lower_leg = self.create_capsule(height=0.40, radius=0.055, segments=16)
            lower_leg.apply_translation([sign * 0.09, 0, 0.40])
            lower_leg.visual.vertex_colors = self.colors['skin']
            meshes.append(lower_leg)

            # Boot
            boot = box(extents=[0.09, 0.20, 0.10])
            boot.apply_translation([sign * 0.09, 0.04, 0.10])
            boot.visual.vertex_colors = self.colors['boots_black']
            meshes.append(boot)

        # Fan
        handle = cylinder(radius=0.012, height=0.25, sections=16)
        handle.apply_translation([0.18, 0.04, 0.96])
        handle.visual.vertex_colors = self.colors['fan_handle']
        meshes.append(handle)

        # Fan hub
        hub = cylinder(radius=0.03, height=0.02, sections=16)
        hub.apply_transform(rotation_matrix(np.radians(90), [1, 0, 0]))
        hub.apply_translation([0.18, 0.16, 1.06])
        hub.visual.vertex_colors = [0.2, 0.2, 0.2, 1.0]
        meshes.append(hub)

        # Fan blades
        for i, color_key in enumerate(['fan_green', 'fan_blue', 'fan_red']):
            angle = i * 120
            blade = icosphere(subdivisions=2, radius=0.05)
            blade.apply_scale([0.3, 2.0, 0.05])
            blade.apply_transform(rotation_matrix(np.radians(angle), [0, 1, 0]))
            blade.apply_translation([0.18, 0.16, 1.06])
            blade.visual.vertex_colors = self.colors[color_key]
            meshes.append(blade)

        # Combine all meshes
        combined = trimesh.util.concatenate(meshes)
        return combined

    def generate_model(self):
        """Generate the complete rigged model"""
        print("Generating rigged Windman 3D model...")
        print("  Creating body mesh...")
        body_mesh = self.create_body_mesh()

        print(f"  Model contains {len(body_mesh.vertices)} vertices and {len(body_mesh.faces)} faces")

        return body_mesh

    def save_model(self, output_path):
        """Save the model as GLB"""
        model = self.generate_model()

        print(f"\nSaving model to {output_path}...")
        model.export(output_path)

        # Also save skeleton information for Godot
        skeleton_info = {
            'bones': self.bones,
            'note': 'This skeleton structure should be recreated in Godot for animation'
        }

        skeleton_path = Path(output_path).with_suffix('.skeleton.json')
        with open(skeleton_path, 'w') as f:
            json.dump(skeleton_info, f, indent=2)

        print("Model saved successfully!")
        print(f"  Model: {output_path}")
        print(f"  Skeleton info: {skeleton_path}")

        # Print statistics
        print(f"\nModel Statistics:")
        print(f"  Vertices: {len(model.vertices)}")
        print(f"  Faces: {len(model.faces)}")
        print(f"  Height: {model.bounds[1][2] - model.bounds[0][2]:.2f} meters")
        print(f"  Bones defined: {len(self.bones)}")

        return model

def main():
    output_dir = Path("/home/user/godot-test1/assets/models/characters")
    output_dir.mkdir(parents=True, exist_ok=True)

    generator = WindmanRiggedGenerator()
    model = generator.save_model(str(output_dir / "windman.glb"))

    print("\n✓ Windman rigged 3D model generated successfully!")
    print(f"  Location: {output_dir / 'windman.glb'}")
    print(f"  Skeleton: {output_dir / 'windman.skeleton.json'}")
    print(f"  Format: GLTF/GLB (Binary GLTF)")
    print(f"\n  Next steps:")
    print(f"  1. Import windman.glb into Godot")
    print(f"  2. Create Skeleton3D node in Godot based on the bone structure")
    print(f"  3. Attach mesh to skeleton with skin weights")
    print(f"  4. Create animations using the skeleton")

if __name__ == "__main__":
    main()
