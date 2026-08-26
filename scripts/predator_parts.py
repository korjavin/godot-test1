#!/usr/bin/env python3
"""
Shared faceted-box toolkit for the biome-predator model generators
(generate_wolf / cougar / bear / hound / snake).

Why this module exists at all: the five predators are the same animal with
different numbers. Copy-pasting a 200-line trimesh quadruped five times is how
the tail ends up drooping the wrong way in exactly one of them, so the shape
code lives here once and each generate_*.py is a short table of proportions and
colours. The older per-character generators (generate_crocodile_model.py,
generate_*_separate.py) predate this and are left alone.

THE THREE CONTRACTS A PREDATOR MODEL MUST HONOUR
------------------------------------------------
1. ORIENTATION: nose along +X, up is +Y, +Z is the animal's left. This is the
   crocodile's local orientation, and `piglet_crocodile_ai.gd` turns it into a
   facing with a single `MODEL_FACING_OFFSET` yaw applied to the whole `Model`
   node. Build to a different axis and every species would need its own offset.

2. FEET AT y = 0. The AI writes `model.position.y` (bob, and the river sink)
   against a rest height latched in `_ready()`, and the world's ground is a flat
   plane at y = 0. A model whose feet sit at y = 0.3 hovers; one at y = -0.3
   is buried, and no code compensates.

3. ONE STATIC MESH, VERTEX-COLOURED. There is no AnimationPlayer and no rig:
   `_animate_body` waddles/bobs/leans the entire `Model` node with sine waves.
   Limb child nodes (`LeftArm` and friends) are the PLAYER convention and are
   ignored here — an enemy is one welded mesh, exactly like the crocodile.
   Colour rides in the vertices because nothing loads textures for these.

Geometry is deliberately blocky: axis-aligned boxes plus the occasional 4-sided
cone, matching the faceted art direction and keeping each animal near ~350
triangles (the crocodile is 1856, so a whole pack is cheaper than it looks).

Run this file directly to build every species and check it:
    python3 scripts/predator_parts.py     # -> SELFCHECK OK
"""

import pathlib

import numpy as np
import trimesh

# Enemy GLBs live beside the crocodile's. Resolved from this file rather than the
# working directory so the self-check below runs from anywhere.
OUT_DIR = pathlib.Path(__file__).resolve().parent.parent / "assets" / "models" / "characters"

# --- Face budget. Not a perf cliff, a canary: blow past this and someone has
# started sculpting instead of stacking boxes. The crocodile is 1856.
MAX_FACES = 1200

# Plausible nose-to-tail envelope in metres. The crocodile is 1.40 long.
LENGTH_RANGE = (0.6, 2.2)


def rgba(hex_color: str, alpha: int = 255) -> np.ndarray:
    """'#2d5016' -> the float RGBA trimesh wants for vertex colours."""
    h = hex_color.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)] + [alpha]) / 255.0


def box(size, pos, color, pitch: float = 0.0, roll: float = 0.0) -> trimesh.Trimesh:
    """
    One faceted block: `size` is (length_x, height_y, width_z), `pos` its CENTRE.

    `pitch` rotates about Z (nose up / nose down) and `roll` about X (ear or leg
    splayed sideways); both are radians and both are applied before the
    translation, so `pos` stays the centre whatever the angles are.
    """
    m = trimesh.creation.box(extents=size)
    if pitch:
        m.apply_transform(trimesh.transformations.rotation_matrix(pitch, [0, 0, 1]))
    if roll:
        m.apply_transform(trimesh.transformations.rotation_matrix(roll, [1, 0, 0]))
    m.visual.vertex_colors = color
    m.apply_translation(pos)
    return m


def spike(base: float, height: float, pos, color, roll: float = 0.0) -> trimesh.Trimesh:
    """
    An upward 4-sided pyramid — the cheapest pointy thing there is (4 faces).
    Used for pricked ears and dorsal ridges. `pos` is the base centre.
    """
    m = trimesh.creation.cone(radius=base, height=height, sections=4)
    # trimesh builds cones along +Z. Everything here is built +Y up, so stand it
    # upright first — otherwise an "ear" points out of the side of the head, and
    # the only symptom is a model that is quietly 0.05 m off-centre.
    m.apply_transform(trimesh.transformations.rotation_matrix(-np.pi / 2, [1, 0, 0]))
    if roll:
        m.apply_transform(trimesh.transformations.rotation_matrix(roll, [1, 0, 0]))
    m.visual.vertex_colors = color
    m.apply_translation(pos)
    return m


