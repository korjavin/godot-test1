#!/usr/bin/env python3
"""
Generate the RIDDEN BIKE — `shared_parts/bike.glb`, the bicycle the hero rides
in epic godot-test1-z2yv (owner ruling 8, 2026-09-20: "the ridden bike is a
generated .glb"). Bead godot-test1-z2yv.5. The pattern is
`generate_windman_fan.py`'s and `generate_primm_swords.py`'s exactly: a rigid
trimesh prop of boxes and cylinders, faceted vertex colours, out through
`predator_parts.export_faceted()`, rebuilt and diffed by CI beside the fan and
the swords (third name in `.github/workflows/build.yml`'s prop loop). A ridden
bike moves with the player, so it can never be chunk-batch content — it is a
hero prop, instanced once for all four heroes (bead z2yv.7), which is why it
lives in `shared_parts/` and not a per-hero dir.

Requires the PINNED toolchain of `scripts/requirements.txt` — trimesh + numpy.
    pip install -r scripts/requirements.txt

COORDINATE CONVENTION (do not move it — beads z2yv.6/.7 pose around it):
  * Godot frame straight out of trimesh: **+X forward, Y up**, and
    `export_faceted` writes those axes through unchanged.
  * **y = 0 at the wheel bottoms** (both wheel centres at y = WHEEL_R).
  * **The origin is under the saddle** — the saddle spans x in [-0.18, +0.08],
    so x = 0 sits inside its footprint; the hero's pelvis lands there.
  * Wheels roll in the X-Y plane, axles along Z.

Design numbers, in metres:
  * Wheels: cylinders, radius 0.35, width 0.05, 8-sided (faceted read, no
    smoothing), centres at x = -0.55 (rear) / +0.55 (front), y = 0.35.
  * Overall length 1.80 (rear tyre back edge -0.90 to front tyre front edge
    +0.90), overall height 0.965 (ground to handlebar top).
  * Frame: six thin tubes (top, down, seat, chain stay, seat stay, fork) plus
    seat post, bottom-bracket shell, stem, saddle and handlebar.

RNG / DETERMINISM: no RNG anywhere (the fan has none either). The wheels are
laid with axis-aligned transforms only (translate, no rotation — the cylinder
primitive already spins about Z, which is the axle). The diagonal frame tubes
are oriented by a hand-rolled rotation about Z built from the segment's own
normalized direction (sqrt + divide: IEEE-754 exactly rounded, no
transcendental anywhere in this file), so `export_faceted`'s byte-compare gate
holds on macOS/arm64 and the Linux runner alike.
"""

import numpy as np
import trimesh
from pathlib import Path

# THE ONE EXPORT SEAM for every model in this game (bead godot-test1-y1o.21,
# owner ruling 2026-09-05 "facet ALL"): it unmerges the mesh and writes flat
# per-face normals. It lives in predator_parts.py because the predators got it
# first — read its docstring before touching anything about normals here.
import sys  # noqa: E402
sys.path.insert(0, str(Path(__file__).resolve().parent))
from predator_parts import export_faceted  # noqa: E402


# The design numbers, in metres. See the module docstring for the frame.
WHEEL_R = 0.35          # wheel radius — the y = 0 and height contracts rest here
WHEEL_W = 0.05          # wheel width (axle along Z)
WHEEL_SECTIONS = 8      # faceted read: 8-sided, no smoothing
REAR_X = -0.55          # rear axle x
FRONT_X = 0.55          # front axle x
AXLE_Y = WHEEL_R        # both axles one radius off the ground
BB = (0.0, 0.30)        # bottom bracket
SEAT_TOP = (-0.05, 0.88)  # seat-tube top, under the saddle (origin above it)
HEAD_TOP = (0.52, 0.86)   # head-tube top
HEAD_BOT = (0.58, 0.66)   # head-tube bottom (fork crown)
TUBE = 0.035            # frame-tube square section — thin
FACE_BUDGET = 300       # the bead's face budget, asserted in generate_and_save
LENGTH_RANGE = (1.6, 2.0)  # overall x span contract
HEIGHT_RANGE = (0.9, 1.1)  # overall y span contract


