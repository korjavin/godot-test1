#!/usr/bin/env python3
"""
Generate the snow Titan model -> assets/models/characters/titan.glb

The SNOW band's boss ("Tower titan inspired by hmm3"): a towering, broad armored
humanoid colossus in sapphire plate armor with antique gold trim, cold blue-steel
cuirass, glowing lightning eyes, and a crackling lightning javelin in hand.

Unlike player characters (which use separate limb GLBs driven by named-node sine
oscillations), the Titan is an ENEMY model: a single static vertex-coloured GLB
honouring the enemy-model contract (nose along +X, up along +Y, feet at y = 0,
single mesh, no named child nodes).

    python3 scripts/generate_titan.py
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
# MEASURED against this boss's own band. Snow ground in assets/shaders/ground.gdshader
# is `snow_color` (vec3(0.85, 0.89, 0.93), displays #f2f5f8, mean linear lum 0.8844)
# mottled +-12% (lum range 0.7783 - 0.9905).
#
# Snow is near-white ground — the INVERSE of the sand-viper bug: a pale titan
# would vanish on snow, so it needs deep saturated plates and dark under-armor:
#
#   SAPPHIRE    #0a1836 displays #1f385c (deep royal blue) -> vs snow 5.88 - 7.38 : 1 (mean 6.63 : 1)
#   NAVY_DARK   #040814 displays #101a2a (shadow under-armor)-> vs snow 10.17 - 12.78 : 1 (mean 11.47 : 1)
#   STEEL       #344458 displays #5c6c80 (cuirass center)   -> vs snow 3.25 - 4.10 : 1
#   GOLD        #8c6210 displays #cb9428 (pauldrons / trim) -> vs snow 1.86 - 2.33 : 1
#               ...read ON the sapphire plates (3.17 : 1 against sapphire)
#   CYAN_GLOW   #10c8e8 displays #3fe7fa (lightning eyes)   -> vs sapphire 4.45 : 1
#   WHITE_CORE  #e0f0fc displays #f8fcff (javelin core)     -> vs sapphire 7.20 : 1
#   DARK_SOLE   #020306 displays #0a0e14 (boot soles)       -> vs snow 15.0 : 1
SAPPHIRE = "#0a1836"    # main armor plates, greaves, tassets
NAVY_DARK = "#040814"   # under-armor suit, shadow joints
STEEL = "#344458"       # cold blue-steel breastplate
GOLD = "#8c6210"        # antique gold pauldrons, belt, crown, trims
CYAN_GLOW = "#10c8e8"   # electric lightning eyes, core, javelin spark
WHITE_CORE = "#e0f0fc"  # javelin center core / high sparks
DARK_SOLE = "#020306"   # heavy boot soles

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


def build_titan() -> trimesh.Trimesh:
    c_sapphire, c_navy, c_steel = rgba(SAPPHIRE), rgba(NAVY_DARK), rgba(STEEL)
    c_gold, c_cyan, c_white, c_sole = rgba(GOLD), rgba(CYAN_GLOW), rgba(WHITE_CORE), rgba(DARK_SOLE)
    parts = []

    # --- 1. Legs & Heavy Armored Boots (mirrored on Z = +/- 0.18)
    for side in (1.0, -1.0):
        z = side * 0.18
        # Boot sole & shoe
        parts.append(box((0.26, 0.05, 0.14), (0.02, 0.025, z), c_sole))
        parts.append(box((0.24, 0.10, 0.13), (0.01, 0.09, z), c_sapphire))
        # Boot toe cap
        parts.append(box((0.08, 0.07, 0.11), (0.10, 0.07, z), c_gold))
        # Greaves / shins
        parts.append(box((0.15, 0.32, 0.14), (0.0, 0.28, z), c_sapphire))
        parts.append(box((0.04, 0.26, 0.08), (0.08, 0.28, z), c_gold))  # shin ridge
        # Knee guard
        parts.append(box((0.07, 0.09, 0.15), (0.06, 0.46, z), c_gold))
        parts.append(box((0.03, 0.05, 0.07), (0.09, 0.46, z), c_cyan))  # knee gem
        # Thighs
        parts.append(box((0.16, 0.34, 0.15), (0.0, 0.65, z), c_navy))
        parts.append(box((0.04, 0.28, 0.12), (0.07, 0.65, z), c_sapphire))  # thigh plate

    # --- 2. Pelvis & Armored Faulds (Waist)
    parts.append(box((0.24, 0.16, 0.38), (0.0, 0.88, 0.0), c_navy))
    parts.append(box((0.28, 0.09, 0.42), (0.0, 0.98, 0.0), c_gold))  # heavy belt
    parts.append(box((0.05, 0.11, 0.12), (0.14, 0.98, 0.0), c_gold))  # buckle plate
    parts.append(box((0.02, 0.06, 0.06), (0.16, 0.98, 0.0), c_cyan))  # buckle lightning gem

    # Front center tasset
    parts.append(box((0.04, 0.22, 0.14), (0.13, 0.84, 0.0), c_sapphire))
    parts.append(box((0.02, 0.20, 0.03), (0.15, 0.84, 0.0), c_gold))
    # Side tassets
    for side in (1.0, -1.0):
        parts.append(box((0.22, 0.18, 0.04), (0.0, 0.85, side * 0.22), c_sapphire))
        parts.append(box((0.20, 0.04, 0.02), (0.0, 0.77, side * 0.24), c_gold))
    # Rear tasset
    parts.append(box((0.04, 0.18, 0.28), (-0.13, 0.86, 0.0), c_sapphire))

    # --- 3. Torso & Heavy Cuirass
    parts.append(box((0.26, 0.18, 0.40), (0.0, 1.10, 0.0), c_navy))  # abdomen
    parts.append(box((0.04, 0.14, 0.24), (0.13, 1.10, 0.0), c_sapphire))  # ab plates
    # Broad chest / cuirass
    parts.append(box((0.34, 0.32, 0.52), (0.02, 1.34, 0.0), c_sapphire))
    # Steel breastplate center
    parts.append(box((0.07, 0.26, 0.38), (0.18, 1.36, 0.0), c_steel))
    # Gold chest trim / crest
    parts.append(box((0.03, 0.06, 0.44), (0.21, 1.44, 0.0), c_gold))
    parts.append(box((0.04, 0.14, 0.08), (0.21, 1.34, 0.0), c_gold))  # sternum pillar
    # Glowing lightning energy core
    parts.append(box((0.03, 0.10, 0.10), (0.22, 1.34, 0.0), c_cyan))
    # Gorget (neck guard)
    parts.append(box((0.24, 0.07, 0.28), (0.02, 1.52, 0.0), c_gold))

    # --- 4. Shoulders & Tiered Pauldrons (mirrored at Z = +/- 0.33)
    for side in (1.0, -1.0):
        sz = side * 0.33
        # Main upper pauldron (tiered gold & sapphire)
        parts.append(box((0.28, 0.14, 0.20), (0.02, 1.54, sz), c_gold))
        parts.append(box((0.24, 0.12, 0.16), (0.02, 1.45, sz + side * 0.04), c_sapphire))
        # Pauldron top ridge & crest spike
        parts.append(box((0.26, 0.04, 0.04), (0.02, 1.62, sz), c_gold))
        parts.append(spike(0.04, 0.10, (0.02, 1.62, sz), c_gold, roll=side * 0.2))

    # --- 5. Left Arm (clenched armored fist at side, combat ready)
    lz = -0.33
    parts.append(box((0.14, 0.24, 0.14), (0.02, 1.36, lz), c_navy))  # upper arm
    parts.append(box((0.16, 0.07, 0.16), (0.02, 1.22, lz), c_gold))  # couter / elbow
    parts.append(box((0.18, 0.20, 0.15), (0.06, 1.08, lz), c_sapphire, pitch=0.2))  # gauntlet
    parts.append(box((0.12, 0.12, 0.12), (0.12, 0.96, lz), c_steel))  # clenched fist
    parts.append(box((0.04, 0.08, 0.08), (0.17, 0.96, lz), c_gold))  # knuckle guard

    # --- 6. Right Arm (raised ready with thunderbolt spear)
    rz = 0.33
    parts.append(box((0.14, 0.22, 0.14), (-0.02, 1.40, rz), c_navy, pitch=-0.3))
    parts.append(box((0.16, 0.07, 0.16), (-0.08, 1.38, rz), c_gold))
    parts.append(box((0.24, 0.14, 0.14), (0.05, 1.44, rz), c_sapphire, pitch=0.15))
    parts.append(box((0.12, 0.12, 0.12), (0.18, 1.47, rz), c_steel))  # gripping hand
    parts.append(box((0.04, 0.08, 0.08), (0.20, 1.47, rz), c_gold))

    # Thunderbolt Spear (crackling zigzag lightning javelin)
    bolt_z = rz
    parts.append(box((0.70, 0.05, 0.05), (0.12, 1.47, bolt_z), c_cyan))
    parts.append(box((0.40, 0.03, 0.03), (0.12, 1.47, bolt_z), c_white))  # white-hot core
    # Forward lightning arrowhead
    parts.append(box((0.18, 0.05, 0.04), (0.48, 1.51, bolt_z), c_cyan, pitch=0.4))
    parts.append(box((0.16, 0.04, 0.04), (0.56, 1.47, bolt_z), c_cyan, pitch=-0.5))
    parts.append(spike(0.04, 0.14, (0.62, 1.47, bolt_z), c_white, pitch=-np.pi / 2))
    # Rear lightning zigzags
    parts.append(box((0.16, 0.04, 0.04), (-0.24, 1.51, bolt_z), c_cyan, pitch=-0.4))
    parts.append(box((0.14, 0.04, 0.04), (-0.30, 1.45, bolt_z), c_cyan, pitch=0.4))
    parts.append(spike(0.035, 0.12, (-0.36, 1.47, bolt_z), c_white, pitch=np.pi / 2))

    # --- 7. Head & Helm (Colossus stoic face & crown)
    parts.append(box((0.14, 0.08, 0.14), (0.02, 1.56, 0.0), c_navy))  # neck
    parts.append(box((0.18, 0.18, 0.18), (0.05, 1.68, 0.0), c_sapphire))  # head base
    parts.append(box((0.10, 0.10, 0.14), (0.13, 1.64, 0.0), c_steel))  # stoic face plate
    # Glowing lightning eyes (piercing cyan)
    for side in (1.0, -1.0):
        parts.append(box((0.04, 0.03, 0.04), (0.145, 1.70, side * 0.05), c_cyan))
    parts.append(box((0.06, 0.04, 0.16), (0.14, 1.73, 0.0), c_gold))  # brow plate

    # Helm Crown / Crest
    parts.append(box((0.22, 0.05, 0.20), (0.05, 1.77, 0.0), c_gold))  # crown rim
    # Central dorsal crest fin
    parts.append(box((0.26, 0.10, 0.04), (0.04, 1.83, 0.0), c_gold))
    parts.append(box((0.22, 0.04, 0.02), (0.04, 1.89, 0.0), c_cyan))  # glowing fin edge
    # Side wing crests on helm
    for side in (1.0, -1.0):
        parts.append(box((0.14, 0.12, 0.03), (-0.02, 1.78, side * 0.11), c_gold, yaw=side * 0.3, pitch=0.2))

    mesh = trimesh.util.concatenate(parts)
    mesh.apply_translation([0.0, -mesh.bounds[0][1], 0.0])
    return mesh


def verify_titan(mesh: trimesh.Trimesh) -> None:
    """Assert enemy-model contracts and sanity bounds."""
    assert len(mesh.faces) > 0, "titan: empty mesh"
    assert len(mesh.faces) <= MAX_FACES, f"titan: {len(mesh.faces)} faces exceeds {MAX_FACES}"

    lo, hi = mesh.bounds
    assert abs(lo[1]) < 1e-6, f"titan: feet at y={lo[1]:.4f}, must be 0"
    assert 1.6 <= hi[1] <= 2.2, f"titan: height {hi[1]:.2f}m outside expected range [1.6, 2.2]"

    length = hi[0] - lo[0]
    assert 0.6 <= length <= 2.2, f"titan: length {length:.2f}m outside [0.6, 2.2]"
    assert hi[0] > 0.0, "titan: nothing forward of origin (+X facing required)"

    bias = hi[2] + lo[2]
    assert abs(bias) <= 0.05, f"titan: off-centre on z (bias {bias:.4f})"

    colors = mesh.visual.vertex_colors
    assert colors is not None and len(colors) == len(mesh.vertices), "titan: missing vertex colors"


def save_titan() -> trimesh.Trimesh:
    mesh = build_titan()
    verify_titan(mesh)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / "titan.glb"
    export_faceted(mesh, path)
    lo, hi = mesh.bounds
    print(f"✓ titan: {path}")
    print(f"  {len(mesh.vertices)} verts / {len(mesh.faces)} faces")
    print(f"  {hi[0] - lo[0]:.2f} m long, {hi[1]:.2f} m tall, {hi[2] - lo[2]:.2f} m wide")
    return mesh


if __name__ == "__main__":
    save_titan()
