#!/usr/bin/env python3
"""
Generate the city Clown model -> assets/models/characters/clown.glb

The CITY band's boss ("clown like in 'It' of King (inspired)"): an uncanny stylized
clown with an exaggerated high pale forehead, sinister wide red grin, wild flared
orange-red hair tufts, tiered Victorian neck ruff, dark vintage circus suit with
bright red pom-poms, oversized bulbous curled-toe clown shoes, and a raised throwing
arm holding a toxic ice-cream cone (projectile keystone).

An ENEMY model: a single static vertex-coloured GLB honouring the enemy-model
contract (nose along +X, up along +Y, feet at y = 0, single mesh, no named child
nodes).

    python3 scripts/generate_clown.py
"""

import pathlib
import sys

import numpy as np
import trimesh

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

# The one export seam: flat per-face normals. See predator_parts.export_faceted.
from predator_parts import export_faceted  # noqa: E402

OUT_DIR = pathlib.Path(__file__).resolve().parent.parent / "assets" / "models" / "characters"

# --- Palette. READ THE GAMMA NOTE BEFORE EDITING. -----------------------------
#
# THESE HEXES ARE LINEAR, NOT sRGB — exactly as in generate_snake.py. Godot
# imports GLB vertex colours with `vertex_color_is_srgb = false`, so each byte
# reaches ALBEDO as-is and every constant here renders MUCH LIGHTER than it looks
# in a text editor. Pick a colour by deciding the DISPLAYED value and converting
# back (`linear = ((srgb + 0.055) / 1.055) ** 2.4`), never by eye off the hex.
#
# MEASURED against this boss's own band. City ground in assets/shaders/ground.gdshader
# is `city_color` (vec3(0.50, 0.48, 0.45), displays #b9b6b1, mean linear lum 0.4821)
# mottled +-12% (lum range 0.4242 - 0.5399).
#
# The clown's dark Victorian circus suit provides sharp high contrast against the
# mid-grey city flagstones, while the pale face and crimson accents pop vividly:
#
#   SUIT_DARK       #14141c displays #3c3c4b (Victorian circus suit)-> vs city 5.22 - 6.49 : 1 (mean 5.85 : 1)
#   RED_ACCENT      #7a0606 displays #9f1c1c (crimson grin/nose/pom)-> vs city 2.79 - 3.47 : 1 (mean 3.13 : 1)
#   RUFF_SILVER     #383842 displays #60606c (ruffles / collar)     -> vs city 2.59 - 3.22 : 1 (mean 2.90 : 1)
#   SHOE_RED        #800606 displays #a51c1c (oversized clown shoes)-> vs city 2.52 - 3.14 : 1 (mean 2.83 : 1)
#   ICE_CREAM_PINK  #9c1438 displays #c93562 (ice cream scoop)      -> vs city 1.88 - 2.34 : 1 (mean 2.11 : 1)
#   HAIR_ORANGE     #9c2c06 displays #c9561a (wild flared hair)     -> vs city 1.55 - 1.93 : 1 (mean 1.74 : 1)
#   FACE_WHITE      #dcd4c8 displays #eee7dd (ghostly pale face)    -> vs city 1.50 - 1.87 : 1 (mean 1.66 : 1)
#                   ...read against the dark ruff & orange hair (6.3 : 1 against suit)
#   CONE_WAFFLE     #704810 displays #976b28 (waffle cone)          -> vs city 1.36 - 1.69 : 1
#   DARK_SOLE       #050507 displays #14141c (shoe soles)           -> vs city 9.8 : 1
FACE_WHITE = "#dcd4c8"      # ghostly pale white
RED_ACCENT = "#7a0606"      # sinister crimson (nose, grin, streaks, pom-poms)
HAIR_ORANGE = "#9c2c06"     # wild orange hair tufts
SUIT_DARK = "#14141c"       # dark vintage Victorian circus suit
SUIT_STRIPE = "#22222c"     # subtle vintage fabric stripe
RUFF_SILVER = "#383842"     # ruffled Elizabethan collar and cuffs
SHOE_RED = "#800606"        # oversized red clown shoes
SHOE_TOE = "#9c6c0a"        # antique gold bulbous shoe toe
ICE_CREAM_PINK = "#9c1438"  # strawberry ice cream scoop
CONE_WAFFLE = "#704810"     # waffle cone
EYE_YELLOW = "#c89008"      # eerie amber eyes
GLOVE_WHITE = "#d0c8c0"     # pale gloved hands
DARK_SOLE = "#050507"       # shoe soles