def rgba8(c):
    """Palette (normalized float RGBA) -> 0-255 uint8 row, the ONE conversion.

    trimesh `vertex_colors` are uint8; handing them floats truncated Primm's
    hilt silver to [0,0,0,1] (codex round 1, bead z629). Every assignment below
    goes through here.
    """
    return np.round(np.array(c, dtype=np.float64) * 255).astype(np.uint8)


class BikeGenerator:
    def __init__(self):
        # The bike's own palette. Ungraded — props carry no skin grade (the
        # fan's comment says why): deep red frame, graphite wheels, brown
        # saddle, gunmetal furniture.
        self.colors = {
            'frame':   [0.620, 0.070, 0.090, 1.0],
            'wheel':   [0.080, 0.080, 0.090, 1.0],
            'saddle':  [0.350, 0.220, 0.120, 1.0],
            'metal':   [0.500, 0.520, 0.550, 1.0],
        }

    def _paint(self, mesh, color_key):
        """One solid uint8 colour over every vertex."""
        mesh.visual.vertex_colors = np.tile(
            rgba8(self.colors[color_key]), (len(mesh.vertices), 1))
        return mesh

    def _tube(self, a, b, thick, wide, color_key):
        """A thin box from point (x, y) A to point (x, y) B, full width `wide`
        in Z.

        Oriented by a hand-rolled rotation about Z from the segment's own unit
        direction — sqrt and divide only, both IEEE-754 exactly rounded, so no
        libm transcendental can differ between macOS/arm64 and the Linux
        runner (the bead's determinism clause). `trimesh.creation.box` is pure
        arithmetic on the extents.
        """
        a = np.array(a, dtype=np.float64)
        b = np.array(b, dtype=np.float64)
        d = b - a
        length = float(np.sqrt((d * d).sum()))
        u = d / length
        tube = trimesh.creation.box(extents=[length, thick, wide])
        rot = np.eye(4)
        rot[:2, :2] = [[u[0], -u[1]], [u[1], u[0]]]  # +X onto u, about +Z
        tube.apply_transform(rot)
        tube.apply_translation([(a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0, 0.0])
        return self._paint(tube, color_key)

    def _box(self, center, extents, color_key):
        """An axis-aligned box. No rotation at all."""
        mesh = trimesh.creation.box(extents=extents)
        mesh.apply_translation(center)
        return self._paint(mesh, color_key)

    def _wheel(self, x):
        """One 8-sided wheel: the cylinder primitive spins about Z already, so
        the axle lands along Z with a pure translation — no rotation laid here
        (the bead's determinism clause)."""
        wheel = trimesh.creation.cylinder(radius=WHEEL_R, height=WHEEL_W,
                                         sections=WHEEL_SECTIONS)
        assert wheel.volume > 0, f"wheel wound inward: volume {wheel.volume}"
        wheel.apply_translation([x, AXLE_Y, 0.0])
        return self._paint(wheel, 'wheel')

    def create_bike(self):
        """The whole bike, origin under the saddle, y = 0 at the wheel bottoms."""
        parts = [
            self._wheel(REAR_X),
            self._wheel(FRONT_X),
            # Frame: top tube, down tube, seat tube, chain stay, seat stay,
            # fork — the bead's 4-5 thin boxes, six with the fork.
            self._tube(SEAT_TOP, HEAD_TOP, TUBE, TUBE, 'frame'),
            self._tube(BB, HEAD_BOT, TUBE, TUBE, 'frame'),
            self._tube(BB, SEAT_TOP, TUBE, TUBE, 'frame'),
            self._tube(BB, (REAR_X, AXLE_Y), 0.03, 0.03, 'frame'),
            self._tube(SEAT_TOP, (REAR_X, AXLE_Y), 0.03, 0.03, 'frame'),
            self._tube(HEAD_BOT, (FRONT_X, AXLE_Y), 0.03, 0.03, 'frame'),
            # Seat post + saddle (origin sits inside the saddle's footprint).
            self._box((-0.05, 0.895, 0.0), (0.03, 0.05, 0.03), 'metal'),
            self._box((-0.05, 0.91, 0.0), (0.26, 0.06, 0.09), 'saddle'),
            # Bottom-bracket shell, stem, handlebar.
            self._box((BB[0], BB[1], 0.0), (0.06, 0.06, 0.08), 'metal'),
            self._tube(HEAD_TOP, (0.50, 0.95), 0.03, 0.03, 'metal'),
            self._box((0.50, 0.95, 0.0), (0.03, 0.03, 0.42), 'metal'),
        ]
        return trimesh.util.concatenate(parts)

    # ------------------------------------------------------------------- driver
    def generate_and_save(self, output_dir):
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        print("Generating the ridden bike...")
        mesh = self.create_bike()
        print(f"  {len(mesh.vertices)} vertices / {len(mesh.faces)} faces")
        # THE FACE BUDGET FIRST, before bounds: an empty build has no bounds
        # to measure, and this assert — not a None-unpack TypeError — is what
        # must fail it (z2yv.5 acceptance 2).
        assert 0 < len(mesh.faces) <= FACE_BUDGET, \
            f"face budget blown: {len(mesh.faces)} faces (budget {FACE_BUDGET})"
        lo, hi = mesh.bounds
        length, height = hi[0] - lo[0], hi[1] - lo[1]
        print(f"  length {length:.3f} m, height {height:.3f} m, "
              f"wheel bottom y {lo[1]:.4f} m")
        # THE EXTENT CONTRACTS (z2yv.5 acceptance 4): asserted on what was just
        # built, so a wrong number fails the build rather than shipping a bike
        # z2yv.6 cannot pose.
        assert LENGTH_RANGE[0] <= length <= LENGTH_RANGE[1], \
            f"length {length:.3f} m outside {LENGTH_RANGE}"
        assert HEIGHT_RANGE[0] <= height <= HEIGHT_RANGE[1], \
            f"height {height:.3f} m outside {HEIGHT_RANGE}"
        assert abs(lo[1]) <= 0.01, \
            f"wheel bottom at y {lo[1]:.4f}, not 0 +- 0.01"
        assert mesh.volume > 0, f"bike wound inward: volume {mesh.volume}"
        vc = np.asarray(mesh.visual.vertex_colors)
        assert (vc[:, 3] == 255).all(), "non-opaque vertex alpha in bike"
        print(f"  budget ok, extents ok, grounded, volume +{mesh.volume:.6f} m3")
        filename = output_dir / "bike.glb"
        export_faceted(mesh, str(filename))
        print(f"\n  Saved to {filename}")
        # NORMALS PRESENT (acceptance 3, the fan's verify pattern): reload the
        # artifact and prove the NORMAL accessor survived the export — plain
        # `mesh.export` writes none, and this is what catches that mutation.
        # A .glb loads as a Scene (one node per primitive) — force one
        # mesh so the NORMAL accessor reads off combined vertices.
        reloaded = trimesh.load(str(filename), process=False, force='mesh')
        assert reloaded.vertex_normals is not None \
            and len(reloaded.vertex_normals) == len(reloaded.vertices), \
            "NORMAL accessor missing in bike.glb — export_faceted bypassed?"
        # UNMERGED (acceptance 3's sharp edge): plain `mesh.export` writes the
        # WELDED mesh — shared corner vertices — and trimesh even computes
        # smooth normals for it on the way out, so the NORMAL check above
        # passes on the mutation. One vertex per face corner is the artifact
        # half of `export_faceted`'s contract, and only the faceted path has
        # it; this assert is what goes red on a plain export.
        assert len(reloaded.vertices) == 3 * len(reloaded.faces), \
            f"bike.glb not unmerged ({len(reloaded.vertices)} verts for " \
            f"{len(reloaded.faces)} faces) — export_faceted bypassed?"
        assert np.isfinite(np.asarray(reloaded.vertex_normals)).all(), \
            "non-finite normal in bike.glb"
        print("  NORMAL accessor present, all finite")


def main():
    # Output next to this repo regardless of where the script is run from.
    repo_root = Path(__file__).resolve().parent.parent
    output_dir = repo_root / "assets" / "models" / "characters" / "shared_parts"

    generator = BikeGenerator()
    generator.generate_and_save(output_dir)

    print("\n  Ridden bike generated successfully!")
    print("  Instanced once for all four heroes (bead z2yv.7)")


if __name__ == "__main__":
    main()
