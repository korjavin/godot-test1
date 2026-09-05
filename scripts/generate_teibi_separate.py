#!/usr/bin/env python3
"""
Generate Teibi 3D model with SEPARATE body parts for individual animation.

Requires: trimesh, numpy  (shapely+scipy are NOT needed here — Teibi has no
extruded chest letter; a small collar/placket on the polo is built from plain
boxes/cylinders). Install with:  pip install trimesh numpy shapely scipy

Each limb is exported as its own GLB file. `scenes/characters/teibi.tscn`
assembles them under a `Body` node whose `LeftArm` / `RightArm` / `LeftLeg` /
`RightLeg` containers are rotated at run time by the procedural walk/idle/jump
animation in `scripts/player_controller.gd`. (Teibi also has a runtime "Resize"
ability that scales the whole model on the player side — that only needs the
standard node names, nothing special in the geometry.)

COORDINATE CONVENTIONS (do not break these — the rig depends on them):
  * trimesh local space is **Z-up**, **+Y = front of the character**. The scene
    rotates each part by Transform3D(1,0,0, 0,0,1, 0,-1,0) so trimesh +Z -> Godot
    +Y (up) and trimesh +Y -> Godot -Z (forward).
  * Every limb part is authored with its **joint pivot at the local origin** and
    the limb extending toward **-Z** (downward / away from the joint), because the
    scene parents the next segment at a fixed downward offset (elbow at -0.27,
    knee at -0.37) and the animation rotates the container around that origin.
  Keep those pivots and spans intact; everything else (girth, colour, the beret,
  collar, placket, belt) is cosmetic and free to change.

Design target (reference image + 2026-06 canon):
  * ordinary man, average height (~1.8 m), medium / slightly lean build,
    natural human proportions;
  * medium skin tone, short dark hair, clean-shaven, calm friendly face;
  * SIGNATURE: a dark navy classic French beret, slightly tilted, soft and
    rounded, with a small nub at the top centre — this is the defining feature;
  * a mustard / golden-yellow LONG-SLEEVE polo/henley: small fold-over collar and
    a short button placket at the chest. Sleeves run the WHOLE arm (upper + lower)
    down to the wrists — only the hands are skin;
  * dark navy/charcoal FULL-LENGTH straight trousers with a dark belt at the
    waist — dark all the way down to the shoes (NOT shorts);
  * low dark-brown/black shoes (flat-soled, plain).
"""

import numpy as np
import trimesh
from trimesh.creation import cylinder, box, icosphere
from trimesh.transformations import rotation_matrix
from pathlib import Path

# THE ONE EXPORT SEAM for every model in this game (bead godot-test1-y1o.21,
# owner ruling 2026-09-05 "facet ALL"): it unmerges the mesh and writes flat
# per-face normals. It lives in predator_parts.py because the predators got it
# first — read its docstring before touching anything about normals here.
import sys  # noqa: E402
sys.path.insert(0, str(Path(__file__).resolve().parent))
from predator_parts import export_faceted  # noqa: E402


