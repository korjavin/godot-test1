#!/usr/bin/env python3
"""
Generate Phoboman 3D model with SEPARATE body parts for individual animation.

Requires: trimesh, numpy  (no shapely/scipy needed — the dragon is built from
swept tube segments, not extruded polygons). Install with:
    pip install trimesh numpy

Each limb is exported as its own GLB file. `scenes/characters/phoboman.tscn`
assembles them under a `Body` node whose `LeftArm` / `RightArm` / `LeftLeg` /
`RightLeg` containers are rotated at run time by the procedural walk/idle/jump
animation in `scripts/player_controller.gd`.

COORDINATE CONVENTIONS (do not break these — the rig depends on them):
  * trimesh local space is **Z-up**, **+Y = front of the character**. The scene
    rotates each part by Transform3D(1,0,0, 0,0,1, 0,-1,0) so trimesh +Z -> Godot
    +Y (up) and trimesh +Y -> Godot -Z (forward).
  * Every limb part is authored with its **joint pivot at the local origin** and
    the limb extending toward **-Z** (downward / away from the joint). The scene
    parents the container at the joint and the animation rotates it about that
    origin.

WHY THIS CHARACTER BREAKS THE WINDMAN SKELETON:
  Phoboman is NON-HUMANOID. His whole body is one giant round dark-blue SPHERE
  (his belly IS the body — like a huge pho bowl). So unlike Windman's tall
  humanoid skeleton, the joint POSITIONS are re-derived in the .tscn:
    * Torso  = the big blue dragon-sphere, centred low on the character.
    * Head   = a brass/gold diving helmet (dome + ring + valve knob) with a
               glass porthole; behind the glass an orange pho/noodle face. It
               sits right on top of the sphere — essentially no neck.
    * Arms   = SHORT, THICK, BARE (skin) stubs poking straight out of the
               UPPER SIDES of the sphere; small hands, no sleeves.
    * Legs   = TINY short black boots at the very bottom of the sphere, close
               together (legs almost hidden under the belly).
  The node NAMES (Body/Head/Torso/LeftArm/RightArm/LeftLeg/RightLeg) and the
  pivot-at-origin / hang-toward-(-Z) convention are sacred; only the offsets in
  the scene change to wrap the sphere.

Design target (primary reference art /Users/iv/Downloads/phobo.png + canon):
  * massive round dark-royal-blue body sphere;
  * bold red Chinese DRAGON wrapping the front of the sphere (sinuous body +
    simple head + horns + tail) — stylised, must read red-on-blue as "dragon";
  * brass/gold diving HELMET head: domed metal, rivets, a top valve knob, and a
    round GLASS porthole on the front;
  * inside the porthole: an ORANGE pho/noodle mass forming a face — two eyes,
    broth, a bright-green herb nose, swirly noodle strands;
  * short, stubby, beefy BARE (skin) arms with small hands;
  * tiny short BLACK boots/feet at the bottom, close together.
"""

import numpy as np
import trimesh
from trimesh.creation import cylinder, box, icosphere, torus
from trimesh.transformations import rotation_matrix
from pathlib import Path

# THE ONE EXPORT SEAM for every model in this game (bead godot-test1-y1o.21,
# owner ruling 2026-09-05 "facet ALL"): it unmerges the mesh and writes flat
# per-face normals. It lives in predator_parts.py because the predators got it
# first — read its docstring before touching anything about normals here.
import sys  # noqa: E402
sys.path.insert(0, str(Path(__file__).resolve().parent))
from predator_parts import export_faceted  # noqa: E402


# Body sphere radius — the whole character is built around this.
BODY_R = 0.52


