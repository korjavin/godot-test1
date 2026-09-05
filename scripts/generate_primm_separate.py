#!/usr/bin/env python3
"""
Generate the Primm 3D model with SEPARATE body parts for individual animation.

Requires: trimesh, numpy, shapely, scipy  (shapely+scipy power the extruded cyan
"circuit / leaf-vein" pattern on the chest). Install with:
    pip install trimesh numpy shapely scipy

Each limb is exported as its own GLB file. `scenes/characters/primm.tscn`
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
  Keep those pivots and spans intact; everything else (girth, colour, the visor,
  hair, coat, cyan pattern, coat tails) is cosmetic and free to change.

Design target (Crime Kickers canon + reference art, 2026-06):
  * slim, lean, athletic young man (~1.8 m);
  * short swept DARK BROWN hair;
  * sleek SILVER/GREY TECH VISOR band across the eyes (pale blue lens) — NOT
    ordinary round glasses;
  * long open PURPLE/VIOLET trench coat with a high collar, worn open so the
    chest shows; coat tails hang past the hips toward knee level;
  * black inner shirt with a glowing CYAN/TEAL branching circuit / leaf-vein
    pattern down the chest;
  * belt at the waist;
  * purple coat sleeves with light blue-grey TURNED-BACK cuffs at the wrists;
  * black tech gloves on the hands;
  * dark navy / near-black jeans;
  * black boots with a white/silver band near the top.
"""

import numpy as np
import trimesh
from trimesh.creation import cylinder, box, icosphere, extrude_polygon
from trimesh.transformations import rotation_matrix
from shapely.geometry import LineString
from pathlib import Path

# THE ONE EXPORT SEAM for every model in this game (bead godot-test1-y1o.21,
# owner ruling 2026-09-05 "facet ALL"): it unmerges the mesh and writes flat
# per-face normals. It lives in predator_parts.py because the predators got it
# first — read its docstring before touching anything about normals here.
import sys  # noqa: E402
sys.path.insert(0, str(Path(__file__).resolve().parent))
from predator_parts import export_faceted  # noqa: E402


