#!/usr/bin/env python3
"""
Generate Windman 3D model with SEPARATE body parts for individual animation.

Requires: trimesh, numpy, shapely, scipy  (shapely+scipy power the extruded "W"
emblem on the chest). Install with:  pip install trimesh numpy shapely scipy


Each limb is exported as its own GLB file. `scenes/characters/windman_updated.tscn`
assembles them under a `Body` node whose `LeftArm` / `RightArm` / `LeftLeg` /
`RightLeg` containers are rotated at run time by the procedural walk/idle/jump
animation in `scripts/player_controller.gd`.

COORDINATE CONVENTIONS (do not break these — the rig depends on them):
  * trimesh local space is **Z-up**, **+Y = front of the character**. The scene
    rotates each part by Transform3D(1,0,0, 0,0,1, 0,-1,0) so trimesh +Z -> Godot
    +Y (up) and trimesh +Y -> Godot -Z (forward).
  * Every limb part is authored with its **joint pivot at the local origin** and
    the limb extending toward **-Z** (downward / away from the joint), because the
    scene parents the next segment at a fixed downward offset (elbow at -0.27,
    knee at -0.37) and the animation rotates the container around that origin.
  Keep those pivots and spans intact; everything else (girth, colour, the chest
  emblem, hair, headband, fan) is cosmetic and free to change.

Design target (2026-06 canon + reference art):
  * moderately stout, slightly loose build — broad torso, thick neck;
  * a SINGLE large white "W" monogram on the chest (the old two-letter "WM" was
    retired 2026-06-14);
  * blue-over-red eye bandage that wraps the whole head, knotted at the back;
  * short chestnut hair, slightly messy;
  * short blue sleeves over beefy bare (skin) arms;
  * brown knee-length baggy shorts, fully black flat-soled boots;
  * a flat three-blade pinwheel fan (green / blue / red) on a short brown handle.
"""

import numpy as np
import trimesh
from trimesh.creation import cylinder, box, icosphere, extrude_polygon
from trimesh.transformations import rotation_matrix
from shapely.geometry import LineString
from pathlib import Path