MAX_FACES = 1200


def rgba(hex_color: str, alpha: int = 255) -> np.ndarray:
    """'#2d5016' -> float RGBA array for trimesh vertex colours."""
    h = hex_color.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)] + [alpha]) / 255.0


def box(size, pos, color, pitch: float = 0.0, roll: float = 0.0, yaw: float = 0.0) -> trimesh.Trimesh:
    """One faceted box: `size` is (len_x, height_y, width_z), `pos` is centre."""
    m = trimesh.creation.box(extents=size)
    if pitch:
        m.apply_transform(trimesh.transformations.rotation_matrix(pitch, [0, 0, 1]))
    if roll:
        m.apply_transform(trimesh.transformations.rotation_matrix(roll, [1, 0, 0]))
    if yaw:
        m.apply_transform(trimesh.transformations.rotation_matrix(yaw, [0, 1, 0]))
    m.visual.vertex_colors = color
    m.apply_translation(pos)
    return m


def spike(base: float, height: float, pos, color, roll: float = 0.0, pitch: float = 0.0, yaw: float = 0.0) -> trimesh.Trimesh:
    """An upward 4-sided pyramid with base centre at `pos`."""
    m = trimesh.creation.cone(radius=base, height=height, sections=4)
    m.apply_transform(trimesh.transformations.rotation_matrix(-np.pi / 2, [1, 0, 0]))
    if roll:
        m.apply_transform(trimesh.transformations.rotation_matrix(roll, [1, 0, 0]))
    if pitch:
        m.apply_transform(trimesh.transformations.rotation_matrix(pitch, [0, 0, 1]))
    if yaw:
        m.apply_transform(trimesh.transformations.rotation_matrix(yaw, [0, 1, 0]))
    m.visual.vertex_colors = color
    m.apply_translation(pos)
    return m


def cone_primitive(radius: float, height: float, pos, color, pitch: float = 0.0, roll: float = 0.0, sections: int = 8) -> trimesh.Trimesh:
    """A cone with base at origin, pointing along +Z before rotations."""
    m = trimesh.creation.cone(radius=radius, height=height, sections=sections)
    m.apply_transform(trimesh.transformations.rotation_matrix(-np.pi / 2, [1, 0, 0]))
    if roll:
        m.apply_transform(trimesh.transformations.rotation_matrix(roll, [1, 0, 0]))
    if pitch:
        m.apply_transform(trimesh.transformations.rotation_matrix(pitch, [0, 0, 1]))
    m.visual.vertex_colors = color
    m.apply_translation(pos)
    return m


