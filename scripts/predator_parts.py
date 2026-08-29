#!/usr/bin/env python3
"""
Shared faceted-box toolkit for the biome-predator model generators
(generate_wolf / cougar / bear / hound / snake / hunter / naga / hydra).

Why this module exists at all: the five animal predators are the same animal with
different numbers. Copy-pasting a 200-line trimesh quadruped five times is how
the tail ends up drooping the wrong way in exactly one of them, so the shape
code lives here once and each generate_*.py is a short table of proportions and
colours. The hunter robot is the one customer that skips `quadruped()` and stacks
its own boxes — it still owes the three contracts below, it just isn't an animal.
The older per-character generators (generate_crocodile_model.py,
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


def wings(shoulder, span: float, color, *, segments: int = 3, fold: float = 0.0,
          chord: float = 0.0, thickness: float = 0.0, taper: float = 0.55,
          edge=None):
    """
    A mirrored pair of stylized wings, returned as parts like every other helper.

    There is no wing anywhere else in the toolkit — the animals are quadrupeds and
    the hunter is a machine — so this is the one place the shape is decided, and
    both winged bosses spend it rather than growing their own geometry.

    `shoulder` is the ROOT CENTRE of the LEFT wing, (x, y, z) with z the positive
    half-width of the attachment; the right wing is its exact mirror. `span` is
    the reach of ONE wing from that root to the tip, `chord` its fore-aft depth at
    the root (0 = derive from the span), and `taper` the fraction of both lost by
    the tip — the same "shrinking blocks" language as `tapered_chain`, only the
    cross-section is a flat plate instead of a square.

    `fold` is the whole personality, in radians: 0 lays the wing back along the
    flank as a vertical fin (folded at rest — which is how these bosses spend
    almost all of their time, since they hop and never fly), pi/2 holds it
    straight out sideways as a horizontal plane, and anything between is
    part-spread. The membrane rolls with it: the chord stands UP when tucked and
    lies FLAT when spread, which is what a folding wing actually does and what
    keeps the tucked pose from reading as a shelf bolted to the ribs.

    `edge` is an optional second colour for a spar down the leading edge — the
    bone in a membrane, the wrist line in a feathered wing. It is the same
    two-tone trick as the dark paw and the dorsal diamond, and without it a wing
    this size reads as a painted plank.

    Nothing here implies a movement mode: the wings are silhouette, and the models
    that wear them hop.
    """
    if segments < 1:
        raise ValueError(f"wings: segments must be >= 1, got {segments}")
    if not 0.0 <= taper < 1.0:
        # 1.0 looks like the natural "taper it all away" value and is in fact a
        # tip segment with zero extents in both directions: degenerate faces that
        # weld into the mesh, survive `verify`, and cost the wing its last
        # segment wherever the importer drops them.
        raise ValueError(f"wings: taper must be in [0, 1), got {taper}")
    sx, sy, sz = shoulder
    chord = chord or span * 0.5
    thickness = thickness or span * 0.07
    step = span / segments

    # The plate is built in a local frame — span along +Z, chord along X, thin in
    # Y — and then swung into place by one yaw per side. Building local means the
    # leading-edge spar is a plain offset instead of trigonometry at every
    # segment, and it keeps `box()` untouched (it has no yaw, and does not need
    # one: only a wing sweeps in the XZ plane).
    #
    # `pitch` rolls the plate about its own span axis: pi/2 when folded (chord
    # vertical), 0 when spread (chord fore-aft). Both sides take the SAME pitch —
    # a rotation about Z survives the z-mirror unchanged — which is half of why
    # the pair comes out mirror-exact rather than mirror-ish.
    pitch = np.pi / 2 - fold

    parts = []
    for side in (1.0, -1.0):
        swing = trimesh.transformations.rotation_matrix(side * (fold - np.pi / 2), [0, 1, 0])
        swing[:3, 3] = (sx, sy, side * sz)   # rotate about the origin, then sit on the shoulder
        for i in range(segments):
            t = (i / max(segments - 1, 1))
            shrink = 1.0 - taper * t
            c, th = chord * shrink, thickness * shrink
            z = side * step * (i + 0.5)
            # Overlong by 12% so the joints never open a gap, exactly as the
            # snake's body blocks overlap around its S-curve.
            plate = box((c, th, step * 1.12), (0.0, 0.0, z), color, pitch=pitch)
            plate.apply_transform(swing)
            parts.append(plate)
            if edge is not None:
                # The spar rides the front of the chord, so it has to be pitched
                # around with it — hence the cos/sin on the offset rather than a
                # flat +X.
                lead = box((c * 0.2, th * 1.7, step * 1.12),
                           (np.cos(pitch) * c * 0.42, np.sin(pitch) * c * 0.42, z),
                           edge, pitch=pitch)
                lead.apply_transform(swing)
                parts.append(lead)

    # Contract 2 is the caller's to keep, but a wing is the one part that can
    # break it without anyone noticing: a tucked wing hangs half a chord below its
    # root, so a shoulder set too low quietly buries the tip and `build()` then
    # lifts the whole animal off the ground to compensate.
    low = min(p.bounds[0][1] for p in parts)
    if low < -1e-9:
        raise ValueError(
            f"wings: dips to y={low:.4f}; raise the shoulder or shorten the chord")
    return parts


def necks(root, count: int, length: float, color, *, segments: int = 3,
          spread: float = 0.5, rise: float = 0.9, thick: float = 0.13,
          taper: float = 0.4, head: float = 1.6, eye=None):
    """
    A fan of necks, each ending in a head, all branching from ONE point.

    The toolkit's animals have exactly one head on exactly one neck, welded in by
    `quadruped`. A hydra does not, and "many necks off one body" is the shape that
    cannot be faked by stacking boxes at the call site without re-deriving the
    same arc trigonometry per neck and getting the mirror wrong on one of them —
    so, like `wings`, it is decided once here and spent by the models.

    `root` is the BRANCH POINT: the spot on the spine every neck leaves from,
    (x, y, z) with z = 0, because a fan hinged off the spine is the only one that
    can come out mirror-exact. `count` necks are spaced evenly across the fan, the
    outermost pair at +-`spread` radians of yaw; an odd count puts one neck dead
    ahead on the spine (it is its own mirror), an even count leaves the middle
    empty. `length` is the run from the branch point to the jaw of ONE neck.

    `rise` is the pitch at the base, in radians, eased down to a quarter of it by
    the last segment: the neck leaves the body steeply and levels off looking
    forward, which is the S a serpent's neck actually makes and what stops the
    heads reading as antennae. `thick` is the cross-section at the root and
    `taper` the fraction of it lost by the jaw — the same shrinking-blocks
    language as `tapered_chain`.

    `head` sizes the head block as a multiple of the neck's tip thickness, and
    `eye` is an optional second colour: without it a head at this scale is a
    slightly fatter neck segment, with it the fan reads as faces.

    Nothing here animates. There is no rig and no per-head motion — the whole
    `Model` node sways as one, which is exactly why the heads have to be far
    enough apart to read as several from a standing start.
    """
    if count < 1:
        raise ValueError(f"necks: count must be >= 1, got {count}")
    if segments < 1:
        raise ValueError(f"necks: segments must be >= 1, got {segments}")
    if not 0.0 <= taper < 1.0:
        # 1.0 tapers the jaw away to zero extents: degenerate faces that weld in,
        # survive `verify` and vanish in whichever importer prunes them. Same
        # trap, same guard, as `wings`.
        raise ValueError(f"necks: taper must be in [0, 1), got {taper}")
    if count > 1 and spread <= 0.0:
        # THE DEGENERATE BRANCH POINT. Every neck at the same yaw is `count`
        # copies of one neck occupying one space: it welds, it verifies, it has
        # the face count of a hydra and the silhouette of a snake. The whole
        # capability is that the heads are APART, so a fan of zero width is an
        # error and not a pose.
        raise ValueError(f"necks: {count} necks need spread > 0, got {spread}")
    if abs(root[2]) > 1e-9:
        # Off the spine the fan is still a fan, but it is no longer mirrored, and
        # `verify(symmetric=True)` would then fail on the finished animal with a
        # z-bias whose source is three functions away.
        raise ValueError(f"necks: root must sit on the spine (z=0), got z={root[2]}")

    rx, ry, _ = root
    step = length / segments
    tip_thick = thick * (1.0 - taper)
    head_len, head_h, head_w = tip_thick * head * 1.15, tip_thick * head * 0.8, tip_thick * head

    parts = []
    for i in range(count):
        # Yaw measured from the CENTRE of the fan, so the i-th neck and its
        # opposite number get exactly-negated angles: (i - half) / half is an
        # exact negation pair in binary, while i / (count - 1) * 2 - 1 is not for
        # count = 4 and the mirror check then fails by one ulp per vertex.
        half = (count - 1) / 2.0
        yaw = spread * ((i - half) / half) if count > 1 else 0.0
        swing = trimesh.transformations.rotation_matrix(yaw, [0, 1, 0])
        swing[:3, 3] = (rx, ry, 0.0)   # rotate about the branch point, then sit on it

        local = []
        x = y = 0.0
        pitch = rise
        for s in range(segments):
            t = s / max(segments - 1, 1)
            pitch = rise * (1.0 - 0.75 * t)
            th = thick * (1.0 - taper * t)
            dx, dy = np.cos(pitch) * step, np.sin(pitch) * step
            # Overlong by 15% so the elbows of the arc never open a gap, the same
            # trick the snake's body blocks and the wing's plates use.
            local.append(box((step * 1.15, th, th), (x + dx / 2, y + dy / 2, 0.0),
                             color, pitch=pitch))
            x, y = x + dx, y + dy

        # Head, carried at the last segment's pitch so the jaw points where the
        # neck was going, plus a blunt snout in front of it.
        hx, hy = x + np.cos(pitch) * head_len / 2, y + np.sin(pitch) * head_len / 2
        local.append(box((head_len, head_h, head_w), (hx, hy, 0.0), color, pitch=pitch))
        sx = hx + np.cos(pitch) * head_len * 0.6
        sy = hy + np.sin(pitch) * head_len * 0.6
        local.append(box((head_len * 0.45, head_h * 0.5, head_w * 0.55),
                         (sx, sy, 0.0), color, pitch=pitch))
        if eye is not None:
            for side in (1.0, -1.0):
                # Straddling the side of the skull, never inside it — an eye tucked
                # in by a centimetre is swallowed by the head block (see quadruped).
                local.append(box((head_len * 0.3, head_h * 0.3, head_w * 0.16),
                                 (hx + np.cos(pitch) * head_len * 0.2,
                                  hy + np.sin(pitch) * head_len * 0.2 + head_h * 0.25,
                                  side * head_w * 0.5), eye, pitch=pitch))

        for p in local:
            p.apply_transform(swing)
        parts += local

    # Contract 2 again: `rise` is a free parameter and a negative one aims the
    # whole fan at the floor, where `build()` would then lift the animal off the
    # ground to compensate rather than fail.
    low = min(p.bounds[0][1] for p in parts)
    if low < -1e-9:
        raise ValueError(f"necks: dips to y={low:.4f}; raise the root or the rise")
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


def _selfcheck_wings() -> None:
    """
    Exercise the wing primitive on the poses a consumer will actually ask for.

    There is no generate_wing.py to run — a wing is half a model, so `verify` (a
    whole animal, nose to tail) cannot judge one. This is its stand-in, and it
    asserts the three things a wing can silently get wrong: it drops below the
    ground, the two sides drift apart, or `fold` stops meaning what it says.
    """
    membrane, bone = rgba("#6a5a3a"), rgba("#241d18")
    # label, shoulder, span, segments, fold, spar — the first two share a shoulder
    # and a span on purpose, so the folded/spread pair can be compared directly.
    cases = [
        ("folded",      (0.10, 0.70, 0.16), 0.55, 3, 0.0,       True),
        ("part-spread", (0.10, 0.70, 0.16), 0.55, 3, 0.9,       True),
        ("spread",      (0.00, 1.20, 0.22), 1.40, 5, np.pi / 2, False),
        ("stub",        (0.00, 0.40, 0.10), 0.25, 1, 0.45,      True),
    ]
    extent = {}
    for label, shoulder, span, segs, fold, spar in cases:
        parts = wings(shoulder, span, membrane, segments=segs, fold=fold,
                      edge=bone if spar else None)
        assert len(parts) == segs * 2 * (2 if spar else 1), f"wings/{label}: part count"

        # Contract 3: the parts weld into ONE vertex-coloured mesh, no wing nodes.
        mesh = trimesh.util.concatenate(parts)
        assert len(mesh.faces) == len(parts) * 12, f"wings/{label}: not plain boxes"
        assert len(mesh.visual.vertex_colors) == len(mesh.vertices), \
            f"wings/{label}: vertex colours lost in the weld"

        lo, hi = mesh.bounds
        # Contract 2: nothing below the ground plane, at any fold.
        assert lo[1] >= -1e-9, f"wings/{label}: dips to y={lo[1]:.4f}"

        # Mirror-exact, not merely balanced: the vertex set must be invariant
        # under a z-flip. A bounds check alone would pass a wing whose right side
        # is a different shape of the same width.
        v = mesh.vertices
        flipped = v * (1.0, 1.0, -1.0)
        left = v[np.lexsort(v.T[::-1])]
        right = flipped[np.lexsort(flipped.T[::-1])]
        assert np.allclose(left, right, atol=1e-12), f"wings/{label}: sides not mirrored"

        # Sane bounds: no vertex reaches further from its own shoulder than the
        # last segment plus its chord can possibly put it.
        sx, sy, sz = shoulder
        roots = np.array([[sx, sy, sz], [sx, sy, -sz]])
        reach = np.linalg.norm(v[:, None, :] - roots[None, :, :], axis=2).min(axis=1)
        assert reach.max() <= span + span * 0.5, f"wings/{label}: reaches {reach.max():.3f} m"
        # ...and the span lands where `fold` says it should, within a chord.
        assert abs((hi[2] - sz) - span * np.sin(fold)) <= span * 0.2, \
            f"wings/{label}: z reach {hi[2] - sz:.3f} m disagrees with fold {fold:.2f}"
        extent[label] = (hi[2] - lo[2], hi[0] - lo[0])

    # What `fold` MEANS, stated as a comparison rather than as numbers: opening a
    # wing trades length along the flank for width off the shoulder.
    assert extent["folded"][0] < extent["part-spread"][0], "fold does not widen the pair"
    assert extent["folded"][1] > extent["part-spread"][1], "fold does not shorten the sweep"

    # Guards, both of which are cheaper to hit here than in a boss model.
    for shoulder, kw, why in (
        ((0.0, 0.05, 0.10), dict(segments=3), "a buried tip"),
        ((0.0, 1.00, 0.10), dict(segments=0), "no segments"),
        ((0.0, 1.00, 0.10), dict(taper=1.0), "a tip tapered away to nothing"),
    ):
        try:
            wings(shoulder, 0.6, membrane, fold=0.0, **kw)
        except ValueError:
            continue
        raise AssertionError(f"wings: {why} was accepted")

    print(f"\u2713 wings: {len(cases)} poses, mirror-exact, clear of the ground")


def _selfcheck_necks() -> None:
    """
    Exercise the multi-head branch point on the fans a consumer will ask for.

    A fan of necks is half a model, so `verify` (a whole animal, nose to tail)
    cannot judge one — same reason `wings` has a stand-in here. The four things a
    branch point can silently get wrong are all asserted below: the heads end up
    in the SAME PLACE (the capability quietly not happening), the necks stop
    meeting at the root (a fan of floating snakes), the two sides drift apart, or
    the whole thing sinks through the floor.
    """
    scale, eye = rgba("#080409"), rgba("#7a8a1a")

    def head_centres(parts, count, per, segs):
        """Centroid of each neck's HEAD block — the part right after its segments."""
        return np.array([parts[i * per + segs].centroid for i in range(count)])

    # label, count, segments, spread, length, eyes — "three" and "wide" share
    # everything but the spread on purpose, so the fan's meaning can be compared.
    cases = [
        ("three", 3, 3, 0.45, 0.55, True),
        ("wide",  3, 3, 0.95, 0.55, True),
        ("pair",  2, 4, 0.40, 0.60, False),
        # count = 4 earns its place: it is the smallest fan whose yaw offsets are
        # NOT exact negations under the obvious `i / (count - 1) * 2 - 1`, so it
        # is the only case in this list that fails the mirror check if the angle
        # is ever computed that way instead of from the fan's centre.
        ("four",  4, 3, 0.55, 0.50, False),
        ("one",   1, 2, 0.00, 0.40, True),
        ("many",  5, 3, 1.00, 0.50, True),
    ]
    root = (0.25, 0.35, 0.0)
    shape = {}
    for label, count, segs, spread, length, eyes in cases:
        parts = necks(root, count, length, scale, segments=segs, spread=spread,
                      eye=eye if eyes else None)
        per = segs + 2 + (2 if eyes else 0)
        assert len(parts) == count * per, f"necks/{label}: part count"

        # Contract 3: the parts weld into ONE vertex-coloured mesh, no head nodes.
        mesh = trimesh.util.concatenate(parts)
        assert len(mesh.faces) == len(parts) * 12, f"necks/{label}: not plain boxes"
        assert len(mesh.visual.vertex_colors) == len(mesh.vertices), \
            f"necks/{label}: vertex colours lost in the weld"

        v = mesh.vertices
        lo, hi = mesh.bounds
        # Contract 2: nothing below the ground plane, at any fan.
        assert lo[1] >= -1e-9, f"necks/{label}: dips to y={lo[1]:.4f}"

        # Mirror-exact, not merely balanced: the vertex set is invariant under a
        # z-flip. A bounds check alone passes a fan whose right half is a
        # different shape of the same width.
        flipped = v * (1.0, 1.0, -1.0)
        left = v[np.lexsort(v.T[::-1])]
        right = flipped[np.lexsort(flipped.T[::-1])]
        assert np.allclose(left, right, atol=1e-12), f"necks/{label}: sides not mirrored"

        # THEY ALL LEAVE THE SAME POINT. Every neck's nearest vertex to the root
        # is within its own cross-section of it, which is what makes this a branch
        # and not `count` animals standing in a row.
        r = np.array(root)
        for i in range(count):
            group = trimesh.util.concatenate(parts[i * per:(i + 1) * per])
            near = np.linalg.norm(group.vertices - r, axis=1).min()
            assert near <= 0.13, f"necks/{label}: neck {i} starts {near:.3f} m off the root"

        # AND THEY END UP APART. A degenerate branch point welds, verifies, and
        # has the face count of a hydra with the silhouette of a snake, so the
        # heads are measured against each other rather than assumed.
        heads = head_centres(parts, count, per, segs)
        if count > 1:
            gaps = np.linalg.norm(heads[:, None, :] - heads[None, :, :], axis=2)
            gaps += np.eye(count) * 1e9
            assert gaps.min() >= length * 0.15, \
                f"necks/{label}: closest heads {gaps.min():.3f} m apart on a {length} m neck"
            # ...and apart ACROSS the spine, not merely at different heights: the
            # fan is a yaw, so the read at distance is the z spread.
            assert np.ptp(heads[:, 2]) >= length * 0.3, \
                f"necks/{label}: heads span only {np.ptp(heads[:, 2]):.3f} m of z"

        # NO GAPS AT THE ELBOWS. Each block spans at least its own stride, which
        # is what the deliberate overlength is for: the arc turns between
        # segments, so a block merely as long as the step opens a wedge on the
        # outside of every bend and the neck reads as a string of beads.
        stride = length / segs
        for i in range(count):
            for s_i in range(segs):
                span = parts[i * per + s_i].extents.max()
                assert span >= stride, \
                    f"necks/{label}: segment {s_i} spans {span:.4f} of a {stride:.4f} stride"

        # A HEAD IS A BLOCK, not a wafer. Every head is measured against the
        # jaw-end segment it sits on: the thinnest thing about the head may not
        # be thinner than the thinnest thing about the neck. Measured on extents
        # rather than eyeballed proportions, because a collapsed dimension is
        # exactly what a proportion typo produces — one that welds, mirrors and
        # verifies perfectly, and ships a fan of headless stalks.
        for i in range(count):
            head_ext = parts[i * per + segs].extents.min()
            jaw_ext = parts[i * per + segs - 1].extents.min()
            assert head_ext >= jaw_ext, \
                f"necks/{label}: head {i} is {head_ext:.4f} thin on a {jaw_ext:.4f} neck"

        # Nothing reaches further than the neck plus its head can put it.
        reach = np.linalg.norm(v - r, axis=1).max()
        assert reach <= length * 1.6, f"necks/{label}: reaches {reach:.3f} m on {length}"
        # Width across the fan, and how far FORWARD the average head ended up.
        # The forward number has to be the mean and not the bound: an odd count
        # keeps one neck dead ahead at every spread, so the mesh's own max x
        # never moves and would compare equal however wide the fan opened.
        shape[label] = (hi[2] - lo[2], heads[:, 0].mean() - r[0])

    # What `spread` MEANS, as a comparison rather than as numbers: opening the fan
    # trades forward reach for width, exactly as `fold` does for a wing.
    assert shape["wide"][0] > shape["three"][0], "spread does not widen the fan"
    assert shape["wide"][1] < shape["three"][1], "spread does not shorten the reach"
    # A single neck is a plain neck: no fan, no width beyond its own head.
    assert shape["one"][0] < 0.2, "a lone neck should be no wider than its head"

    # Guards. Each is cheaper to hit here than in a boss model.
    for args, kw, why in (
        ((root, 0, 0.5), {}, "no necks"),
        ((root, 3, 0.5), dict(segments=0), "no segments"),
        ((root, 3, 0.5), dict(taper=1.0), "a jaw tapered away to nothing"),
        ((root, 3, 0.5), dict(spread=0.0), "a degenerate branch point"),
        ((root, 3, 0.5), dict(spread=-0.4), "a fan folded inside out"),
        (((0.2, 0.3, 0.05), 3, 0.5), {}, "a root off the spine"),
        (((0.2, 0.1, 0.0), 3, 0.9), dict(rise=-0.8), "a fan aimed at the floor"),
    ):
        try:
            necks(*args, scale, **kw)
        except ValueError:
            continue
        raise AssertionError(f"necks: {why} was accepted")

    print(f"✓ necks: {len(cases)} fans, mirror-exact, branching and apart")


if __name__ == "__main__":
    # Running the toolkit runs every generator that uses it, so `verify` fires on
    # every species. Same shape as the project's GDScript self-checks.
    import runpy

    here = pathlib.Path(__file__).resolve().parent
    for species in ("wolf", "cougar", "bear", "hound", "snake", "hunter",
                    "naga", "hydra"):
        runpy.run_path(str(here / f"generate_{species}.py"), run_name="__main__")
    # The wing primitive has no generator of its own — no model wears it yet — so
    # it is checked here directly, on the poses its consumers will ask for.
    _selfcheck_wings()
    # The neck fan HAS a consumer (the hydra, above), but `verify` only ever sees
    # the finished animal — one welded mesh in which the branch point is no longer
    # a separable thing. So it is checked here too, on its own.
    _selfcheck_necks()
    print("SELFCHECK OK")