class WindmanSeparateMeshGenerator:
    def __init__(self):
        # Palette tuned to the reference art (royal-blue tee, chestnut hair,
        # brick-red lower bandage, medium-brown shorts/handle).
        self.colors = {
            'skin':         [0.93, 0.74, 0.62, 1.0],
            'hair':         [0.32, 0.20, 0.11, 1.0],
            'bandage_blue': [0.20, 0.38, 0.75, 1.0],
            'bandage_red':  [0.72, 0.18, 0.15, 1.0],
            'shirt_blue':   [0.16, 0.33, 0.60, 1.0],
            'letter_white': [0.93, 0.93, 0.93, 1.0],
            'shorts_brown': [0.42, 0.30, 0.18, 1.0],
            'boots_black':  [0.08, 0.08, 0.09, 1.0],
            'fan_handle':   [0.45, 0.30, 0.16, 1.0],
            'fan_hub':      [0.20, 0.20, 0.22, 1.0],
            'fan_green':    [0.20, 0.66, 0.28, 1.0],
            'fan_blue':     [0.16, 0.45, 0.85, 1.0],
            'fan_red':      [0.85, 0.20, 0.18, 1.0],
        }

    # ------------------------------------------------------------------ helpers
    def create_capsule(self, height, radius, segments=16):
        """A capsule (cylinder + hemisphere caps) centred on the origin, axis = Z."""
        cyl_height = max(0.01, height - 2 * radius)
        cylinder_mesh = cylinder(radius=radius, height=cyl_height, sections=segments)

        top_sphere = icosphere(subdivisions=2, radius=radius)
        top_sphere.apply_translation([0, 0, cyl_height / 2])

        bottom_sphere = icosphere(subdivisions=2, radius=radius)
        bottom_sphere.apply_translation([0, 0, -cyl_height / 2])

        return trimesh.util.concatenate([cylinder_mesh, top_sphere, bottom_sphere])

    def _make_w_emblem(self, y_front, color):
        """A single bold white "W" sitting proud of the chest.

        Built as a buffered poly-line (so the strokes join cleanly into one solid
        letter) extruded to a shallow slab, then re-oriented from the extrusion's
        XY plane into the body's X (horizontal) / Z (vertical) chest plane with the
        slab depth pointing forward (+Y).
        """
        # W centre-line in the chest plane: (x, vertical). Outer strokes tall, the
        # middle vertex a clear peak so it reads unmistakably as a "W".
        pts = [(-0.092, 0.135), (-0.044, -0.048), (0.0, 0.072),
               (0.044, -0.048), (0.092, 0.135)]
        poly = LineString(pts).buffer(0.027, cap_style=2, join_style=1)
        emblem = extrude_polygon(poly, height=0.022)

        # extrude lives in (X=horizontal, Y=vertical, Z=depth). Bring vertical to Z
        # and depth to +Y (forward) with a PROPER ROTATION (det +1) so the face
        # winding is preserved — a reflection (det -1) would flip the winding and
        # Godot's back-face culling would hide the front of the letter. Horizontal
        # is mirrored, which is harmless for the symmetric "W".
        rot = np.array([[-1, 0, 0, 0],
                        [0, 0, 1, 0],
                        [0, 1, 0, 0],
                        [0, 0, 0, 1]], dtype=float)
        emblem.apply_transform(rot)
        # Raise onto the chest. Keep the whole slab PROUD of the shirt: the back
        # face must clear the torso surface (y_front) or the convex, faceted torso
        # pokes through the thin emblem and shreds the letter into stripes.
        emblem.apply_translation([0, y_front + 0.012, 0.045])
        emblem.visual.vertex_colors = color
        return emblem

    # -------------------------------------------------------------------- parts
    def create_head_assembly(self):
        """Head + messy hair + wrap-around blue/red eye bandage (knotted at back)."""
        meshes = []

        # Slightly rounded head with soft features.
        head = icosphere(subdivisions=3, radius=0.12)
        head.apply_scale([1.0, 1.02, 1.05])
        head.visual.vertex_colors = self.colors['skin']
        meshes.append(head)

        # Short chestnut hair: a flattened cap on top plus a few spiky tufts so it
        # reads as "short, slightly messy" rather than a smooth helmet.
        hair_cap = icosphere(subdivisions=2, radius=0.125)
        hair_cap.apply_scale([1.0, 1.0, 0.55])
        hair_cap.apply_translation([0, -0.005, 0.075])
        hair_cap.visual.vertex_colors = self.colors['hair']
        meshes.append(hair_cap)

        for (tx, ty, tz, s) in [
            (-0.06, -0.02, 0.10, 0.9), (0.05, -0.03, 0.11, 1.0),
            (0.00, -0.06, 0.12, 0.85), (-0.02, 0.02, 0.115, 0.8),
            (0.07, 0.01, 0.085, 0.75),
        ]:
            tuft = icosphere(subdivisions=1, radius=0.032 * s)
            tuft.apply_scale([1.0, 1.0, 1.4])
            tuft.apply_translation([tx, ty, tz])
            tuft.visual.vertex_colors = self.colors['hair']
            meshes.append(tuft)

        # Eye bandage: two stacked discs wrapping the head at eye level. The band
        # is a touch larger than the head so it sits proud of the face and fully
        # covers the eyes (it's a blindfold). Blue on top, red below.
        band_blue = cylinder(radius=0.127, height=0.040, sections=24)
        band_blue.apply_translation([0, 0, 0.012])
        band_blue.visual.vertex_colors = self.colors['bandage_blue']
        meshes.append(band_blue)

        band_red = cylinder(radius=0.126, height=0.026, sections=24)
        band_red.apply_translation([0, 0, -0.020])
        band_red.visual.vertex_colors = self.colors['bandage_red']
        meshes.append(band_red)

        # Small knot at the back of the head with two short tails drooping down
        # close to the nape (kept tight so they don't read as a paddle).
        knot = icosphere(subdivisions=2, radius=0.020)
        knot.apply_translation([0.0, -0.122, -0.005])
        knot.visual.vertex_colors = self.colors['bandage_blue']
        meshes.append(knot)

        for (tx, tilt_deg, length) in [(-0.020, 10, 0.075), (0.018, -8, 0.060)]:
            tail = box(extents=[0.016, 0.010, length])
            tail.apply_transform(rotation_matrix(np.radians(tilt_deg), [0, 1, 0]))
            tail.apply_translation([tx, -0.118, -0.04 - length / 2])
            tail.visual.vertex_colors = self.colors['bandage_blue']
            meshes.append(tail)

        return trimesh.util.concatenate(meshes)

    def create_torso_assembly(self):
        """Stout torso (shirt) + thick neck + single big "W" + shorts waistband."""
        meshes = []

        # Thick neck.
        neck = cylinder(radius=0.062, height=0.09, sections=16)
        neck.apply_translation([0, 0, 0.16])
        neck.visual.vertex_colors = self.colors['skin']
        meshes.append(neck)

        # Broad torso — wider in X, taller in Z, only moderately deep in Y so the
        # build reads "stout" without becoming a sphere. The shoulders are filled
        # out with a wider block up top so the tee looks broad, not egg-shaped.
        torso = icosphere(subdivisions=3, radius=0.15)
        torso.apply_scale([1.12, 0.78, 1.6])
        torso.visual.vertex_colors = self.colors['shirt_blue']
        meshes.append(torso)

        shoulders = icosphere(subdivisions=2, radius=0.15)
        shoulders.apply_scale([1.45, 0.7, 0.55])
        shoulders.apply_translation([0, 0, 0.135])
        shoulders.visual.vertex_colors = self.colors['shirt_blue']
        meshes.append(shoulders)

        # Single large white "W" monogram on the chest.
        meshes.append(self._make_w_emblem(y_front=0.117, color=self.colors['letter_white']))

        # Shorts waistband / pelvis block at the bottom of the torso part.
        pelvis = box(extents=[0.30, 0.19, 0.16])
        pelvis.apply_translation([0, 0, -0.30])
        pelvis.visual.vertex_colors = self.colors['shorts_brown']
        meshes.append(pelvis)

        return trimesh.util.concatenate(meshes)

    def create_upper_arm(self):
        """Beefy bare (skin) upper arm with a short blue t-shirt sleeve at the top.

        The pivot (shoulder) is at the local origin so the rig rotates correctly,
        but the geometry HANGS DOWN toward -Z (shoulder at 0, elbow near -0.27) so
        the arm reads as hanging from the shoulder instead of straddling it.
        """
        meshes = []

        arm = self.create_capsule(height=0.30, radius=0.058, segments=16)
        arm.apply_translation([0, 0, -0.15])
        arm.visual.vertex_colors = self.colors['skin']
        meshes.append(arm)

        # Rounded shoulder cap right at the joint.
        shoulder = icosphere(subdivisions=2, radius=0.072)
        shoulder.apply_scale([1.0, 1.0, 0.85])
        shoulder.apply_translation([0, 0, -0.01])
        shoulder.visual.vertex_colors = self.colors['shirt_blue']
        meshes.append(shoulder)

        # Short flared sleeve covering just the top of the upper arm.
        sleeve = cylinder(radius=0.071, height=0.10, sections=16)
        sleeve.apply_translation([0, 0, -0.06])
        sleeve.visual.vertex_colors = self.colors['shirt_blue']
        meshes.append(sleeve)

        return trimesh.util.concatenate(meshes)

    def create_lower_arm(self):
        """Forearm (skin) tapering into a hand. Pivot (elbow) at origin, runs -Z."""
        meshes = []

        forearm = self.create_capsule(height=0.27, radius=0.050, segments=16)
        forearm.visual.vertex_colors = self.colors['skin']
        meshes.append(forearm)

        hand = icosphere(subdivisions=2, radius=0.055)
        hand.apply_scale([0.85, 1.0, 1.2])
        hand.apply_translation([0, 0, -0.16])
        hand.visual.vertex_colors = self.colors['skin']
        meshes.append(hand)

        return trimesh.util.concatenate(meshes)

    def create_upper_leg(self):
        """Baggy brown shorts thigh. Pivot (hip) at origin; geometry hangs to -Z
        (hip at 0, knee near -0.37) so the thigh fills the hip-to-knee gap."""
        leg = self.create_capsule(height=0.42, radius=0.084, segments=16)
        leg.apply_translation([0, 0, -0.19])
        leg.visual.vertex_colors = self.colors['shorts_brown']
        return leg

    def create_lower_leg(self):
        """Bare calf (skin) ending in a black flat-soled boot. Pivot (knee) at origin."""
        meshes = []

        calf = self.create_capsule(height=0.40, radius=0.058, segments=16)
        calf.visual.vertex_colors = self.colors['skin']
        meshes.append(calf)

        # Boot upper (ankle-height), forward-biased over the foot.
        boot = box(extents=[0.095, 0.17, 0.12])
        boot.apply_translation([0, 0.035, -0.30])
        boot.visual.vertex_colors = self.colors['boots_black']
        meshes.append(boot)

        # Rounded toe cap.
        toe = icosphere(subdivisions=2, radius=0.06)
        toe.apply_scale([0.8, 1.1, 0.55])
        toe.apply_translation([0, 0.12, -0.335])
        toe.visual.vertex_colors = self.colors['boots_black']
        meshes.append(toe)

        # Wider, flat sole slab at the very bottom.
        sole = box(extents=[0.105, 0.26, 0.035])
        sole.apply_translation([0, 0.045, -0.358])
        sole.visual.vertex_colors = self.colors['boots_black']
        meshes.append(sole)

        return trimesh.util.concatenate(meshes)

    def create_fan(self):
        """Flat three-blade pinwheel fan on a short brown handle.

        Authored Z-up / +Y-front like the limbs: the handle runs along Z with the
        grip at the top (Z ~ 0, where the hand holds it) and the pinwheel at the
        bottom (-Z). The blades fan out in the X-Z plane (flat face along Y), so
        once the scene applies the limb rotation the handle hangs down and the
        pinwheel faces forward. Green up, blue lower-left, red lower-right.
        """
        meshes = []

        # Short wood-textured handle; grip end near Z=0, tip toward -Z.
        handle = cylinder(radius=0.013, height=0.17, sections=16)
        handle.apply_translation([0, 0, -0.065])
        handle.visual.vertex_colors = self.colors['fan_handle']
        meshes.append(handle)

        # Pinwheel centre at the bottom tip, nudged forward (+Y) off the grip.
        hub_center = np.array([0.0, 0.022, -0.155])

        hub = cylinder(radius=0.016, height=0.016, sections=20)
        hub.apply_transform(rotation_matrix(np.radians(90), [1, 0, 0]))  # face +Y
        hub.apply_translation(hub_center)
        hub.visual.vertex_colors = self.colors['fan_hub']
        meshes.append(hub)

        # rotation_matrix(a, +Y) sends +X -> (cos a, 0, -sin a); pick angles so the
        # petals land up / lower-left / lower-right.
        blade_specs = [('fan_green', -90), ('fan_red', 30), ('fan_blue', 150)]
        for color_key, angle_deg in blade_specs:
            petal = icosphere(subdivisions=2, radius=0.055)
            # Long & rounded radially (+X), thin in Y (flat), wide in Z (petal).
            petal.apply_scale([1.8, 0.16, 1.05])
            petal.apply_translation([0.062, 0.0, 0.0])
            petal.apply_transform(rotation_matrix(np.radians(angle_deg), [0, 1, 0]))
            petal.apply_translation(hub_center)
            petal.visual.vertex_colors = self.colors[color_key]
            meshes.append(petal)

        return trimesh.util.concatenate(meshes)

    # ------------------------------------------------------------------- driver
    def generate_and_save(self, output_dir):
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

        print(f"\n  All parts saved to {output_dir}")
        print(f"  Total parts: {len(parts)}")


def main():
    # Output next to this repo regardless of where the script is run from.
    repo_root = Path(__file__).resolve().parent.parent
    output_dir = repo_root / "assets" / "models" / "characters" / "windman_parts"

    generator = WindmanSeparateMeshGenerator()
    generator.generate_and_save(output_dir)

    print("\n  Windman separate mesh parts generated successfully!")
    print("  Assembled + animated by scenes/characters/windman_updated.tscn")


if __name__ == "__main__":
    main()