def tapered_chain(start, seg_len, count, thick_from, thick_to, color,
                  dx=1.0, dy=0.0, dz=0.0, taper_pow: float = 1.0):
    """
    A run of shrinking blocks marching from `start` along the (dx, dy, dz) step.

    Every predator's tail is this, and so is the whole snake. `thick_from` /
    `thick_to` are the square cross-section at the first and last segment, eased
    by `taper_pow` (>1 keeps it thick then drops away — a bushy wolf brush;
    1.0 is a straight taper — a cat's whip).
    """
    parts = []
    for i in range(count):
        t = (i / max(count - 1, 1)) ** taper_pow
        thick = thick_from + (thick_to - thick_from) * t
        parts.append(box(
            (seg_len, thick, thick),
            (start[0] + dx * seg_len * i,
             start[1] + dy * seg_len * i,
             start[2] + dz * seg_len * i),
            color,
        ))
    return parts


def quadruped(
    *,
    body_len: float, body_h: float, body_w: float,
    leg_len: float, leg_w: float,
    head_len: float, head_h: float, head_w: float,
    snout_len: float,
    neck_drop: float,
    tail_len: float, tail_w: float, tail_droop: float,
    tail_bushy: float = 1.0,
    ears: str = "point", ear_size: float = 0.09,
    haunch: float = 0.0,
    body: str = "#7a6a5a", belly: str = "#b8a894",
    dark: str = "#241d18", eye: str = "#d8b43c",
):
    """
    Build wolf / cougar / bear / hound from proportions and return the part list.

    Everything is measured from the ground up, so `leg_len` alone decides how
    tall the animal stands and the caller never computes a y offset. The head
    sits `neck_drop` below the shoulder line — cats carry it level (0), bears
    slung low (positive), which is most of what separates their silhouettes.

    `haunch` adds a raised block over the hind legs: a bear's shoulder hump and
    a cat's rear drive, both from the same knob. Returned as a plain list so a
    caller can append its own species flourish before saving.
    """
    c_body, c_belly, c_dark, c_eye = rgba(body), rgba(belly), rgba(dark), rgba(eye)
    parts = []

    back_y = leg_len + body_h  # top of the torso, i.e. the shoulder line

    # --- Torso, with a lighter belly slab hung under it.
    parts.append(box((body_len, body_h, body_w), (0.0, leg_len + body_h / 2, 0.0), c_body))
    parts.append(box((body_len * 0.86, body_h * 0.3, body_w * 0.86),
                     (0.0, leg_len + body_h * 0.14, 0.0), c_belly))

    # --- Haunch / hump over the hind legs.
    if haunch > 0.0:
        parts.append(box((body_len * 0.34, haunch, body_w * 0.9),
                         (-body_len * 0.26, back_y + haunch / 2 - 0.01, 0.0), c_body))

    # --- Neck: one block bridging the chest to the back of the head. Pitched so
    # it actually meets the head when the head is carried low.
    head_x = body_len / 2 + head_len / 2 + 0.02
    head_y = back_y - neck_drop - head_h / 2
    neck_x = body_len / 2 - 0.02
    parts.append(box((head_len * 1.3, head_h * 0.85, head_w * 0.9),
                     ((neck_x + head_x) / 2, (back_y - head_h * 0.3 + head_y) / 2, 0.0),
                     c_body,
                     pitch=np.arctan2(head_y - back_y + head_h * 0.3, head_x - neck_x)))

    # --- Head, muzzle, nose.
    parts.append(box((head_len, head_h, head_w), (head_x, head_y, 0.0), c_body))
    snout_h = head_h * 0.55
    snout_x = head_x + head_len / 2 + snout_len / 2
    snout_y = head_y - head_h * 0.18
    parts.append(box((snout_len, snout_h, head_w * 0.66), (snout_x, snout_y, 0.0), c_body))
    parts.append(box((snout_len * 0.22, snout_h * 0.5, head_w * 0.4),
                     (snout_x + snout_len / 2, snout_y + snout_h * 0.2, 0.0), c_dark))

    # --- Eyes: a bright block with a dark pupil poking out in front of it, one
    # per side. They straddle the side of the skull (z = half the head width)
    # rather than sitting inside it — an eye tucked in by even a centimetre is
    # swallowed whole by the head block and the face renders blank.
    for side in (1.0, -1.0):
        ez = side * head_w * 0.5
        parts.append(box((head_len * 0.2, head_h * 0.2, head_w * 0.14),
                         (head_x + head_len * 0.28, head_y + head_h * 0.2, ez), c_eye))
        parts.append(box((head_len * 0.1, head_h * 0.1, head_w * 0.1),
                         (head_x + head_len * 0.37, head_y + head_h * 0.2, ez), c_dark))

    # --- Ears. Three silhouettes off one switch, because the ear is the fastest
    # read on a small blocky animal: pricked = wild, round = bear, flop = dog.
    ear_x = head_x - head_len * 0.22
    for side in (1.0, -1.0):
        ez = side * head_w * 0.34
        if ears == "point":
            parts.append(spike(ear_size * 0.6, ear_size * 1.6,
                               (ear_x, head_y + head_h / 2, ez), c_body))
        elif ears == "round":
            parts.append(box((ear_size * 0.5, ear_size, ear_size),
                             (ear_x, head_y + head_h / 2 + ear_size * 0.35,
                              ez + side * ear_size * 0.2), c_body))
        elif ears == "flop":
            parts.append(box((ear_size * 0.8, ear_size * 2.0, ear_size * 0.4),
                             (ear_x, head_y - ear_size * 0.4, ez + side * head_w * 0.16),
                             c_dark, roll=side * 0.25))
        else:
            raise ValueError(f"unknown ear style: {ears!r}")

    # --- Legs, each capped with a darker paw so the feet read against the ground.
    paw_h = leg_len * 0.16
    for x in (body_len * 0.32, -body_len * 0.32):
        for z in (body_w / 2 - leg_w / 2, -(body_w / 2 - leg_w / 2)):
            parts.append(box((leg_w, leg_len, leg_w), (x, leg_len / 2, z), c_body))
            parts.append(box((leg_w * 1.25, paw_h, leg_w * 1.1), (x + leg_w * 0.1, paw_h / 2, z), c_dark))

    # --- Tail: chained blocks sloping back and down from the rump.
    segs = 5
    seg_len = tail_len / segs
    parts += tapered_chain(
        (-body_len / 2 - seg_len / 2, leg_len + body_h * 0.75, 0.0),
        seg_len, segs, tail_w, tail_w * 0.35, c_body,
        dx=-1.0, dy=-tail_droop, taper_pow=tail_bushy,
    )
    return parts


