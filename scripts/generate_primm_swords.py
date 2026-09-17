#!/usr/bin/env python3
"""
Generate Primm's SWORDS — two katanas crossed in an X on his back, and nothing
else. The pattern is `generate_windman_fan.py`'s exactly: a rigid trimesh prop,
faceted vertex colours, out through `predator_parts.export_faceted()`, hung off
a chest bone by a `BoneAttachment3D` in `scenes/characters/primm.tscn`.

WHY GENERATED AND NOT AUTHORED. The swords are a prop, not a body — rigid
geometry the skeleton carries, never skinned — so they owe nothing to MakeHuman
and everything to the toolkit every other generated model in this repo uses.
They stay inside `build.yml`'s rebuild-and-diff gate for the same reason the
fan does. `build_hero.py`'s own comment says it outright: an accessory that is
not geometry is an ATTACHMENT and belongs in the .tscn, and these two are
geometry. (`hero_manifest.json` is the SKINNED mesh's gate and knows nothing
about this file; do not add it there.)

Requires the PINNED toolchain of `scripts/requirements.txt` — trimesh + numpy.
    pip install -r scripts/requirements.txt

COORDINATE CONVENTION (do not break it — the .tscn's offset depends on it):
  * trimesh local space is **Z-up**, **+Y = front of the character**, and
    `export_faceted` writes those axes through unchanged — the fan's convention,
    kept so the two props read the same way. Each katana is built along +Z with
    the TIP at -Z and the HILT at +Z, then tilted ±30° about Y so the pair
    crosses in the X-Z plane (flat against the back) at the origin.
  * The `BoneAttachment3D` is what turns that into Godot's Y-up chest frame.
    Its basis is measured on `spine_03`'s rest pose, not guessed — see the .tscn.

Design target (owner ruling 2026-09-17: "two samurai swords on his back"):
sheathed katanas — blade in a dark saya with the hilt showing — because the
back-carry canon IS sheathed (hilts up for the draw; drawn blades are not
worn), because the saya hides the blade/back intersection, and because it is
cheaper: no fuller, no edge, the slight curve reads on the saya silhouette.
Blade ~0.70 m inside a 0.72 m saya, tsuba disc, wrapped hilt ~0.25 m dark with
a diamond-ish two-tone, pommel cap. Crossed ±30° on the shoulder blades, hilts
up past the shoulders, tips splayed past the coat tails. The two saya tubes
interpenetrate where they cross — that is the lashed look, the fan's petals
sink into its hub the same way, and separating them would float one sword off
the back.
"""

import numpy as np
import trimesh
from pathlib import Path

import sys  # noqa: E402
sys.path.insert(0, str(Path(__file__).resolve().parent))
from predator_parts import export_faceted  # noqa: E402


# The design numbers, in metres. One katana, built along +Z, tip at -Z:
SAYA_LEN = 0.72        # covers a ~0.70 blade with a margin at the mouth
SAYA_R = 0.022         # saya tube radius
SAYA_STATIONS = 5      # the bead's 3-5 segments of slight curve, as stations
SAYA_SECTIONS = 12     # around
SAYA_BOW = 0.008       # outward bow at mid-saya — the curve on the silhouette
TSUBA_R = 0.035        # guard disc radius
TSUBA_T = 0.008        # ... thickness
TSUBA_SECTIONS = 16    # around
HILT_LEN = 0.25        # tsuka, tsuba face to pommel
HILT_R = 0.016         # grip radius
HILT_SECTIONS = 8      # octagonal — faceted, reads as wrap ridges
HILT_RINGS = 8         # along — with the sections, the diamond grid
POMMEL_LEN = 0.018     # kashira cap
POMMEL_R = 0.018
TILT_DEG = 30.0        # each sword off vertical, mirrored — the X
# Along-axis stations measured from the X crossing (s = 0), + toward the hilt:
S_TIP = -0.716         # tip (saya cap) — splays past the coat tails' x-range
S_MOUTH = 0.004        # saya mouth / tsuba face — the X crosses at the guards
S_POMMEL = S_MOUTH + HILT_LEN  # 0.254 — hilt end, up past the shoulders


def rgba8(c):
    """Palette (normalized float RGBA) -> 0-255 uint8 row, the ONE conversion.

    trimesh `vertex_colors` are uint8; handing them floats truncated the hilt's
    silver wrap to [0,0,0,1] (codex round 1, bead z629). Every assignment below
    goes through here.
    """
    return np.round(np.array(c, dtype=np.float64) * 255).astype(np.uint8)