class PrimmSeparateMeshGenerator:
    def __init__(self):
        # Palette tuned to the reference art: violet trench coat, black shirt with
        # cyan circuit lines, light blue-grey cuffs/visor frame, dark-navy jeans.
        self.colors = {
            'skin':        [0.91, 0.73, 0.62, 1.0],
            'hair':        [0.26, 0.16, 0.10, 1.0],   # dark brown
            'coat_purple': [0.30, 0.15, 0.44, 1.0],   # deep violet trench coat
            'coat_collar': [0.25, 0.12, 0.37, 1.0],   # slightly darker collar
            'silver_trim': [0.74, 0.76, 0.80, 1.0],   # seam / coat-edge trim
            'cuff_grey':   [0.62, 0.68, 0.74, 1.0],   # light blue-grey cuffs
            'shirt_black': [0.07, 0.07, 0.10, 1.0],   # black inner shirt
            'cyan_glow':   [0.20, 0.85, 0.85, 1.0],   # glowing cyan circuit lines
            'glove_black': [0.06, 0.06, 0.07, 1.0],   # black tech gloves
            'belt_black':  [0.05, 0.05, 0.06, 1.0],
            'belt_buckle': [0.70, 0.72, 0.76, 1.0],
            'jeans_navy':  [0.10, 0.11, 0.17, 1.0],   # dark navy / near-black
            'boots_black': [0.07, 0.07, 0.08, 1.0],
            'boot_band':   [0.86, 0.88, 0.90, 1.0],   # white/silver band near top
            'visor_frame': [0.70, 0.72, 0.76, 1.0],   # silver visor frame
            'visor_lens':  [0.66, 0.80, 0.90, 1.0],   # pale blue lens
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

    def _make_cyan_pattern(self, y_front, color):
        """A glowing cyan branching circuit / leaf-vein pattern down the chest.

        Built as several buffered poly-lines (a central stem with angled branches,
        like a leaf vein / circuit trace) extruded to a shallow slab, re-oriented
        from the extrusion's XY plane into the body's X (horizontal) / Z (vertical)
        chest plane with the slab depth pointing forward (+Y). Pushed fully PROUD
        of the shirt so the faceted body never shreds it.
        """
        # Centre-line strokes in the chest plane: (x, vertical). A vertical stem
        # from the collar down to the belt with symmetric angled branches reads as
        # a leaf-vein / circuit trace.
        strokes = [
            # central stem (top of chest -> waist)
            [(0.0, 0.20), (0.0, -0.20)],
            # upper branches
            [(0.0, 0.12), (-0.085, 0.18)],
            [(0.0, 0.12), (0.085, 0.18)],
            # mid branches
            [(0.0, 0.02), (-0.075, 0.07)],
            [(0.0, 0.02), (0.075, 0.07)],
            # lower branches
            [(0.0, -0.08), (-0.065, -0.04)],
            [(0.0, -0.08), (0.065, -0.04)],
        ]
        emblems = []
        rot = np.array([[-1, 0, 0, 0],
                        [0, 0, 1, 0],
                        [0, 1, 0, 0],
                        [0, 0, 0, 1]], dtype=float)
        for pts in strokes:
            poly = LineString(pts).buffer(0.010, cap_style=1, join_style=1)
            seg = extrude_polygon(poly, height=0.016)
            seg.apply_transform(rot)
            seg.apply_translation([0, y_front + 0.012, 0.04])
            seg.visual.vertex_colors = color
            emblems.append(seg)
        return trimesh.util.concatenate(emblems)

    # -------------------------------------------------------------------- parts
    def create_head_assembly(self):
        """Head + short swept dark-brown hair + sleek silver tech visor band."""
        meshes = []

        # Slightly elongated face (taller in Z, a touch narrower in X).
        head = icosphere(subdivisions=3, radius=0.115)
        head.apply_scale([0.96, 1.0, 1.12])
        head.visual.vertex_colors = self.colors['skin']
        meshes.append(head)

        # Short swept hair: a flattened cap that sweeps back, plus a small front
        # fringe tuft so it reads as "short swept brown hair", not a helmet.
        hair_cap = icosphere(subdivisions=2, radius=0.122)
        hair_cap.apply_scale([1.0, 1.02, 0.62])
        hair_cap.apply_translation([0, -0.012, 0.082])
        hair_cap.visual.vertex_colors = self.colors['hair']
        meshes.append(hair_cap)

        # Side / back hair sweep (covers above the ears and the nape lightly).
        for (tx, ty, tz, sx, sy, sz) in [
            (0.0,  -0.060, 0.060, 1.06, 0.85, 0.70),   # back sweep
            (-0.085, 0.02, 0.060, 0.55, 0.85, 0.70),   # left side
            (0.085,  0.02, 0.060, 0.55, 0.85, 0.70),   # right side
        ]:
            sweep = icosphere(subdivisions=2, radius=0.072)
            sweep.apply_scale([sx, sy, sz])
            sweep.apply_translation([tx, ty, tz])
            sweep.visual.vertex_colors = self.colors['hair']
            meshes.append(sweep)

        # Front fringe tufts swept across the forehead (small, slightly forward).
        for (tx, ty, tz, s) in [
            (-0.04, 0.075, 0.085, 1.0), (0.02, 0.085, 0.080, 0.9),
            (0.06, 0.075, 0.070, 0.8),
        ]:
            tuft = icosphere(subdivisions=1, radius=0.030 * s)
            tuft.apply_scale([1.2, 1.0, 0.9])
            tuft.apply_translation([tx, ty, tz])
            tuft.visual.vertex_colors = self.colors['hair']
            meshes.append(tuft)

        # ---- Tech visor band across the eyes (the defining feature) ----
        # A sleek silver frame band wrapping the upper face at eye level, with a
        # slightly proud pale-blue lens on the front. Sits ON the face (front +Y),
        # not a full wrap, so it reads as a sci-fi visor rather than a blindfold.
        frame = box(extents=[0.215, 0.090, 0.052])
        frame.apply_translation([0, 0.062, 0.022])
        frame.visual.vertex_colors = self.colors['visor_frame']
        meshes.append(frame)

        # Pale blue lens slab, proud of the frame on +Y (made prominent so the
        # sci-fi visor is unmistakable at a glance).
        lens = box(extents=[0.198, 0.044, 0.048])
        lens.apply_translation([0, 0.106, 0.022])
        lens.visual.vertex_colors = self.colors['visor_lens']
        meshes.append(lens)

        # Small temple arms running back along the sides toward the ears.
        for sx in (-1.0, 1.0):
            temple = box(extents=[0.022, 0.110, 0.018])
            temple.apply_translation([sx * 0.100, 0.015, 0.030])
            temple.visual.vertex_colors = self.colors['visor_frame']
            meshes.append(temple)

        return trimesh.util.concatenate(meshes)

    def create_torso_assembly(self):
        """Slim torso: open purple coat with high collar over a black cyan-circuit
        shirt + belt at the waist + short coat tails hanging past the hips."""
        meshes = []

        # Slim neck.
        neck = cylinder(radius=0.050, height=0.09, sections=16)
        neck.apply_translation([0, 0, 0.18])
        neck.visual.vertex_colors = self.colors['skin']
        meshes.append(neck)

        # Black inner shirt: a slim chest column sitting slightly BACK (-Y) so the
        # purple coat panels can flank it and the front gap reads as "open coat".
        shirt = icosphere(subdivisions=3, radius=0.125)
        shirt.apply_scale([0.78, 0.62, 1.5])
        shirt.apply_translation([0, -0.018, 0.0])
        shirt.visual.vertex_colors = self.colors['shirt_black']
        meshes.append(shirt)

        # Glowing cyan branching pattern down the centre of the black shirt.
        meshes.append(self._make_cyan_pattern(
            y_front=0.060, color=self.colors['cyan_glow']))

        # ---- Open purple coat ----
        # Two front coat panels (lapels) flanking the central shirt gap, plus the
        # bulk of the coat wrapping the back/sides. Built as flank slabs so a clear
        # vertical strip of black shirt + cyan stays visible down the front.
        for sx in (-1.0, 1.0):
            panel = box(extents=[0.115, 0.15, 0.42])
            # rotate slightly outward at the top to read as an open lapel
            panel.apply_transform(rotation_matrix(np.radians(-8 * sx), [0, 0, 1]))
            panel.apply_translation([sx * 0.118, 0.038, 0.02])
            panel.visual.vertex_colors = self.colors['coat_purple']
            meshes.append(panel)

            # Silver seam trim down the front edge of each lapel.
            trim = box(extents=[0.018, 0.020, 0.42])
            trim.apply_transform(rotation_matrix(np.radians(-8 * sx), [0, 0, 1]))
            trim.apply_translation([sx * 0.062, 0.110, 0.02])
            trim.visual.vertex_colors = self.colors['silver_trim']
            meshes.append(trim)

        # Coat back / sides: a broad purple shell behind the shirt.
        back = icosphere(subdivisions=3, radius=0.14)
        back.apply_scale([1.10, 0.62, 1.55])
        back.apply_translation([0, -0.055, 0.0])
        back.visual.vertex_colors = self.colors['coat_purple']
        meshes.append(back)

        # ---- High coat collar ----
        # A short upturned ring at the base of the neck, open at the front.
        for ang in range(120, 421, 20):  # leave a gap at the front (~ +Y)
            a = np.radians(ang)
            seg = box(extents=[0.040, 0.040, 0.10])
            seg.apply_transform(rotation_matrix(a, [0, 0, 1]))
            seg.apply_translation([np.cos(a) * 0.110, np.sin(a) * 0.110, 0.165])
            seg.visual.vertex_colors = self.colors['coat_collar']
            meshes.append(seg)

        # ---- Belt at the waist ----
        belt = cylinder(radius=0.135, height=0.05, sections=24)
        belt.apply_scale([1.0, 0.78, 1.0])
        belt.apply_translation([0, 0, -0.255])
        belt.visual.vertex_colors = self.colors['belt_black']
        meshes.append(belt)

        buckle = box(extents=[0.06, 0.05, 0.045])
        buckle.apply_translation([0, 0.105, -0.255])
        buckle.visual.vertex_colors = self.colors['belt_buckle']
        meshes.append(buckle)

        # Pelvis block (jeans) at the bottom of the torso part.
        pelvis = box(extents=[0.24, 0.17, 0.14])
        pelvis.apply_translation([0, 0, -0.33])
        pelvis.visual.vertex_colors = self.colors['jeans_navy']
        meshes.append(pelvis)

        # ---- Coat tails hanging past the hips ----
        # Front-flanking and back tails: thin purple panels hanging down toward
        # knee level. Kept narrow and to the sides/back so they don't fight the
        # leg animation. Each tapers to a point (pointed hem like the reference).
        tail_specs = [
            # (x, y, length, taper) — back centre + back-left/right + side fronts
            (0.0,  -0.105, 0.62, 0.55),   # long back centre tail
            (-0.140, -0.060, 0.50, 0.50),  # back-left
            (0.140, -0.060, 0.50, 0.50),   # back-right
            (-0.150, 0.060, 0.42, 0.50),   # front-left flap
            (0.150, 0.060, 0.42, 0.50),    # front-right flap
        ]
        for (tx, ty, length, taper) in tail_specs:
            tail = box(extents=[0.105, 0.030, length])
            # taper the bottom toward a point by squeezing lower verts in X
            v = tail.vertices.copy()
            zmin = v[:, 2].min()
            span = v[:, 2].max() - zmin
            for i in range(len(v)):
                t = (v[i, 2] - zmin) / span  # 0 at bottom, 1 at top
                scale_x = taper + (1.0 - taper) * t
                v[i, 0] *= scale_x
            tail.vertices = v
            tail.apply_translation([tx, ty, -0.33 - length / 2 + 0.03])
            tail.visual.vertex_colors = self.colors['coat_purple']
            meshes.append(tail)

        return trimesh.util.concatenate(meshes)

    def create_upper_arm(self):
        """Slim purple coat-sleeve upper arm. Pivot (shoulder) at origin, runs -Z."""
        meshes = []

        arm = self.create_capsule(height=0.30, radius=0.050, segments=16)
        arm.apply_translation([0, 0, -0.15])
        arm.visual.vertex_colors = self.colors['coat_purple']
        meshes.append(arm)

        # Rounded shoulder cap right at the joint (coat shoulder).
        shoulder = icosphere(subdivisions=2, radius=0.064)
        shoulder.apply_scale([1.0, 1.0, 0.9])
        shoulder.apply_translation([0, 0, -0.01])
        shoulder.visual.vertex_colors = self.colors['coat_purple']
        meshes.append(shoulder)

        return trimesh.util.concatenate(meshes)

    def create_lower_arm(self):
        """Purple coat forearm with a light blue-grey turned-back cuff, ending in a
        black tech glove. Pivot (elbow) at origin, runs -Z."""
        meshes = []

        # Purple forearm (upper part of the coat sleeve).
        forearm = self.create_capsule(height=0.20, radius=0.046, segments=16)
        forearm.apply_translation([0, 0, -0.02])
        forearm.visual.vertex_colors = self.colors['coat_purple']
        meshes.append(forearm)

        # Light blue-grey turned-back cuff at the wrist (a flared ring).
        cuff = cylinder(radius=0.058, height=0.055, sections=18)
        cuff.apply_translation([0, 0, -0.155])
        cuff.visual.vertex_colors = self.colors['cuff_grey']
        meshes.append(cuff)

        # Black-gloved hand below the cuff.
        wrist = self.create_capsule(height=0.07, radius=0.040, segments=14)
        wrist.apply_translation([0, 0, -0.205])
        wrist.visual.vertex_colors = self.colors['glove_black']
        meshes.append(wrist)

        hand = icosphere(subdivisions=2, radius=0.050)
        hand.apply_scale([0.85, 1.0, 1.15])
        hand.apply_translation([0, 0, -0.255])
        hand.visual.vertex_colors = self.colors['glove_black']
        meshes.append(hand)

        return trimesh.util.concatenate(meshes)

    def create_upper_leg(self):
        """Dark-navy jeans thigh. Pivot (hip) at origin; geometry hangs to -Z."""
        leg = self.create_capsule(height=0.42, radius=0.072, segments=16)
        leg.apply_translation([0, 0, -0.19])
        leg.visual.vertex_colors = self.colors['jeans_navy']
        return leg

    def create_lower_leg(self):
        """Navy-jeans calf tucked into a black boot with a white/silver band near
        the top. Pivot (knee) at origin, runs -Z."""
        meshes = []

        # Jeans calf (upper portion).
        calf = self.create_capsule(height=0.22, radius=0.058, segments=16)
        calf.apply_translation([0, 0, -0.02])
        calf.visual.vertex_colors = self.colors['jeans_navy']
        meshes.append(calf)

        # Boot shaft (medium height, black) over the lower calf.
        shaft = self.create_capsule(height=0.20, radius=0.066, segments=16)
        shaft.apply_translation([0, 0, -0.235])
        shaft.visual.vertex_colors = self.colors['boots_black']
        meshes.append(shaft)

        # White/silver band near the top of the boot.
        band = cylinder(radius=0.071, height=0.035, sections=18)
        band.apply_translation([0, 0, -0.150])
        band.visual.vertex_colors = self.colors['boot_band']
        meshes.append(band)

        # Boot foot (forward-biased over the toes).
        boot = box(extents=[0.095, 0.18, 0.11])
        boot.apply_translation([0, 0.040, -0.345])
        boot.visual.vertex_colors = self.colors['boots_black']
        meshes.append(boot)

        # Rounded toe cap.
        toe = icosphere(subdivisions=2, radius=0.058)
        toe.apply_scale([0.8, 1.1, 0.55])
        toe.apply_translation([0, 0.125, -0.375])
        toe.visual.vertex_colors = self.colors['boots_black']
        meshes.append(toe)

        # Flat sole slab.
        sole = box(extents=[0.105, 0.27, 0.035])
        sole.apply_translation([0, 0.050, -0.398])
        sole.visual.vertex_colors = self.colors['boots_black']
        meshes.append(sole)

        return trimesh.util.concatenate(meshes)

    # ------------------------------------------------------------------- driver
    def generate_and_save(self, output_dir):
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        print("Generating Primm separate mesh parts...")

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
            filename = output_dir / f"primm_{name}.glb"
            print(f"  Saving {name}... ({len(mesh.vertices)} vertices)")
            export_faceted(mesh, str(filename))

        print(f"\n  All parts saved to {output_dir}")
        print(f"  Total parts: {len(parts)}")


def main():
    # Output next to this repo regardless of where the script is run from.
    repo_root = Path(__file__).resolve().parent.parent
    output_dir = repo_root / "assets" / "models" / "characters" / "primm_parts"

    generator = PrimmSeparateMeshGenerator()
    generator.generate_and_save(output_dir)

    print("\n  Primm separate mesh parts generated successfully!")
    print("  Assembled + animated by scenes/characters/primm.tscn")


if __name__ == "__main__":
    main()