def build(parts, scale: float = 1.0) -> trimesh.Trimesh:
    """Weld the parts into the single mesh Godot instances, feet planted at y = 0."""
    mesh = trimesh.util.concatenate(parts)
    if scale != 1.0:
        mesh.apply_scale(scale)
    mesh.apply_translation([0.0, -mesh.bounds[0][1], 0.0])
    return mesh


def verify(mesh: trimesh.Trimesh, name: str, symmetric: bool = True) -> None:
    """
    Assert the three contracts in the module docstring, on every generation.

    This is the whole test for these scripts: a proportion typo that buries the
    animal, points it backwards or leaves it colourless fails here instead of
    being discovered as a hovering white blob in the game.
    """
    assert len(mesh.faces) > 0, f"{name}: empty mesh"
    assert len(mesh.faces) <= MAX_FACES, f"{name}: {len(mesh.faces)} faces exceeds {MAX_FACES}"

    lo, hi = mesh.bounds
    assert abs(lo[1]) < 1e-6, f"{name}: feet at y={lo[1]:.4f}, must be 0"
    assert hi[1] > 0.1, f"{name}: {hi[1]:.3f} m tall — flat on the ground?"

    length = hi[0] - lo[0]
    assert LENGTH_RANGE[0] <= length <= LENGTH_RANGE[1], \
        f"{name}: {length:.2f} m long, outside {LENGTH_RANGE}"
    # Nose along +X: the head has to be the front-most thing, and the body has to
    # be longer than it is wide or the facing yaw reads as a sideways animal.
    assert hi[0] > 0.0, f"{name}: nothing forward of the origin — is it facing -X?"
    assert length > hi[2] - lo[2], f"{name}: wider than it is long"
    # Centred on the spine, so the waddle roll doesn't read as a limp. A snake is
    # posed in an S and is genuinely lopsided, so it only has to be roughly
    # centred (`symmetric=False`) rather than mirror-exact.
    bias = hi[2] + lo[2]
    limit = 1e-6 if symmetric else (hi[2] - lo[2]) * 0.2
    assert abs(bias) <= limit, f"{name}: off-centre on z (bias {bias:.4f}, limit {limit:.4f})"

    colors = mesh.visual.vertex_colors
    assert colors is not None and len(colors) == len(mesh.vertices), \
        f"{name}: vertex colours missing — Godot would render it untinted white"


def save(parts, name: str, scale: float = 1.0, symmetric: bool = True) -> trimesh.Trimesh:
    """Weld, check, export, report. The tail end of every generate_*.py main()."""
    mesh = build(parts, scale)
    verify(mesh, name, symmetric)
    path = OUT_DIR / f"{name}.glb"
    mesh.export(path)
    lo, hi = mesh.bounds
    print(f"✓ {name}: {path}")
    print(f"  {len(mesh.vertices)} verts / {len(mesh.faces)} faces")
    print(f"  {hi[0] - lo[0]:.2f} m long, {hi[1]:.2f} m tall, {hi[2] - lo[2]:.2f} m wide")
    return mesh


if __name__ == "__main__":
    # Running the toolkit runs every generator that uses it, so `verify` fires on
    # all five species. Same shape as the project's GDScript self-checks.
    import runpy

    here = pathlib.Path(__file__).resolve().parent
    for species in ("wolf", "cougar", "bear", "hound", "snake"):
        runpy.run_path(str(here / f"generate_{species}.py"), run_name="__main__")
    print("SELFCHECK OK")