class PrimmSwordsGenerator:
    def __init__(self):
        # Primm's own palette: the coat's silver for the wrap diamonds, dark
        # indigo-black for the saya, gunmetal for the furniture. Ungraded —
        # props carry no skin grade (the fan's comment says why).
        self.colors = {
            'saya':    [0.030, 0.035, 0.070, 1.0],
            'tsuba':   [0.160, 0.170, 0.190, 1.0],
            'hilt_a':  [0.020, 0.020, 0.025, 1.0],
            'hilt_b':  [0.550, 0.580, 0.620, 1.0],
            'pommel':  [0.160, 0.170, 0.190, 1.0],
        }

    def _tube(self, stations, color, cap_ends=True):
        """A tube through (z, x_off, radius, sections, ring_color) stations.

        One straight run of quads (two tris each) plus triangle-fan caps.
        Stations share no vertices with each other — every ring is its own
        loop, so `export_faceted`'s unmerge is a no-op here rather than a fix.
        """
        verts = []
        faces = []
        colors = []
        ring_start = []
        for z, x_off, radius, sections, ring_color in stations:
            ring_start.append(len(verts))
            for i in range(sections):
                a = 2.0 * np.pi * i / sections
                verts.append([x_off + radius * np.cos(a),
                              radius * np.sin(a), z])
                colors.append(ring_color)
        # WINDING IS OUTWARD (codex round 1, bead z629): rings advance in +z and
        # wind CCW seen from +z, so [a, b, c] faces away from the axis — Godot
        # front faces are clockwise seen from outside and `export_faceted`
        # preserves winding, so inward triangles render as the tube's inside.
        # trimesh signs it: the shipped pair must have POSITIVE volume (asserted
        # in `generate_and_save`), and it shipped NEGATIVE once.
        verts = np.array(verts, dtype=np.float64)
        for r in range(len(stations) - 1):
            s0, s1 = ring_start[r], ring_start[r + 1]
            n0 = stations[r][3]
            for i in range(n0):
                a, b = s0 + i, s0 + (i + 1) % n0
                c, d = s1 + i, s1 + (i + 1) % n0
                faces.append([a, b, c])
                faces.append([b, d, c])
        if cap_ends:
            for end, flip in ((0, False), (len(stations) - 1, True)):
                s = ring_start[end]
                n = stations[end][3]
                z, x_off = stations[end][0], stations[end][1]
                ci = len(verts)
                verts = np.vstack([verts, [[x_off, 0.0, z]]])
                colors.append(stations[end][4])
                for i in range(n):
                    a, b = s + i, s + (i + 1) % n
                    faces.append([ci, a, b] if flip else [ci, b, a])
        # Vertex colours ride 0-255 uint8 (codex round 1, bead z629): the
        # palette above is normalized floats, and assigning those into a uint8
        # array truncated the hilt's silver to [0,0,0,1] — black with an alpha
        # of 1/255. Convert ONCE here, after the cap colour is appended.
        colors = (np.round(np.array(colors, dtype=np.float64) * 255)
                  .astype(np.uint8))
        mesh = trimesh.Trimesh(vertices=verts, faces=np.array(faces),
                               process=False)
        mesh.visual = trimesh.visual.ColorVisuals(mesh, vertex_colors=colors)
        return mesh

    def _katana(self, side):
        """One sheathed katana along +Z: curved saya, tsuba, diamond hilt,
        pommel. `side` +1 bows and tilts toward +X, -1 mirrors it."""
        parts = []
        # Saya: a shallow outward bow over SAYA_STATIONS — the curve reads on
        # the silhouette, 8 mm at mid-tube.
        span = S_MOUTH - S_TIP
        saya_stations = []
        for k in range(SAYA_STATIONS):
            t = k / (SAYA_STATIONS - 1)
            z = S_TIP + t * span
            bow = SAYA_BOW * np.sin(np.pi * t) * side
            saya_stations.append((z, bow, SAYA_R, SAYA_SECTIONS,
                                  self.colors['saya']))
        saya = self._tube(saya_stations, self.colors['saya'])
        assert saya.volume > 0, f"saya wound inward: volume {saya.volume}"
        parts.append(saya)
        # Tsuba: a disc across the mouth, axis along the blade.
        tsuba = trimesh.creation.cylinder(radius=TSUBA_R, height=TSUBA_T,
                                          sections=TSUBA_SECTIONS)
        tsuba.apply_translation([0.0, 0.0, S_MOUTH])
        assert tsuba.volume > 0, f"tsuba wound inward: volume {tsuba.volume}"
        tsuba.visual.vertex_colors = rgba8(self.colors['tsuba'])
        parts.append(tsuba)
        # Hilt: octagonal, diamond two-tone by (ring + section) parity — the
        # wrap read, without a wrap to simulate.
        hilt_stations = []
        for k in range(HILT_RINGS):
            t = k / (HILT_RINGS - 1)
            z = S_MOUTH + t * HILT_LEN
            hilt_stations.append((z, 0.0, HILT_R, HILT_SECTIONS, None))
        hilt = self._tube(
            [(z, x, r, n, self.colors['hilt_a']) for z, x, r, n, _ in hilt_stations],
            self.colors['hilt_a'], cap_ends=False)
        hv = np.asarray(hilt.visual.vertex_colors).copy()
        for k in range(HILT_RINGS):
            for i in range(HILT_SECTIONS):
                if (k + i) % 2:
                    hv[k * HILT_SECTIONS + i] = rgba8(self.colors['hilt_b'])
        hilt.visual = trimesh.visual.ColorVisuals(hilt, vertex_colors=hv)
        parts.append(hilt)
        # Pommel cap. (The hilt gets no volume assertion: it is an OPEN tube by
        # design, and an open surface has no signed volume to check. Its sides
        # share `_tube()`'s winding with the saya, which IS asserted.)
        pommel = trimesh.creation.cylinder(radius=POMMEL_R, height=POMMEL_LEN,
                                           sections=10)
        pommel.apply_translation([0.0, 0.0, S_POMMEL + POMMEL_LEN / 2.0])
        assert pommel.volume > 0, f"pommel wound inward: volume {pommel.volume}"
        pommel.visual.vertex_colors = rgba8(self.colors['pommel'])
        parts.append(pommel)
        sword = trimesh.util.concatenate(parts)
        # Tilt into the X: +side toward +X at the hilt. rotation_matrix(a, +Y)
        # sends +Z -> (sin a, 0, cos a), so +30° tips this hilt top-right.
        sword.apply_transform(
            trimesh.transformations.rotation_matrix(np.radians(TILT_DEG * side),
                                                    [0, 1, 0]))
        return sword

    def create_swords(self):
        """The crossed pair, origin at the X crossing, hilts up."""
        return trimesh.util.concatenate([self._katana(+1), self._katana(-1)])

    # ------------------------------------------------------------------- driver
    def generate_and_save(self, output_dir):
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        print("Generating Primm's swords...")
        mesh = self.create_swords()
        lo, hi = mesh.bounds
        print(f"  {len(mesh.vertices)} vertices / {len(mesh.faces)} faces")
        print(f"  span x {hi[0] - lo[0]:.3f} m, y {hi[1] - lo[1]:.3f} m, "
              f"z {hi[2] - lo[2]:.3f} m")
        # CODEX ROUND 1 (bead z629) — this script runs in CI's rebuild loop, so
        # it grades its own homework: positive signed volume (outward winding —
        # it shipped inside-out once), opaque alphas everywhere, and the hilt's
        # silver wrap highlight present (it shipped truncated to black once).
        assert mesh.volume > 0, f"swords wound inward: volume {mesh.volume}"
        vc = np.asarray(mesh.visual.vertex_colors)
        assert (vc[:, 3] == 255).all(), "non-opaque vertex alpha in swords"
        highlight = rgba8(self.colors['hilt_b'])
        assert (vc == highlight).all(axis=1).any(), "hilt wrap highlight gone"
        print(f"  volume +{mesh.volume:.6f} m3, alphas opaque, silver present")
        filename = output_dir / "primm_swords.glb"
        export_faceted(mesh, str(filename))
        print(f"\n  Saved to {filename}")


def main():
    # Output next to this repo regardless of where the script is run from.
    repo_root = Path(__file__).resolve().parent.parent
    output_dir = repo_root / "assets" / "models" / "characters" / "primm_parts"

    generator = PrimmSwordsGenerator()
    generator.generate_and_save(output_dir)

    print("\n  Primm's swords generated successfully!")
    print("  Hung on spine_03 by scenes/characters/primm.tscn")


if __name__ == "__main__":
    main()