def build_clown() -> trimesh.Trimesh:
    c_face, c_red, c_hair = rgba(FACE_WHITE), rgba(RED_ACCENT), rgba(HAIR_ORANGE)
    c_suit, c_stripe, c_ruff = rgba(SUIT_DARK), rgba(SUIT_STRIPE), rgba(RUFF_SILVER)
    c_shoe, c_shoetoe, c_sole = rgba(SHOE_RED), rgba(SHOE_TOE), rgba(DARK_SOLE)
    c_ice, c_cone, c_eye, c_glove = rgba(ICE_CREAM_PINK), rgba(CONE_WAFFLE), rgba(EYE_YELLOW), rgba(GLOVE_WHITE)
    parts = []

    # --- 1. Oversized Clown Shoes & Ankle Ruffles (Z = +/- 0.16)
    for side in (1.0, -1.0):
        z = side * 0.16
        # Sole: elongated forward
        parts.append(box((0.36, 0.04, 0.16), (0.06, 0.02, z), c_sole))
        # Red heel & body of shoe
        parts.append(box((0.22, 0.10, 0.15), (-0.02, 0.08, z), c_shoe))
        # Huge bulbous front toe (curving upward)
        parts.append(box((0.16, 0.12, 0.17), (0.16, 0.09, z), c_shoe))
        parts.append(box((0.08, 0.10, 0.14), (0.22, 0.12, z), c_shoetoe, pitch=0.3))
        parts.append(box((0.04, 0.04, 0.04), (0.24, 0.16, z), c_red))  # toe pom-pom
        # Ankle ruff
        parts.append(box((0.16, 0.05, 0.16), (0.0, 0.16, z), c_ruff))
        # Puffy lower leg pantaloons
        parts.append(box((0.18, 0.30, 0.18), (0.0, 0.32, z), c_suit))
        parts.append(box((0.20, 0.26, 0.04), (0.0, 0.32, z + side * 0.08), c_stripe))
        # Knee puff
        parts.append(box((0.20, 0.08, 0.20), (0.0, 0.48, z), c_ruff))
        # Puffy upper thigh pantaloons
        parts.append(box((0.20, 0.26, 0.20), (0.0, 0.62, z), c_suit))

    # --- 2. Puffed Waist & Peplum Frills
    parts.append(box((0.28, 0.18, 0.42), (0.0, 0.78, 0.0), c_suit))
    # Flared peplum frill around waist
    parts.append(box((0.34, 0.06, 0.48), (0.0, 0.74, 0.0), c_ruff))
    parts.append(box((0.36, 0.04, 0.50), (0.0, 0.72, 0.0), c_stripe))

    # --- 3. Torso & Bodice with 3 Bright Red Pom-Poms
    parts.append(box((0.28, 0.32, 0.42), (0.0, 0.98, 0.0), c_suit))
    parts.append(box((0.30, 0.30, 0.20), (0.02, 0.98, 0.0), c_stripe))
    # 3 Bright Red Pom-Poms down chest
    parts.append(box((0.06, 0.06, 0.06), (0.16, 1.10, 0.0), c_red))
    parts.append(box((0.06, 0.06, 0.06), (0.16, 0.98, 0.0), c_red))
    parts.append(box((0.06, 0.06, 0.06), (0.16, 0.86, 0.0), c_red))

    # --- 4. Massive Tiered Elizabethan Neck Ruff
    parts.append(box((0.38, 0.06, 0.52), (0.02, 1.15, 0.0), c_ruff))
    parts.append(box((0.42, 0.05, 0.58), (0.02, 1.19, 0.0), c_ruff))
    parts.append(box((0.36, 0.05, 0.50), (0.02, 1.23, 0.0), c_ruff))
    parts.append(box((0.44, 0.02, 0.60), (0.02, 1.19, 0.0), c_red))

    # --- 5. Left Arm (uncanny dangling pose at side)
    lz = -0.28
    parts.append(box((0.16, 0.14, 0.16), (0.0, 1.12, lz), c_suit))
    parts.append(box((0.12, 0.22, 0.12), (0.02, 0.96, lz), c_suit, pitch=-0.1))
    parts.append(box((0.15, 0.05, 0.15), (0.04, 0.84, lz), c_ruff))
    parts.append(box((0.11, 0.20, 0.11), (0.08, 0.74, lz), c_suit, pitch=0.2))
    parts.append(box((0.14, 0.05, 0.14), (0.11, 0.64, lz), c_ruff))
    parts.append(box((0.10, 0.10, 0.08), (0.14, 0.57, lz), c_glove))
    parts.append(box((0.08, 0.04, 0.06), (0.19, 0.55, lz), c_glove, pitch=0.4))

    # --- 6. Right Arm (raised high in throwing pose, holding ice cream projectile)
    rz = 0.28
    parts.append(box((0.16, 0.14, 0.16), (0.0, 1.14, rz), c_suit))
    parts.append(box((0.13, 0.22, 0.13), (-0.06, 1.22, rz), c_suit, pitch=-0.6))
    parts.append(box((0.15, 0.05, 0.15), (-0.14, 1.29, rz), c_ruff))
    parts.append(box((0.24, 0.12, 0.12), (-0.04, 1.36, rz), c_suit, pitch=0.4))
    parts.append(box((0.14, 0.05, 0.14), (0.06, 1.40, rz), c_ruff))
    parts.append(box((0.10, 0.10, 0.10), (0.12, 1.42, rz), c_glove))

    # Ice cream cone in right hand
    cone_x, cone_y, cone_z = 0.14, 1.44, rz
    parts.append(cone_primitive(0.065, 0.20, (cone_x, cone_y, cone_z), c_cone, pitch=-np.pi / 3, sections=8))
    scoop_x, scoop_y = cone_x + 0.10, cone_y + 0.12
    parts.append(box((0.14, 0.14, 0.14), (scoop_x, scoop_y, cone_z), c_ice))
    parts.append(box((0.16, 0.08, 0.12), (scoop_x - 0.02, scoop_y - 0.04, cone_z), c_ice))
    parts.append(box((0.05, 0.05, 0.05), (scoop_x + 0.04, scoop_y + 0.08, cone_z), c_red))

    # --- 7. Head & Face (Uncanny Pennywise / "It" inspired)
    neck_y = 1.25
    parts.append(box((0.14, 0.08, 0.14), (0.02, neck_y, 0.0), c_face))
    head_y = 1.40
    parts.append(box((0.22, 0.24, 0.20), (0.04, head_y, 0.0), c_face))
    parts.append(box((0.18, 0.12, 0.18), (0.08, head_y + 0.08, 0.0), c_face))

    # Wild orange-red hair tufts flaring out at temples
    for side in (1.0, -1.0):
        hz = side * 0.13
        parts.append(spike(0.07, 0.18, (0.0, head_y + 0.04, hz), c_hair, roll=side * 0.7, pitch=-0.2))
        parts.append(spike(0.06, 0.14, (-0.04, head_y + 0.08, hz), c_hair, roll=side * 0.8))
        parts.append(box((0.10, 0.12, 0.08), (-0.02, head_y + 0.02, hz), c_hair))

    # Sinister Face Details:
    for side in (1.0, -1.0):
        ez = side * 0.055
        parts.append(box((0.04, 0.035, 0.035), (0.14, head_y + 0.02, ez), c_eye))
        parts.append(box((0.03, 0.16, 0.02), (0.145, head_y + 0.02, ez), c_red))

    # Big round bright red clown nose
    parts.append(box((0.07, 0.07, 0.07), (0.17, head_y - 0.01, 0.0), c_red))

    # Exaggerated sinister red grin / smile curving upward to cheeks
    parts.append(box((0.06, 0.04, 0.16), (0.15, head_y - 0.07, 0.0), c_red))
    parts.append(box((0.04, 0.025, 0.10), (0.16, head_y - 0.07, 0.0), c_face))
    for side in (1.0, -1.0):
        parts.append(box((0.04, 0.06, 0.03), (0.14, head_y - 0.04, side * 0.09), c_red, roll=side * 0.3))

    mesh = trimesh.util.concatenate(parts)
    mesh.apply_translation([0.0, -mesh.bounds[0][1], 0.0])
    return mesh