class PhobomanSeparateMeshGenerator:
    def __init__(self):
        # Palette tuned to the reference art.
        self.colors = {
            'body_blue':    [0.13, 0.18, 0.46, 1.0],   # deep royal/navy belly sphere
            'dragon_red':   [0.80, 0.13, 0.13, 1.0],   # bold Chinese-dragon red
            'dragon_gold':  [0.92, 0.74, 0.30, 1.0],   # tiny dragon accents (horns/whiskers)
            'helmet_gold':  [0.80, 0.62, 0.24, 1.0],   # brass/gold diving helmet
            'helmet_dark':  [0.55, 0.41, 0.15, 1.0],   # darker brass for the ring/rivets
            'glass':        [0.55, 0.75, 0.82, 1.0],   # porthole glass (light, glassy)
            'broth':        [0.95, 0.52, 0.18, 1.0],   # orange pho broth
            'broth_hi':     [0.99, 0.78, 0.30, 1.0],   # bright-yellow broth highlight
            'noodle':       [0.97, 0.85, 0.55, 1.0],   # pale noodle strands
            'eye_dark':     [0.20, 0.10, 0.05, 1.0],   # dark noodle-eye pupils
            'nose_green':   [0.30, 0.70, 0.22, 1.0],   # bright-green herb nose
            'skin':         [0.91, 0.71, 0.58, 1.0],   # bare muscular arm skin
            'boots_black':  [0.07, 0.07, 0.08, 1.0],   # flat black boots
        }

    # ------------------------------------------------------------------ helpers
    def create_capsule(self, height, radius, segments=16):
        """A capsule (cylinder + hemisphere caps) centred on the origin, axis = Z."""
        cyl_height = max(0.01, height - 2 * radius)
        cylinder_mesh = cylinder(radius=radius, height=cyl_height, sections=segments)
        top = icosphere(subdivisions=2, radius=radius)
        top.apply_translation([0, 0, cyl_height / 2])
        bottom = icosphere(subdivisions=2, radius=radius)
        bottom.apply_translation([0, 0, -cyl_height / 2])
        return trimesh.util.concatenate([cylinder_mesh, top, bottom])

    def _tube_segment(self, p0, p1, radius, color, sections=10):
        """A short capsule between two points (for the dragon body / tail)."""
        p0 = np.asarray(p0, float)
        p1 = np.asarray(p1, float)
        axis = p1 - p0
        length = float(np.linalg.norm(axis))
        if length < 1e-6:
            seg = icosphere(subdivisions=2, radius=radius)
            seg.apply_translation(p0)
            seg.visual.vertex_colors = color
            return seg
        seg = self.create_capsule(height=length + 2 * radius, radius=radius, segments=sections)
        # capsule is built along +Z centred at origin; rotate +Z onto `axis`.
        z = np.array([0, 0, 1.0])
        a = axis / length
        v = np.cross(z, a)
        s = float(np.linalg.norm(v))
        c = float(np.dot(z, a))
        if s < 1e-8:
            if c < 0:
                seg.apply_transform(rotation_matrix(np.pi, [1, 0, 0]))
        else:
            seg.apply_transform(rotation_matrix(np.arctan2(s, c), v / s))
        seg.apply_translation((p0 + p1) / 2.0)
        seg.visual.vertex_colors = color
        return seg

    def _project_to_sphere(self, x, z, proud=0.012):
        """Given a desired (x, z) on the front of the body sphere, return the
        full 3D point sitting just PROUD of the sphere surface on the +Y front
        so the dragon reads as painted/embossed art, not buried in the body."""
        r = BODY_R + proud
        rem = r * r - x * x - z * z
        y = np.sqrt(max(rem, (0.30 * r) ** 2))  # keep it on the front hemisphere
        return np.array([x, y, z])

    # -------------------------------------------------------------------- parts
    def create_head_assembly(self):
        """Brass diving helmet (dome + ring + valve knob + rivets) with a glass
        porthole on the front, and an orange pho/noodle face behind the glass.

        Authored so the helmet bottom sits at local Z=0 (it will be placed right
        on top of the body sphere), rising up toward +Z. The face / porthole look
        out the +Y front."""
        meshes = []

        # --- helmet dome: a sphere flattened a touch, sitting above Z=0 ---------
        dome_r = 0.27
        dome = icosphere(subdivisions=3, radius=dome_r)
        dome.apply_scale([1.0, 1.02, 1.0])
        dome.apply_translation([0, 0, dome_r * 0.86])
        dome.visual.vertex_colors = self.colors['helmet_gold']
        meshes.append(dome)

        # --- bottom collar ring (where the helmet meets the body) --------------
        collar = torus(major_radius=0.235, minor_radius=0.045, major_sections=28, minor_sections=12)
        collar.apply_translation([0, 0, 0.03])
        collar.visual.vertex_colors = self.colors['helmet_dark']
        meshes.append(collar)

        # --- top valve / breather knob -----------------------------------------
        knob_base = cylinder(radius=0.045, height=0.05, sections=16)
        knob_base.apply_translation([0, 0, dome_r * 1.72 + 0.02])
        knob_base.visual.vertex_colors = self.colors['helmet_dark']
        meshes.append(knob_base)
        knob_top = icosphere(subdivisions=2, radius=0.035)
        knob_top.apply_translation([0, 0, dome_r * 1.72 + 0.07])
        knob_top.visual.vertex_colors = self.colors['helmet_gold']
        meshes.append(knob_top)

        # --- porthole rim ring on the front (+Y) -------------------------------
        port_r = 0.165
        port_z = dome_r * 0.92
        rim = torus(major_radius=port_r, minor_radius=0.028, major_sections=28, minor_sections=10)
        rim.apply_transform(rotation_matrix(np.radians(90), [1, 0, 0]))  # face +Y
        rim.apply_translation([0, dome_r * 0.86, port_z])
        rim.visual.vertex_colors = self.colors['helmet_dark']
        meshes.append(rim)

        # --- rivets around the porthole rim ------------------------------------
        for i in range(10):
            ang = i * (2 * np.pi / 10)
            rx = np.cos(ang) * port_r
            rz = port_z + np.sin(ang) * port_r
            rivet = icosphere(subdivisions=1, radius=0.017)
            ry = np.sqrt(max(dome_r * dome_r - rx * rx, 0.0)) * 0.92 + 0.03
            rivet.apply_translation([rx, ry + 0.02, rz])
            rivet.visual.vertex_colors = self.colors['helmet_dark']
            meshes.append(rivet)

        # --- glass porthole disc (slightly recessed, light glassy blue) --------
        glass = cylinder(radius=port_r - 0.01, height=0.02, sections=28)
        glass.apply_transform(rotation_matrix(np.radians(90), [1, 0, 0]))  # face +Y
        glass.apply_translation([0, dome_r * 0.86 + 0.02, port_z])
        glass.visual.vertex_colors = self.colors['glass']
        meshes.append(glass)

        # --- the pho/noodle FACE behind the glass ------------------------------
        face_y = dome_r * 0.86 - 0.02   # just inside the glass
        # Orange broth disc filling the porthole.
        broth = cylinder(radius=port_r - 0.02, height=0.04, sections=28)
        broth.apply_transform(rotation_matrix(np.radians(90), [1, 0, 0]))
        broth.apply_translation([0, face_y, port_z])
        broth.visual.vertex_colors = self.colors['broth']
        meshes.append(broth)
        # Bright highlight pool along the TOP rim of the broth (kept high and thin
        # so it doesn't wash over the eyes in the middle of the porthole).
        broth_hi = icosphere(subdivisions=2, radius=0.05)
        broth_hi.apply_scale([1.6, 0.4, 0.45])
        broth_hi.apply_translation([0, face_y + 0.01, port_z + 0.10])
        broth_hi.visual.vertex_colors = self.colors['broth_hi']
        meshes.append(broth_hi)

        # Two noodle eyes (pale noodle ring + big dark pupil), set in the UPPER
        # half of the porthole and lifted PROUD of the broth so they read clearly.
        eye_y = face_y + 0.05
        eye_z = port_z + 0.045
        for ex in (-0.058, 0.058):
            eye_ring = torus(major_radius=0.040, minor_radius=0.014, major_sections=16, minor_sections=8)
            eye_ring.apply_transform(rotation_matrix(np.radians(90), [1, 0, 0]))
            eye_ring.apply_translation([ex, eye_y, eye_z])
            eye_ring.visual.vertex_colors = self.colors['noodle']
            meshes.append(eye_ring)
            pupil = icosphere(subdivisions=2, radius=0.028)
            pupil.apply_scale([1.0, 0.7, 1.0])
            pupil.apply_translation([ex, eye_y + 0.012, eye_z])
            pupil.visual.vertex_colors = self.colors['eye_dark']
            meshes.append(pupil)

        # Bright-green herb nose poking up out of the broth, centre between/below
        # the eyes.
        nose = icosphere(subdivisions=2, radius=0.028)
        nose.apply_scale([1.1, 0.7, 1.3])
        nose.apply_translation([0, face_y + 0.04, port_z - 0.01])
        nose.visual.vertex_colors = self.colors['nose_green']
        meshes.append(nose)
        # A couple of tiny green herb flecks scattered around.
        for (hx, hz) in [(-0.05, -0.04), (0.055, -0.05), (0.0, -0.085)]:
            herb = icosphere(subdivisions=1, radius=0.013)
            herb.apply_translation([hx, face_y + 0.03, port_z + hz])
            herb.visual.vertex_colors = self.colors['nose_green']
            meshes.append(herb)

        # Swirly noodle strands across the lower broth (the "slurped" tangle).
        for (sx, sz, sl, rot) in [(-0.07, -0.06, 0.10, 20), (0.05, -0.07, 0.09, -25),
                                   (-0.02, -0.095, 0.08, 10), (0.07, -0.04, 0.07, 35)]:
            strand = self.create_capsule(height=sl, radius=0.009, segments=8)
            strand.apply_transform(rotation_matrix(np.radians(rot), [0, 1, 0]))
            strand.apply_transform(rotation_matrix(np.radians(90), [1, 0, 0]))
            strand.apply_translation([sx, face_y + 0.03, port_z + sz])
            strand.visual.vertex_colors = self.colors['noodle']
            meshes.append(strand)

        return trimesh.util.concatenate(meshes)

    def create_torso_assembly(self):
        """The big dark-blue body sphere with the red Chinese dragon wrapping the
        front. The sphere is centred at the local origin; the scene places this
        Torso node at the body centre height. The dragon sits PROUD of the +Y
        front surface so it reads as bold red-on-blue art."""
        meshes = []

        # --- the body sphere ----------------------------------------------------
        body = icosphere(subdivisions=4, radius=BODY_R)
        # Very slightly squashed vertically so it reads as a round bowl/belly,
        # not a perfect ball; keep it close to spherical.
        body.apply_scale([1.0, 0.96, 0.94])
        body.visual.vertex_colors = self.colors['body_blue']
        meshes.append(body)

        # --- red Chinese dragon, swept across the front of the sphere ----------
        # A sinuous S-curve of (x, z) waypoints in the chest plane; each is
        # projected onto the front of the sphere. Body tapers from tail to head.
        # Matching the reference: the tail starts UPPER-LEFT, the body snakes
        # DOWN-and-RIGHT across the belly in an S, and the head ends LOWER-RIGHT.
        # Vertical extent dominates so it reads as a dragon coursing down the
        # front of the bowl rather than a flat smile.
        path_xz = [
            (-0.20, 0.26),    # tail tip (upper left)
            (-0.06, 0.20),
            (0.05, 0.09),
            (0.09, -0.03),
            (0.01, -0.13),
            (-0.08, -0.20),
            (0.02, -0.26),
            (0.15, -0.27),    # head end (lower, centre-right of the belly)
        ]
        pts = [self._project_to_sphere(x, z) for (x, z) in path_xz]
        radii = np.linspace(0.030, 0.064, len(pts))  # thin tail -> bold thick body
        for i in range(len(pts) - 1):
            seg = self._tube_segment(pts[i], pts[i + 1], float((radii[i] + radii[i + 1]) / 2),
                                     self.colors['dragon_red'], sections=10)
            meshes.append(seg)
        # Round joints so the body reads as one continuous serpent.
        for i, p in enumerate(pts):
            joint = icosphere(subdivisions=2, radius=float(radii[i]) * 1.05)
            joint.apply_translation(p)
            joint.visual.vertex_colors = self.colors['dragon_red']
            meshes.append(joint)

        # --- dragon head at the lower end (last waypoint) ----------------------
        head_anchor = pts[-1]
        head = icosphere(subdivisions=2, radius=0.085)
        head.apply_scale([1.25, 0.9, 1.0])
        head.apply_translation(head_anchor + np.array([0.04, 0.01, -0.02]))
        head.visual.vertex_colors = self.colors['dragon_red']
        meshes.append(head)
        # Snout pointing right.
        snout = icosphere(subdivisions=2, radius=0.05)
        snout.apply_scale([1.4, 0.9, 0.85])
        snout.apply_translation(head_anchor + np.array([0.11, 0.0, -0.04]))
        snout.visual.vertex_colors = self.colors['dragon_red']
        meshes.append(snout)
        # Two gold horns swept back/up from the head.
        for hx in (-0.025, 0.025):
            horn = self.create_capsule(height=0.06, radius=0.011, segments=8)
            horn.apply_transform(rotation_matrix(np.radians(-30), [1, 0, 0]))
            horn.apply_translation(head_anchor + np.array([hx, 0.02, 0.06]))
            horn.visual.vertex_colors = self.colors['dragon_gold']
            meshes.append(horn)
        # Two small gold eyes on the head.
        for hx in (-0.015, 0.035):
            deye = icosphere(subdivisions=1, radius=0.012)
            deye.apply_translation(head_anchor + np.array([hx + 0.03, 0.04, 0.0]))
            deye.visual.vertex_colors = self.colors['dragon_gold']
            meshes.append(deye)
        # A couple of gold whisker/flame flicks trailing off the snout.
        for (wx, wz, wr) in [(0.20, -0.24, 40), (0.20, -0.31, -20)]:
            whisk = self.create_capsule(height=0.08, radius=0.008, segments=6)
            whisk.apply_transform(rotation_matrix(np.radians(wr), [0, 1, 0]))
            wp = self._project_to_sphere(wx, wz, proud=0.02)
            whisk.apply_translation([wx + 0.04, wp[1], wz])
            whisk.visual.vertex_colors = self.colors['dragon_gold']
            meshes.append(whisk)

        # --- a few red dragon "claw/leg" tufts branching off the body ----------
        for (cx, cz) in [(0.06, 0.04), (0.03, -0.10), (-0.05, -0.18)]:
            base = self._project_to_sphere(cx, cz)
            tip = self._project_to_sphere(cx + 0.05, cz - 0.05, proud=0.0)
            leg = self._tube_segment(base, tip, 0.016, self.colors['dragon_red'], sections=8)
            meshes.append(leg)

        return trimesh.util.concatenate(meshes)

    def create_upper_arm(self):
        """Short, thick, BARE (skin) upper arm. Pivot (shoulder) at origin;
        geometry hangs / extends toward -Z but stays short and beefy. The scene
        rotates the whole arm outward so it pokes out the side of the sphere."""
        meshes = []
        # Short and THICK (beefy) bicep.
        arm = self.create_capsule(height=0.18, radius=0.085, segments=16)
        arm.apply_translation([0, 0, -0.075])
        arm.visual.vertex_colors = self.colors['skin']
        meshes.append(arm)
        # Rounded muscular shoulder cap at the joint.
        shoulder = icosphere(subdivisions=2, radius=0.095)
        shoulder.apply_translation([0, 0, 0.0])
        shoulder.visual.vertex_colors = self.colors['skin']
        meshes.append(shoulder)
        return trimesh.util.concatenate(meshes)

    def create_lower_arm(self):
        """Short, thick forearm continuous with the bicep, ending in a small
        fist. Pivot (elbow) at origin. Radius matches the upper arm so the limb
        reads as ONE beefy stub, not two stacked bumps."""
        meshes = []
        forearm = self.create_capsule(height=0.13, radius=0.080, segments=16)
        forearm.apply_translation([0, 0, -0.025])
        forearm.visual.vertex_colors = self.colors['skin']
        meshes.append(forearm)
        hand = icosphere(subdivisions=2, radius=0.076)
        hand.apply_scale([0.95, 1.0, 0.95])
        hand.apply_translation([0, 0, -0.095])
        hand.visual.vertex_colors = self.colors['skin']
        meshes.append(hand)
        return trimesh.util.concatenate(meshes)

    def create_upper_leg(self):
        """Tiny short black leg stub (mostly hidden under the belly). Pivot (hip)
        at origin; runs -Z."""
        leg = self.create_capsule(height=0.10, radius=0.050, segments=12)
        leg.apply_translation([0, 0, -0.04])
        leg.visual.vertex_colors = self.colors['boots_black']
        return leg

    def create_lower_leg(self):
        """Short black boot. Pivot (knee) at origin; the boot sits at the bottom
        and reads as a little flat-soled shoe."""
        meshes = []
        ankle = self.create_capsule(height=0.07, radius=0.046, segments=12)
        ankle.visual.vertex_colors = self.colors['boots_black']
        meshes.append(ankle)
        # Boot body, forward-biased over the foot.
        boot = box(extents=[0.10, 0.15, 0.10])
        boot.apply_translation([0, 0.03, -0.085])
        boot.visual.vertex_colors = self.colors['boots_black']
        meshes.append(boot)
        # Rounded toe.
        toe = icosphere(subdivisions=2, radius=0.055)
        toe.apply_scale([0.85, 1.0, 0.6])
        toe.apply_translation([0, 0.10, -0.10])
        toe.visual.vertex_colors = self.colors['boots_black']
        meshes.append(toe)
        # Flat sole.
        sole = box(extents=[0.11, 0.22, 0.03])
        sole.apply_translation([0, 0.04, -0.12])
        sole.visual.vertex_colors = self.colors['boots_black']
        meshes.append(sole)
        return trimesh.util.concatenate(meshes)

    # ------------------------------------------------------------------- driver
    def generate_and_save(self, output_dir):
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        print("Generating Phoboman separate mesh parts...")

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
            filename = output_dir / f"phoboman_{name}.glb"
            print(f"  Saving {name}... ({len(mesh.vertices)} vertices)")
            export_faceted(mesh, str(filename))

        print(f"\n  All parts saved to {output_dir}")
        print(f"  Total parts: {len(parts)}")


def main():
    repo_root = Path(__file__).resolve().parent.parent
    output_dir = repo_root / "assets" / "models" / "characters" / "phoboman_parts"

    generator = PhobomanSeparateMeshGenerator()
    generator.generate_and_save(output_dir)

    print("\n  Phoboman separate mesh parts generated successfully!")
    print("  Assembled + animated by scenes/characters/phoboman.tscn")


if __name__ == "__main__":
    main()