class TeibiSeparateMeshGenerator:
    def __init__(self):
        # Palette tuned to the reference art (mustard long-sleeve polo, dark navy
        # beret, charcoal-navy trousers, dark-brown shoes, medium skin).
        self.colors = {
            'skin':         [0.86, 0.66, 0.54, 1.0],
            'hair':         [0.17, 0.12, 0.09, 1.0],
            # Deep dark navy so the beret never reads as a washed-out gray cap;
            # a touch of blue keeps it "navy" rather than flat black under the
            # in-game cel/toon shading.
            'beret_navy':   [0.07, 0.09, 0.19, 1.0],
            'shirt_mustard': [0.87, 0.66, 0.17, 1.0],
            'shirt_collar': [0.74, 0.55, 0.12, 1.0],   # slightly darker mustard
            'placket':      [0.70, 0.52, 0.11, 1.0],   # shaded button placket
            'button':       [0.55, 0.40, 0.08, 1.0],
            'trousers':     [0.20, 0.22, 0.28, 1.0],
            'belt':         [0.11, 0.10, 0.11, 1.0],
            'belt_buckle':  [0.55, 0.50, 0.30, 1.0],
            'shoes':        [0.16, 0.11, 0.08, 1.0],
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

    # -------------------------------------------------------------------- parts
    def create_head_assembly(self):
        """Head + short dark hair + the signature dark-navy French beret."""
        meshes = []

        # Slightly rounded human head, medium skin.
        head = icosphere(subdivisions=3, radius=0.115)
        head.apply_scale([1.0, 1.02, 1.08])
        head.visual.vertex_colors = self.colors['skin']
        meshes.append(head)

        # Short dark hair: a thin cap hugging the back/sides of the skull, kept
        # low at the front so the face stays clear (the beret covers the crown).
        hair_cap = icosphere(subdivisions=2, radius=0.118)
        hair_cap.apply_scale([1.02, 1.0, 0.62])
        hair_cap.apply_translation([0, -0.012, 0.045])
        hair_cap.visual.vertex_colors = self.colors['hair']
        meshes.append(hair_cap)

        # A little fringe / sideburn hint at the lower sides so it reads as hair,
        # not a swim cap.
        for (tx, ty, tz) in [(-0.085, 0.02, 0.0), (0.085, 0.02, 0.0),
                              (-0.05, 0.06, 0.02), (0.05, 0.06, 0.02)]:
            tuft = icosphere(subdivisions=1, radius=0.030)
            tuft.apply_scale([0.9, 0.8, 1.2])
            tuft.apply_translation([tx, ty, tz])
            tuft.visual.vertex_colors = self.colors['hair']
            meshes.append(tuft)

        # ---- French beret (signature) ---------------------------------------
        # A soft, rounded floppy disc clamped low onto the crown — NOT a peaked
        # military cap. Built Z-up: a wide flat-bottomed dome with a downturned
        # overhanging brim all round, a tight headband gripping the skull, and the
        # little nub at the very top centre. Tilted gently to one side.
        beret_meshes = []

        # Main beret body: a broad, very low dome (squashed sphere), wider than the
        # head so it overhangs the brow all round like a real beret.
        dome = icosphere(subdivisions=3, radius=0.162)
        dome.apply_scale([1.0, 1.0, 0.44])      # wide & quite flat
        dome.visual.vertex_colors = self.colors['beret_navy']
        beret_meshes.append(dome)

        # A soft drooping brim ring at the rim level so the edge folds down toward
        # the head instead of looking like a stiff cap visor.
        brim = trimesh.creation.annulus(r_min=0.105, r_max=0.165, height=0.020, sections=32)
        brim.apply_translation([0, 0, -0.028])
        brim.visual.vertex_colors = self.colors['beret_navy']
        beret_meshes.append(brim)

        # Tight headband gripping the skull, hidden just under the brim.
        rim = cylinder(radius=0.112, height=0.045, sections=28)
        rim.apply_translation([0, 0, -0.050])
        rim.visual.vertex_colors = self.colors['beret_navy']
        beret_meshes.append(rim)

        # The small nub / stalk at the top centre of the beret.
        nub = icosphere(subdivisions=2, radius=0.017)
        nub.apply_translation([0, 0, 0.066])
        nub.visual.vertex_colors = self.colors['beret_navy']
        beret_meshes.append(nub)

        beret = trimesh.util.concatenate(beret_meshes)
        # Tilt gently to one side (a classic jaunty beret) and seat it LOW on the
        # crown so the headband meets the hairline with no floating gap.
        beret.apply_transform(rotation_matrix(np.radians(7), [1, 0, 0]))
        beret.apply_transform(rotation_matrix(np.radians(-11), [0, 1, 0]))
        beret.apply_translation([0.015, 0.004, 0.092])
        meshes.append(beret)

        return trimesh.util.concatenate(meshes)

    def create_torso_assembly(self):
        """Average torso (mustard polo) + neck + small collar + button placket +
        belt + dark trouser waistband."""
        meshes = []

        # Neck (skin) poking out of the collar.
        neck = cylinder(radius=0.052, height=0.085, sections=16)
        neck.apply_translation([0, 0, 0.155])
        neck.visual.vertex_colors = self.colors['skin']
        meshes.append(neck)

        # Torso — average build: moderate width in X, modest depth in Y, tall in Z.
        # Slimmer than Windman's stout barrel so Teibi reads as a normal man.
        torso = icosphere(subdivisions=3, radius=0.145)
        torso.apply_scale([0.95, 0.66, 1.62])
        torso.visual.vertex_colors = self.colors['shirt_mustard']
        meshes.append(torso)

        # Natural shoulders (not the broad slab Windman has).
        shoulders = icosphere(subdivisions=2, radius=0.145)
        shoulders.apply_scale([1.22, 0.62, 0.5])
        shoulders.apply_translation([0, 0, 0.145])
        shoulders.visual.vertex_colors = self.colors['shirt_mustard']
        meshes.append(shoulders)

        # ---- Polo collar: a small fold-over band around the neck base ----------
        # A short slightly-tilted ring sitting proud at the top-front of the torso.
        collar = cylinder(radius=0.066, height=0.040, sections=20)
        collar.apply_transform(rotation_matrix(np.radians(18), [1, 0, 0]))
        collar.apply_translation([0, 0.005, 0.150])
        collar.visual.vertex_colors = self.colors['shirt_collar']
        meshes.append(collar)

        # Two little collar points flaring open at the front.
        for sgn in (-1, 1):
            point = box(extents=[0.050, 0.020, 0.055])
            point.apply_transform(rotation_matrix(np.radians(sgn * 22), [0, 0, 1]))
            point.apply_transform(rotation_matrix(np.radians(28), [1, 0, 0]))
            point.apply_translation([sgn * 0.040, 0.085, 0.130])
            point.visual.vertex_colors = self.colors['shirt_collar']
            meshes.append(point)

        # ---- Button placket: a short vertical strip down the chest, proud of
        # the shirt so the convex torso doesn't shred it. ----------------------
        placket = box(extents=[0.034, 0.020, 0.16])
        placket.apply_translation([0, 0.118, 0.075])
        placket.visual.vertex_colors = self.colors['placket']
        meshes.append(placket)

        for bz in (0.135, 0.090, 0.045):
            button = cylinder(radius=0.009, height=0.012, sections=10)
            button.apply_transform(rotation_matrix(np.radians(90), [1, 0, 0]))
            button.apply_translation([0, 0.131, bz])
            button.visual.vertex_colors = self.colors['button']
            meshes.append(button)

        # ---- Belt at the waist (over the trousers waistband) -------------------
        belt = box(extents=[0.275, 0.165, 0.05])
        belt.apply_translation([0, 0, -0.225])
        belt.visual.vertex_colors = self.colors['belt']
        meshes.append(belt)

        buckle = box(extents=[0.05, 0.02, 0.045])
        buckle.apply_translation([0, 0.090, -0.225])
        buckle.visual.vertex_colors = self.colors['belt_buckle']
        meshes.append(buckle)

        # Dark trouser hips/pelvis below the belt — extended down far enough to
        # reach the thigh tops (hips sit at world 0.77; this part's node is at
        # 1.17) so there is no bare gap between the shirt/belt and the legs.
        pelvis = box(extents=[0.265, 0.165, 0.20])
        pelvis.apply_translation([0, 0, -0.345])
        pelvis.visual.vertex_colors = self.colors['trousers']
        meshes.append(pelvis)

        # Two rounded thigh-tops blending the pelvis into each leg so the seam is
        # filled even when the legs swing during the walk animation.
        for sgn in (-1, 1):
            hip = icosphere(subdivisions=2, radius=0.088)
            hip.apply_scale([0.95, 1.0, 1.15])
            hip.apply_translation([sgn * 0.09, 0, -0.40])
            hip.visual.vertex_colors = self.colors['trousers']
            meshes.append(hip)

        return trimesh.util.concatenate(meshes)

    def create_upper_arm(self):
        """Upper arm fully covered by the mustard LONG SLEEVE.

        The pivot (shoulder) is at the local origin so the rig rotates correctly,
        but the geometry HANGS DOWN toward -Z (shoulder at 0, elbow near -0.27).
        Because the shirt has long sleeves, the entire upper arm is shirt colour.
        """
        meshes = []

        arm = self.create_capsule(height=0.30, radius=0.052, segments=16)
        arm.apply_translation([0, 0, -0.15])
        arm.visual.vertex_colors = self.colors['shirt_mustard']
        meshes.append(arm)

        # Rounded shoulder cap (also sleeve colour) right at the joint.
        shoulder = icosphere(subdivisions=2, radius=0.064)
        shoulder.apply_scale([1.0, 1.0, 0.9])
        shoulder.apply_translation([0, 0, -0.005])
        shoulder.visual.vertex_colors = self.colors['shirt_mustard']
        meshes.append(shoulder)

        return trimesh.util.concatenate(meshes)

    def create_lower_arm(self):
        """Forearm covered by the mustard sleeve, ending in a skin HAND at the
        wrist (sleeves stop at the wrist). Pivot (elbow) at origin, runs -Z."""
        meshes = []

        # Sleeved forearm.
        forearm = self.create_capsule(height=0.255, radius=0.046, segments=16)
        forearm.visual.vertex_colors = self.colors['shirt_mustard']
        meshes.append(forearm)

        # A thin cuff ring at the wrist to read as the sleeve ending.
        cuff = cylinder(radius=0.050, height=0.020, sections=16)
        cuff.apply_translation([0, 0, -0.135])
        cuff.visual.vertex_colors = self.colors['shirt_collar']
        meshes.append(cuff)

        # Skin hand emerging past the cuff.
        hand = icosphere(subdivisions=2, radius=0.048)
        hand.apply_scale([0.82, 1.0, 1.2])
        hand.apply_translation([0, 0, -0.175])
        hand.visual.vertex_colors = self.colors['skin']
        meshes.append(hand)

        return trimesh.util.concatenate(meshes)

    def create_upper_leg(self):
        """Dark trouser thigh (full-length trousers). Pivot (hip) at origin;
        geometry hangs to -Z (hip at 0, knee near -0.37)."""
        leg = self.create_capsule(height=0.42, radius=0.078, segments=16)
        leg.apply_translation([0, 0, -0.19])
        leg.visual.vertex_colors = self.colors['trousers']
        return leg

    def create_lower_leg(self):
        """Dark trouser calf (trousers run all the way down) ending in a low
        dark shoe. Pivot (knee) at origin."""
        meshes = []

        # Trouser-covered calf — straight, only a slight taper.
        calf = self.create_capsule(height=0.40, radius=0.062, segments=16)
        calf.visual.vertex_colors = self.colors['trousers']
        meshes.append(calf)

        # Trouser hem just above the shoe.
        hem = cylinder(radius=0.066, height=0.030, sections=16)
        hem.apply_translation([0, 0.005, -0.275])
        hem.visual.vertex_colors = self.colors['trousers']
        meshes.append(hem)

        # ---- Low dress shoe (not a tall boot) ---------------------------------
        # Forward-biased over the foot, flat-soled, plain dark.
        shoe = box(extents=[0.085, 0.16, 0.075])
        shoe.apply_translation([0, 0.045, -0.32])
        shoe.visual.vertex_colors = self.colors['shoes']
        meshes.append(shoe)

        # Rounded toe cap.
        toe = icosphere(subdivisions=2, radius=0.055)
        toe.apply_scale([0.78, 1.15, 0.6])
        toe.apply_translation([0, 0.125, -0.335])
        toe.visual.vertex_colors = self.colors['shoes']
        meshes.append(toe)

        # Thin flat sole at the very bottom.
        sole = box(extents=[0.092, 0.235, 0.028])
        sole.apply_translation([0, 0.05, -0.352])
        sole.visual.vertex_colors = self.colors['shoes']
        meshes.append(sole)

        return trimesh.util.concatenate(meshes)

    # ------------------------------------------------------------------- driver
    def generate_and_save(self, output_dir):
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        print("Generating Teibi separate mesh parts...")

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
        }

        for name, mesh in parts.items():
            filename = output_dir / f"teibi_{name}.glb"
            print(f"  Saving {name}... ({len(mesh.vertices)} vertices)")
            export_faceted(mesh, str(filename))

        print(f"\n  All parts saved to {output_dir}")
        print(f"  Total parts: {len(parts)}")


def main():
    # Output next to this repo regardless of where the script is run from.
    repo_root = Path(__file__).resolve().parent.parent
    output_dir = repo_root / "assets" / "models" / "characters" / "teibi_parts"

    generator = TeibiSeparateMeshGenerator()
    generator.generate_and_save(output_dir)

    print("\n  Teibi separate mesh parts generated successfully!")
    print("  Assembled + animated by scenes/characters/teibi.tscn")


if __name__ == "__main__":
    main()
