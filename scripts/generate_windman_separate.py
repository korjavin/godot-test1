#!/usr/bin/env python3
"""
Generate Windman's FAN — and, since bead godot-test1-5u3.5, nothing else.

WHAT LEFT, AND WHY. This script used to emit ten body parts: a torso with an
extruded "W" on its chest, four arm segments, four leg segments, and this fan.
Bead 5u3.5 replaced the body with one skinned mesh on a 23-bone MakeHuman rig
(`scripts/build_hero.py`, the source of record; `assets/models/characters/
PROVENANCE.md` carries the row), and the authored head was folded into that same
mesh, so there is no part tree left to build. The chest "W" went with the torso:
it is VERTEX COLOUR now, painted by `build_hero.paint_chest_glyph` off the same
five-point centre-line and 27 mm buffer this file used to hand to shapely — which
is why this file no longer imports `shapely` or `extrude_polygon` at all, and why
`scripts/requirements.txt` can drop those two pins as soon as Primm's generator
(bead 5u3.6) stops being their last user.

THE FAN STAYS GENERATED BECAUSE IT IS A PROP, NOT A BODY. It hangs off `hand_r`
as a `BoneAttachment3D` in `scenes/characters/windman_updated.tscn` — rigid
geometry the skeleton carries, never skinned — so it owes nothing to MakeHuman
and everything to the toolkit every other generated model in this repo uses. It
therefore stays inside `build.yml`'s rebuild-and-diff gate, which is the reason
`windman` is still a name in that workflow's hero loop.

Requires the PINNED toolchain of `scripts/requirements.txt` — trimesh + numpy.
    pip install -r scripts/requirements.txt

COORDINATE CONVENTION (do not break it — the .tscn's offset depends on it):
  * trimesh local space is **Z-up**, **+Y = front of the character**, and
    `export_faceted` writes those axes through unchanged. The fan's handle runs
    along Z with the GRIP at Z ~ 0 (where the hand closes on it) and the pinwheel
    at -Z; the blades fan out in the X-Z plane, flat face along Y.
  * The `BoneAttachment3D` is what turns that into Godot's Y-up hand frame. Its
    basis is measured on `hand_r`'s rest pose, not guessed — see the .tscn.

Design target (2026-06 canon + reference art): a flat three-blade pinwheel fan
(green / blue / red) on a short brown handle, in the RIGHT hand.
"""

import numpy as np
import trimesh
from trimesh.creation import cylinder, icosphere
from trimesh.transformations import rotation_matrix
from pathlib import Path

# THE ONE EXPORT SEAM for every model in this game (bead godot-test1-y1o.21,
# owner ruling 2026-09-05 "facet ALL"): it unmerges the mesh and writes flat
# per-face normals. It lives in predator_parts.py because the predators got it
# first — read its docstring before touching anything about normals here.
import sys  # noqa: E402
sys.path.insert(0, str(Path(__file__).resolve().parent))
from predator_parts import export_faceted  # noqa: E402


class WindmanSeparateMeshGenerator:
    def __init__(self):
        # The fan's own palette. The body's colours left with the body — they live
        # in `build_hero.HEROES["windman"]["colours"]` now, ungraded, and the skin
        # grade `scripts/hero_skin.py` owns is applied there at paint time.
        self.colors = {
            'fan_handle':   [0.45, 0.30, 0.16, 1.0],
            'fan_hub':      [0.20, 0.20, 0.22, 1.0],
            'fan_green':    [0.20, 0.66, 0.28, 1.0],
            'fan_blue':     [0.16, 0.45, 0.85, 1.0],
            'fan_red':      [0.85, 0.20, 0.18, 1.0],
        }

    def create_fan(self):
        """Flat three-blade pinwheel fan on a short brown handle.

        Authored Z-up / +Y-front like the body parts that used to sit beside it:
        the handle runs along Z with the grip at the top (Z ~ 0, where the hand
        holds it) and the pinwheel at the bottom (-Z). The blades fan out in the
        X-Z plane (flat face along Y), so once the hand's rest basis is applied
        the handle hangs down and the pinwheel faces forward. Green up, blue
        lower-left, red lower-right.
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

        print("Generating Windman's fan...")
        mesh = self.create_fan()
        filename = output_dir / "windman_fan.glb"
        print(f"  Saving fan... ({len(mesh.vertices)} vertices)")
        export_faceted(mesh, str(filename))
        print(f"\n  Saved to {filename}")


def main():
    # Output next to this repo regardless of where the script is run from.
    repo_root = Path(__file__).resolve().parent.parent
    output_dir = repo_root / "assets" / "models" / "characters" / "windman_parts"

    generator = WindmanSeparateMeshGenerator()
    generator.generate_and_save(output_dir)

    print("\n  Windman's fan generated successfully!")
    print("  Hung on hand_r by scenes/characters/windman_updated.tscn")


if __name__ == "__main__":
    main()