def verify_clown(mesh: trimesh.Trimesh) -> None:
    """Assert enemy-model contracts and sanity bounds."""
    assert len(mesh.faces) > 0, "clown: empty mesh"
    assert len(mesh.faces) <= MAX_FACES, f"clown: {len(mesh.faces)} faces exceeds {MAX_FACES}"

    lo, hi = mesh.bounds
    assert abs(lo[1]) < 1e-6, f"clown: feet at y={lo[1]:.4f}, must be 0"
    assert 1.4 <= hi[1] <= 1.9, f"clown: height {hi[1]:.2f}m outside expected range [1.4, 1.9]"

    length = hi[0] - lo[0]
    assert 0.4 <= length <= 2.2, f"clown: length {length:.2f}m outside [0.4, 2.2]"
    assert hi[0] > 0.0, "clown: nothing forward of origin (+X facing required)"

    bias = hi[2] + lo[2]
    assert abs(bias) <= 0.05, f"clown: off-centre on z (bias {bias:.4f})"

    colors = mesh.visual.vertex_colors
    assert colors is not None and len(colors) == len(mesh.vertices), "clown: missing vertex colors"


def save_clown() -> trimesh.Trimesh:
    mesh = build_clown()
    verify_clown(mesh)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / "clown.glb"
    export_faceted(mesh, path)
    lo, hi = mesh.bounds
    print(f"✓ clown: {path}")
    print(f"  {len(mesh.vertices)} verts / {len(mesh.faces)} faces")
    print(f"  {hi[0] - lo[0]:.2f} m long, {hi[1]:.2f} m tall, {hi[2] - lo[2]:.2f} m wide")
    return mesh


if __name__ == "__main__":
    save_clown()
