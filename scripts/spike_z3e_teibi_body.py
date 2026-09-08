"""
Spike godot-test1-z3e.10 — Teibi's WHOLE BODY from the MPFB2/MakeHuman basemesh,
built the way scripts/spike_z3e_head.py built the Windman head (bead z3e.2), one
body along. NOT part of the build, NOT run by CI: run by hand to produce the
spike's evidence, which the owner rules from (bd show godot-test1-z3e.10).

Builds TWO variants:
  parts  the body cut at the joints into the SAME ten pieces
         scripts/generate_teibi_separate.py already ships (Head, Torso, Left/
         RightArm UpperArm + LowerArm/Mesh, Left/RightLeg UpperLeg + LowerLeg/
         Mesh) — same node names, so the sine rig, remote avatars and the
         resize ability need ZERO code change.
  uncut  the same body as ONE mesh, no cuts, no rig — the picture of what a
         SKINNED hero (bead z3e.6) looks like at rest.

Run:  blender --background --python-exit-code 1 --python scripts/spike_z3e_teibi_body.py
      (bind it: perl -e 'alarm 900; exec @ARGV' blender ... -- there is no
      `timeout` binary here)

THE ONE NEW TRAP THIS BEAD PAYS FOR (on top of the four in bd show godot-test1-z3e's
NOTES — MPFB2 enable, default_set=True, no --factory-startup, godot --import after
every rebuild): scripts/blender_hero.py's weights.game_engine.json indices are
BASEMESH indices, and bake_to_plain_mesh()'s convert() applies the helper MASK
modifier, which RENUMBERS vertices. So every vertex group this script writes off
that JSON is written on the RAW human object BEFORE convert() — groups survive
the mask and the decimate that follows, indices don't need to.

THE PIVOT MATH (bead's "Pivot in Godot = (x, z, -y) of the part-frame pivot"):
this script's internal frame is trimesh's / spike_z3e_head.py's — Z-up, +Y =
face-forward, matching generate_teibi_separate.py's own convention exactly, so
the .tscn's fixed per-part basis Rx(-90) = (1,0,0, 0,0,1, 0,-1,0) turns an
internal-frame vector (x,y,z) into Godot's (x, z, -y) without this script
touching the .tscn at all — it only PRINTS the joint positions in that frame;
scenes/characters/teibi_authored.tscn's origins are hand-edited from the log
(bead's own instruction: "the node ORIGINS ... replaced by MakeHuman's joints
as printed by the script").
"""

import json
import math
import os
import sys

import addon_utils
import bmesh
import bpy
import importlib
from mathutils import Matrix, Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO, "assets", "models", "characters", "teibi_parts")
WEIGHTS_PATH = os.path.expanduser(
    "~/Library/Application Support/Blender/5.2/extensions/blender_org/mpfb/"
    "data/rigs/standard/weights.game_engine.json")

# scripts/generate_teibi_separate.py's self.colors, verbatim (owner ruling:
# vertex colours, zero texture bytes — no baked albedo here).
COLORS = {
    "skin":          (0.86, 0.66, 0.54, 1.0),
    "hair":          (0.17, 0.12, 0.09, 1.0),
    "beret_navy":    (0.07, 0.09, 0.19, 1.0),
    "shirt_mustard": (0.87, 0.66, 0.17, 1.0),
    "shirt_collar":  (0.74, 0.55, 0.12, 1.0),
    "trousers":      (0.20, 0.22, 0.28, 1.0),
    "belt":          (0.11, 0.10, 0.11, 1.0),
    "belt_buckle":   (0.55, 0.50, 0.30, 1.0),
    "shoes":         (0.16, 0.11, 0.08, 1.0),
    # Not in the generator's palette (it has no face detail beyond the head
    # sphere's colour regions) — reuses spike_z3e_head.py's LIPS, and hair for
    # the eyebrows.
    "lips":          (0.80, 0.55, 0.48, 1.0),
    "eye_white":     (0.92, 0.92, 0.90, 1.0),
    "eye_iris":      (0.22, 0.16, 0.11, 1.0),
}

STUMP_WEIGHT = 0.25          # bead's "~0.25" — the blend zone at every joint
# MEASURED 2026-09-08: a naive 12k (the bead's own headline number) landed the
# PARTS total at 14,717 tris -- the ten pieces' STUMP overlap plus every cut's
# holes_fill cap cost ~2.7k over the single merged mesh, and the beret+eyes
# (built at their first-draft resolution) cost another 1.7k. Tightened here
# rather than there: this constant is the knob, the primitive resolutions
# below (bead 1f/1g) are the shape and stay at the numbers the bead names.
TRI_BUDGET_BODY = 10500      # whole body, before splitting (bead 1h)
TRI_BUDGET_HEAD = 4500       # head + beret + eyes, after splitting (bead 1h)
TARGET_HEIGHT = 1.78         # natural MakeHuman proportions (orchestrator default)
HAIR_LIFT = 0.006            # short hair as a shell over the scalp, in metres


def log(*a):
    print("[SPIKE]", *a)
    sys.stdout.flush()


def enable_mpfb():
    target = "bl_ext.blender_org.mpfb"
    addon_utils.enable(target, default_set=True, persistent=True)
    importlib.import_module(target)


def dyn(module_suffix, key):
    for name in sys.modules:
        if name.endswith(module_suffix):
            mod = importlib.import_module(name)
            if hasattr(mod, key):
                return getattr(mod, key)
    raise ValueError("no module %s with %s" % (module_suffix, key))


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def joint_centroid(obj, group_name):
    """Centre of one of the basemesh's helper JOINT CUBES, in object space —
    scripts/spike_z3e_head.py's helper, verbatim."""
    idx = obj.vertex_groups[group_name].index
    acc = Vector((0.0, 0.0, 0.0))
    n = 0
    for v in obj.data.vertices:
        for g in v.groups:
            if g.group == idx:
                acc += v.co
                n += 1
                break
    if n == 0:
        raise ValueError("empty vertex group " + group_name)
    return acc / n


# ---------------------------------------------------------------------------
# Bone -> piece / colour region tables (bead 1b, 1e)
# ---------------------------------------------------------------------------

def _fingers(side):
    return ["%s_%02d_%s" % (d, n, side)
            for d in ("thumb", "index", "middle", "ring", "pinky")
            for n in (1, 2, 3)]


PIECE_BONES = {
    "head": ["head", "neck_01"],
    "torso": ["Root", "pelvis", "spine_01", "spine_02", "spine_03",
              "clavicle_l", "clavicle_r"],
    "leftarm.upperarm": ["upperarm_l"],
    "leftarm.lowerarm.mesh": ["lowerarm_l", "hand_l"] + _fingers("l"),
    "rightarm.upperarm": ["upperarm_r"],
    "rightarm.lowerarm.mesh": ["lowerarm_r", "hand_r"] + _fingers("r"),
    "leftleg.upperleg": ["thigh_l"],
    "leftleg.lowerleg.mesh": ["calf_l", "foot_l", "ball_l"],
    "rightleg.upperleg": ["thigh_r"],
    "rightleg.lowerleg.mesh": ["calf_r", "foot_r", "ball_r"],
}

# The .tscn's ten ext_resources, in file order (teibi.tscn — confirmed the
# bead's "eleven" is off by one: ten pieces, ten ext_resource rows, and the
# acceptance criterion that the authored .tscn diff shows only uid/paths/
# origins requires the SAME count).
PIECE_ORDER = [
    "head", "torso",
    "leftarm.upperarm", "leftarm.lowerarm.mesh",
    "rightarm.upperarm", "rightarm.lowerarm.mesh",
    "leftleg.upperleg", "leftleg.lowerleg.mesh",
    "rightleg.upperleg", "rightleg.lowerleg.mesh",
]

# Which transformed joint is each piece's pivot (bead 1c).
PIECE_PIVOT_JOINT = {
    "head": "neck",
    "torso": "pelvis",
    "leftarm.upperarm": "l-shoulder",
    "leftarm.lowerarm.mesh": "l-elbow",
    "rightarm.upperarm": "r-shoulder",
    "rightarm.lowerarm.mesh": "r-elbow",
    "leftleg.upperleg": "l-upper-leg",
    "leftleg.lowerleg.mesh": "l-knee",
    "rightleg.upperleg": "r-upper-leg",
    "rightleg.lowerleg.mesh": "r-knee",
}

# Colour regions are a DIFFERENT partition of the same bones (bead 1e): the
# pelvis is TROUSERS even though it lives in the TORSO piece.
COLOUR_BONES = {
    "skin": ["head", "neck_01", "hand_l", "hand_r"] + _fingers("l") + _fingers("r"),
    "shirt": ["spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r",
              "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"],
    "trousers": ["pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r"],
    "shoes": ["foot_l", "foot_r", "ball_l", "ball_r"],
}
COLOUR_KEY = {"skin": "skin", "shirt": "shirt_mustard",
              "trousers": "trousers", "shoes": "shoes"}


def load_bone_weights():
    with open(WEIGHTS_PATH) as f:
        data = json.load(f)
    return data["weights"]


# ---------------------------------------------------------------------------
# Human + vertex groups (all BEFORE convert — the trap)
# ---------------------------------------------------------------------------

def build_human():
    HumanService = dyn("mpfb.services.humanservice", "HumanService")
    TargetService = dyn("mpfb.services.targetservice", "TargetService")
    LocationService = dyn("mpfb.services.locationservice", "LocationService")
    HumanObjectProperties = dyn("mpfb.entities.objectproperties", "HumanObjectProperties")

    human = HumanService.create_human(mask_helpers=True, detailed_helpers=True,
                                      extra_vertex_groups=True)
    # Teibi's canon (docs/characters/tiebi.md, teibi.png): ordinary man, medium
    # build, calm friendly face, no facial hair. Developer's-eye macros, not a
    # copy of Windman's (bd z3e.2) — different gender/age/build numbers.
    for key, value in (("gender", 0.9), ("age", 0.4), ("muscle", 0.5),
                       ("weight", 0.45), ("caucasian", 1.0), ("african", 0.0),
                       ("asian", 0.0)):
        HumanObjectProperties.set_value(key, value, entity_reference=human)
    TargetService.reapply_macro_details(human)

    targets_root = LocationService.get_mpfb_data("targets")
    for rel, weight in (
            (("head", "head-round.target.gz"), 0.30),
            (("cheek", "l-cheek-volume-incr.target.gz"), 0.18),
            (("cheek", "r-cheek-volume-incr.target.gz"), 0.18),
            (("nose", "nose-scale-vert-decr.target.gz"), 0.15),
            (("chin", "chin-jaw-drop-decr.target.gz"), 0.12),
    ):
        path = os.path.join(targets_root, *rel)
        if not os.path.exists(path):
            log("target missing, skipped:", path)
            continue
        TargetService.load_target(human, path, weight=weight)

    log("joint groups:", sorted(vg.name for vg in human.vertex_groups
                                 if vg.name.startswith("joint-")))

    joints = {}
    for name in ("neck", "l-shoulder", "r-shoulder", "l-elbow", "r-elbow",
                 "l-upper-leg", "r-upper-leg", "l-knee", "r-knee", "pelvis",
                 "l-eye", "r-eye"):
        joints[name] = joint_centroid(human, "joint-" + name)
    log("joints (raw basemesh space):",
        {k: tuple(round(c, 4) for c in v) for k, v in joints.items()})
    return human, joints


def assign_piece_groups(human, bone_weights):
    """Bead 1b: sum each piece's bone weights per vertex; a vertex belongs to
    a piece when that sum is >= STUMP_WEIGHT. Overlap at the blend zone is the
    stump that fills the joint when a limb swings."""
    sums = {}
    for piece, bones in PIECE_BONES.items():
        for bone in bones:
            if bone not in bone_weights:
                log("WARNING: bone not in weights json:", bone)
                continue
            for vidx, w in bone_weights[bone]:
                sums.setdefault(vidx, {}).setdefault(piece, 0.0)
                sums[vidx][piece] += w
    groups = {p: human.vertex_groups.new(name="piece_" + p.replace(".", "_"))
              for p in PIECE_BONES}
    counts = {p: 0 for p in PIECE_BONES}
    for vidx, piece_sums in sums.items():
        for piece, s in piece_sums.items():
            if s >= STUMP_WEIGHT:
                groups[piece].add([vidx], 1.0, 'REPLACE')
                counts[piece] += 1
    log("piece membership (raw basemesh verts, overlap allowed):", counts)
    return groups


def assign_colour_groups(human, bone_weights):
    """Bead 1e's base classification: MUTUALLY EXCLUSIVE (argmax), unlike the
    piece groups above — a seam wants one colour, not a blend."""
    sums = {}
    for region, bones in COLOUR_BONES.items():
        for bone in bones:
            if bone not in bone_weights:
                continue
            for vidx, w in bone_weights[bone]:
                sums.setdefault(vidx, {}).setdefault(region, 0.0)
                sums[vidx][region] += w
    groups = {r: human.vertex_groups.new(name="colour_" + r) for r in COLOUR_BONES}
    counts = {r: 0 for r in COLOUR_BONES}
    for vidx, region_sums in sums.items():
        best = max(region_sums, key=region_sums.get)
        groups[best].add([vidx], 1.0, 'REPLACE')
        counts[best] += 1
    log("colour region membership (raw basemesh verts, argmax):", counts)
    return groups


def bake_to_plain_mesh(obj):
    """Apply the helper MASK modifier and every macro/target shape key in one
    go — spike_z3e_head.py's helper, verbatim. Vertex groups survive."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target='MESH')
    return bpy.context.view_layer.objects.active


def reframe(obj):
    """Turn the whole body 180 degrees (spike_z3e_head.py's measured turn:
    MakeHuman faces -Y, this game's parts face +Y) and scale it UNIFORMLY to
    TARGET_HEIGHT crown-to-heel — natural MakeHuman proportions, NOT today's
    cartoon rig's joint heights (orchestrator default 1)."""
    me = obj.data
    for v in me.vertices:
        v.co.y = -v.co.y
        v.co.x = -v.co.x
    zs = [v.co.z for v in me.vertices]
    crown, heel = max(zs), min(zs)
    scale = TARGET_HEIGHT / (crown - heel)
    for v in me.vertices:
        v.co *= scale
    xs = [v.co.x for v in me.vertices]
    centre_x = (min(xs) + max(xs)) / 2.0
    heel_z = heel * scale
    for v in me.vertices:
        v.co.x -= centre_x
        v.co.z -= heel_z
    me.update()
    zs2 = [v.co.z for v in me.vertices]
    log("reframed: scale %.4f height %.3f (z %.3f..%.3f)"
        % (scale, max(zs2) - min(zs2), min(zs2), max(zs2)))
    return scale, centre_x, heel_z


def transform_point(p, scale, centre_x, heel_z):
    """Carry a joint centroid (measured pre-turn, pre-scale, on the raw human
    object) through the SAME linear map `reframe()` just applied to the mesh."""
    return Vector((-p.x * scale - centre_x, -p.y * scale, p.z * scale - heel_z))


def decimate(obj, tri_target):
    bpy.context.view_layer.objects.active = obj
    obj.data.calc_loop_triangles()
    current = len(obj.data.loop_triangles)
    if current <= tri_target:
        log("no decimation needed (%d tris)" % current)
        return
    mod = obj.modifiers.new("Decimate", 'DECIMATE')
    mod.decimate_type = 'COLLAPSE'
    mod.ratio = float(tri_target) / float(current)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.data.calc_loop_triangles()
    log("decimated %d -> %d tris" % (current, len(obj.data.loop_triangles)))


# ---------------------------------------------------------------------------
# Colour (bead 1e)
# ---------------------------------------------------------------------------

def paint_body(obj, tj):
    """Base region colour by bone-weight argmax (colour_* groups, exclusive),
    then geometric BAND overrides scoped by the PIECE groups so a belt band
    never bleeds onto a leg and a cuff never bleeds onto the torso."""
    me = obj.data
    colour_idx = {name: obj.vertex_groups["colour_" + name].index
                  for name in COLOUR_BONES}
    idx_to_region = {idx: name for name, idx in colour_idx.items()}
    piece_idx = {p: obj.vertex_groups["piece_" + p.replace(".", "_")].index
                 for p in PIECE_BONES}

    pelvis_z = tj["pelvis"].z
    neck_z = tj["neck"].z
    eye_z = ((tj["l-eye"].z + tj["r-eye"].z) / 2.0)
    # No joint-l-wrist helper exists; the forearm is roughly as long as the
    # upper arm, so estimate the wrist a forearm-length past the elbow.
    l_wrist_z = tj["l-elbow"].z - (tj["l-shoulder"].z - tj["l-elbow"].z) * 0.85
    r_wrist_z = tj["r-elbow"].z - (tj["r-shoulder"].z - tj["r-elbow"].z) * 0.85

    def piece_weight(v, piece):
        for g in v.groups:
            if g.group == piece_idx[piece]:
                return g.weight
        return 0.0

    per_vert = [None] * len(me.vertices)
    counts = {}
    for i, v in enumerate(me.vertices):
        region, best_w = "skin", -1.0
        for g in v.groups:
            if g.group in idx_to_region and g.weight > best_w:
                best_w, region = g.weight, idx_to_region[g.group]
        key = COLOUR_KEY[region]

        in_torso = piece_weight(v, "torso") > 0.4
        if in_torso and abs(v.co.z - pelvis_z) <= 0.025:
            key = "belt"
            if v.co.y > 0.06 and abs(v.co.x) < 0.05:
                key = "belt_buckle"
        elif (piece_weight(v, "leftarm.lowerarm.mesh") > 0.4
              and abs(v.co.z - l_wrist_z) <= 0.02) \
                or (piece_weight(v, "rightarm.lowerarm.mesh") > 0.4
                    and abs(v.co.z - r_wrist_z) <= 0.02):
            key = "shirt_collar"   # cuff — the generator's darker-mustard ring
        elif in_torso and neck_z - 0.03 <= v.co.z <= neck_z + 0.015:
            key = "shirt_collar"

        per_vert[i] = key
        counts[key] = counts.get(key, 0) + 1

    # THE HEAD REGION: lips, eyebrows, hair — spike_z3e_head.py's paint(),
    # ported (position-relative-to-eye-line, not bone weight, matches a real
    # face better than a skinning weight ever could).
    lip_z = eye_z - 0.088
    hair_front = eye_z + 0.036
    half_depth = max(abs(v.co.y) for i, v in enumerate(me.vertices)
                      if piece_weight(v, "head") > 0.4) or 1e-6
    normals_dirty = False
    for i, v in enumerate(me.vertices):
        if piece_weight(v, "head") <= 0.4:
            continue
        depth = v.co.y / half_depth
        hair_z = hair_front - 0.05 * max(0.0, -depth)
        if v.co.z >= hair_z:
            per_vert[i] = "hair"
        elif lip_z - 0.014 <= v.co.z <= lip_z + 0.010 and depth > 0.55:
            per_vert[i] = "lips"
        elif eye_z + 0.028 <= v.co.z <= eye_z + 0.040 and depth > 0.45:
            per_vert[i] = "hair"   # eyebrows, hair-coloured, above the eye line

    counts = {}
    for k in per_vert:
        counts[k] = counts.get(k, 0) + 1
    log("paint counts:", counts)

    attr = me.color_attributes.new(name="Color", type='FLOAT_COLOR', domain='POINT')
    for i, key in enumerate(per_vert):
        attr.data[i].color = COLORS[key]
    me.color_attributes.active_color = attr
    me.attributes.active_color = attr

    # The hair shell — lift along the vertex normal, tapered at the hairline,
    # spike_z3e_head.py's HAIR_LIFT idiom.
    me.calc_loop_triangles()
    normals = [v.normal.copy() for v in me.vertices]
    for i, v in enumerate(me.vertices):
        if per_vert[i] != "hair" or piece_weight(v, "head") <= 0.4:
            continue
        taper = min(1.0, (v.co.z - (hair_front - 0.05)) / 0.04)
        v.co += normals[i] * (HAIR_LIFT * max(0.0, taper))
    me.update()


# ---------------------------------------------------------------------------
# Beret + eyes (bead 1f, 1g)
# ---------------------------------------------------------------------------

def _apply_all_transforms(obj):
    bpy.context.view_layer.objects.active = obj
    for o in bpy.data.objects:
        o.select_set(o is obj)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def _make_ring(r_in, r_out, height, name, vertices=18):
    """trimesh.creation.annulus, in bpy: an outer cylinder with a hole punched
    by a boolean difference against a taller inner cylinder."""
    bpy.ops.mesh.primitive_cylinder_add(radius=r_out, depth=height, vertices=vertices)
    outer = bpy.context.active_object
    outer.name = name
    bpy.ops.mesh.primitive_cylinder_add(radius=r_in, depth=height * 1.6, vertices=vertices)
    inner = bpy.context.active_object
    mod = outer.modifiers.new("Hole", 'BOOLEAN')
    mod.operation = 'DIFFERENCE'
    mod.object = inner
    bpy.context.view_layer.objects.active = outer
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(inner, do_unlink=True)
    return outer


def build_beret():
    """create_head_assembly's beret (generate_teibi_separate.py), rebuilt with
    bpy primitives from its EXACT numbers (bead 1g) — dome, brim, headband,
    nub, tilted 7/-11 degrees. Returned UN-SEATED (its own local origin is the
    dome's centre); `seat_on_crown()` positions a copy on a specific head."""
    # Resolutions (segments/rings/vertices) are THIS script's choice, not the
    # bead's -- the radii/heights/tilts it names are all kept exact. Trimmed
    # from a first draft's 24/14/32/28/12/8 (beret+eyes cost 1.7k tris at that
    # resolution, measured 2026-09-08) to fit the head+beret+eyes budget.
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.162, segments=14, ring_count=8)
    dome = bpy.context.active_object
    dome.name = "BeretDome"
    dome.scale = (1.0, 1.0, 0.44)
    _apply_all_transforms(dome)

    brim = _make_ring(0.105, 0.165, 0.020, "BeretBrim")
    brim.location = (0.0, 0.0, -0.028)
    _apply_all_transforms(brim)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.112, depth=0.045, vertices=16,
                                        location=(0.0, 0.0, -0.050))
    band = bpy.context.active_object
    band.name = "BeretBand"
    _apply_all_transforms(band)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.017, segments=8, ring_count=5,
                                         location=(0.0, 0.0, 0.066))
    nub = bpy.context.active_object
    nub.name = "BeretNub"
    _apply_all_transforms(nub)

    for o in bpy.data.objects:
        o.select_set(o in (dome, brim, band, nub))
    bpy.context.view_layer.objects.active = dome
    bpy.ops.object.join()
    beret = bpy.context.active_object
    beret.name = "Beret"

    # The jaunty tilt, about the assembly's own origin (the generator's
    # rotation_matrix calls, composed the same order: X then Y).
    tilt = Matrix.Rotation(math.radians(7), 4, 'X') @ Matrix.Rotation(math.radians(-11), 4, 'Y')
    me = beret.data
    for v in me.vertices:
        v.co = tilt @ v.co
    me.update()

    attr = me.color_attributes.new(name="Color", type='FLOAT_COLOR', domain='POINT')
    for i in range(len(me.vertices)):
        attr.data[i].color = COLORS["beret_navy"]
    me.color_attributes.active_color = attr
    me.attributes.active_color = attr
    return beret


def seat_beret_copy(beret_template, crown_z, embed=0.032):
    """A fresh copy of the beret, seated on a specific head's crown (measured
    in WHATEVER frame the caller passes `crown_z` in — the whole body's or a
    split Head piece's own local one). Keeps the generator's small jaunty
    offset (x 0.015, y 0.004).

    ANCHORED ON THE DOME'S OWN CENTRE (the beret's mesh-data origin, (0,0,0) —
    tilt rotates about it, so it survives `build_beret()` untouched), not on
    its lowest vertex: the assembly spans a genuine 15.6 cm crown-to-band
    (dome radius 0.162 scaled to a 0.44 flat disc, headband down at -0.050,
    nub up at 0.066 -- the generator's own numbers), and a real beret WEARS
    embedded in the scalp, only its top third showing. The first draft
    anchored the LOWEST point at the crown and the whole assembly floated
    ~17 cm above the head (measured 2026-09-08 via blender_hero.py's
    assembled-height assert: 1.9476 m against a 1.78 m body). `embed` instead
    sinks the origin 3.2 cm below the crown — the generator's own dome-centre-
    to-crown distance in ITS head's frame (crown ~0.124, dome translated to
    z=0.092) — so the nub pokes up ~5 cm and the band buries into the skull,
    both inside the tolerance a spike needs, not a literal fit."""
    copy = beret_template.copy()
    copy.data = beret_template.data.copy()
    bpy.context.collection.objects.link(copy)
    me = copy.data
    dz = crown_z - embed
    for v in me.vertices:
        v.co.x += 0.015
        v.co.y += 0.004
        v.co.z += dz
    me.update()
    return copy


def build_eyes(l_pos, r_pos, radius=0.012):
    """Two small UV spheres at the eye joints, white with a dark iris/pupil
    disc on the +Y (face) side — mask_helpers=True deleted MakeHuman's own
    eyeball helpers, and MPFB2's eye ASSETS are a separate download (bead 1f:
    do not go looking for them)."""
    spheres = []
    for pos, side in ((l_pos, "L"), (r_pos, "R")):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=10, ring_count=6,
                                             location=(pos.x, pos.y, pos.z))
        eye = bpy.context.active_object
        eye.name = "Eye" + side
        _apply_all_transforms(eye)
        me = eye.data
        attr = me.color_attributes.new(name="Color", type='FLOAT_COLOR', domain='POINT')
        for i, v in enumerate(me.vertices):
            local_y = v.co.y - pos.y
            attr.data[i].color = COLORS["eye_iris"] if local_y > radius * 0.55 \
                else COLORS["eye_white"]
        me.color_attributes.active_color = attr
        me.attributes.active_color = attr
        spheres.append(eye)
    for o in bpy.data.objects:
        o.select_set(o in spheres)
    bpy.context.view_layer.objects.active = spheres[0]
    bpy.ops.object.join()
    eyes = bpy.context.active_object
    eyes.name = "Eyes"
    return eyes


def join_into(target, extra):
    bpy.context.view_layer.objects.active = target
    for o in bpy.data.objects:
        o.select_set(o is target or o is extra)
    bpy.ops.object.join()
    return target


def measure_group_extent(obj, group_name, axis="z", mode="max", min_weight=0.4):
    idx = obj.vertex_groups[group_name].index
    vals = []
    for v in obj.data.vertices:
        for g in v.groups:
            if g.group == idx and g.weight >= min_weight:
                vals.append(getattr(v.co, axis))
                break
    if not vals:
        raise ValueError("no verts in group " + group_name + " at weight >= %.2f" % min_weight)
    return max(vals) if mode == "max" else min(vals)


# ---------------------------------------------------------------------------
# Split into pieces (bead 1b/1c)
# ---------------------------------------------------------------------------

def split_piece(obj, piece_key):
    bpy.context.view_layer.objects.active = obj
    piece_obj = obj.copy()
    piece_obj.data = obj.data.copy()
    bpy.context.collection.objects.link(piece_obj)
    piece_obj.name = "piece_" + piece_key.replace(".", "_")
    group_name = "piece_" + piece_key.replace(".", "_")

    me = piece_obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    dvert = bm.verts.layers.deform.verify()
    gi = piece_obj.vertex_groups[group_name].index
    bm.verts.ensure_lookup_table()
    doomed = [v for v in bm.verts if gi not in v[dvert] or v[dvert][gi] < 0.5]
    bmesh.ops.delete(bm, geom=doomed, context='VERTS')
    boundary = [e for e in bm.edges if e.is_boundary]
    if boundary:
        bmesh.ops.holes_fill(bm, edges=boundary, sides=0)
    bm.to_mesh(me)
    bm.free()
    me.update()
    return piece_obj


def centre_on_pivot(piece_obj, pivot):
    me = piece_obj.data
    for v in me.vertices:
        v.co -= pivot
    me.update()


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

def export_glb(obj, path):
    for o in bpy.data.objects:
        o.select_set(o is obj)
    bpy.context.view_layer.objects.active = obj
    for poly in obj.data.polygons:
        poly.use_smooth = True
    obj.data.update()
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        # spike_z3e_head.py's export(): the Rx(-90) part-basis this repo's
        # generators (and the .tscn) are authored against expects Z-up.
        export_yup=False,
        export_normals=True,
        export_tangents=False,
        # Vertex colours, no material, no texture — owner ruling (zero bytes),
        # matches the faceted head variant's export path (Godot's glTF
        # importer turns COLOR_0 + no material into
        # StandardMaterial3D.vertex_color_use_as_albedo, the shipped path).
        export_vertex_color='ACTIVE',
        export_all_vertex_colors=False,
        export_texcoords=False,
        export_materials='NONE',
        export_image_format='NONE',
    )
    obj.data.calc_loop_triangles()
    tris = len(obj.data.loop_triangles)
    size = os.path.getsize(path)
    log("wrote %s (%d tris, %d bytes)" % (os.path.basename(path), tris, size))
    return tris, size


def assert_no_multires(objs):
    for obj in objs:
        for mod in getattr(obj, "modifiers", []):
            if mod.type == 'MULTIRES':
                raise AssertionError("%s carries a MULTIRES modifier" % obj.name)


PART_FILENAME = {
    "head": "teibi_head_authored.glb",
    "torso": "teibi_torso_authored.glb",
    "leftarm.upperarm": "teibi_left_upper_arm_authored.glb",
    "leftarm.lowerarm.mesh": "teibi_left_lower_arm_authored.glb",
    "rightarm.upperarm": "teibi_right_upper_arm_authored.glb",
    "rightarm.lowerarm.mesh": "teibi_right_lower_arm_authored.glb",
    "leftleg.upperleg": "teibi_left_upper_leg_authored.glb",
    "leftleg.lowerleg.mesh": "teibi_left_lower_leg_authored.glb",
    "rightleg.upperleg": "teibi_right_upper_leg_authored.glb",
    "rightleg.lowerleg.mesh": "teibi_right_lower_leg_authored.glb",
}


def main():
    enable_mpfb()
    clear_scene()
    bone_weights = load_bone_weights()

    human, joints = build_human()
    piece_groups = assign_piece_groups(human, bone_weights)
    colour_groups = assign_colour_groups(human, bone_weights)

    obj = bake_to_plain_mesh(human)
    scale, centre_x, heel_z = reframe(obj)
    tj = {name: transform_point(p, scale, centre_x, heel_z) for name, p in joints.items()}
    log("transformed joints:", {k: tuple(round(c, 4) for c in v) for k, v in tj.items()})

    # THE TWO ASSERTS THE BEAD NAMES: face at +Y, left shoulder at -X.
    if tj["l-eye"].y <= 0.0 and tj["r-eye"].y <= 0.0:
        raise AssertionError("body facing backwards: eye y=%.4f/%.4f"
                             % (tj["l-eye"].y, tj["r-eye"].y))
    if tj["l-shoulder"].x >= 0.0:
        raise AssertionError("left shoulder not at negative x: %.4f" % tj["l-shoulder"].x)
    log("ASSERT OK: face +Y, joint-l-shoulder x=%.4f (< 0)" % tj["l-shoulder"].x)

    decimate(obj, TRI_BUDGET_BODY)
    paint_body(obj, tj)

    beret_template = build_beret()
    eyes_whole = build_eyes(tj["l-eye"], tj["r-eye"])

    # ---- UNCUT: one mesh, feet at z=0 (reframe() already put them there) ----
    uncut = obj.copy()
    uncut.data = obj.data.copy()
    bpy.context.collection.objects.link(uncut)
    uncut.name = "TeibiUncut"
    crown_z_whole = measure_group_extent(uncut, "piece_head", "z", "max")
    beret_whole = seat_beret_copy(beret_template, crown_z_whole)
    join_into(uncut, beret_whole)
    eyes_whole_copy = eyes_whole.copy()
    eyes_whole_copy.data = eyes_whole.data.copy()
    bpy.context.collection.objects.link(eyes_whole_copy)
    join_into(uncut, eyes_whole_copy)
    uncut.data.calc_loop_triangles()
    log("uncut whole body: %d tris" % len(uncut.data.loop_triangles))
    export_glb(uncut, os.path.join(OUT_DIR, "teibi_uncut_authored.glb"))

    # ---- PARTS: ten pieces, pivot-centred, head decorated ----
    part_objs = []
    godot_origins = {}
    for piece_key in PIECE_ORDER:
        piece_obj = split_piece(obj, piece_key)
        pivot = tj[PIECE_PIVOT_JOINT[piece_key]]
        centre_on_pivot(piece_obj, pivot)
        godot_origins[piece_key] = Vector((pivot.x, pivot.z, -pivot.y))

        if piece_key == "head":
            crown_z_local = measure_group_extent(piece_obj, "piece_head", "z", "max")
            beret_local = seat_beret_copy(beret_template, crown_z_local)
            join_into(piece_obj, beret_local)
            eyes_local = eyes_whole.copy()
            eyes_local.data = eyes_whole.data.copy()
            bpy.context.collection.objects.link(eyes_local)
            for v in eyes_local.data.vertices:
                v.co -= pivot
            join_into(piece_obj, eyes_local)

        part_objs.append(piece_obj)

    bpy.data.objects.remove(beret_template, do_unlink=True)
    bpy.data.objects.remove(eyes_whole, do_unlink=True)

    assert_no_multires([obj, uncut] + part_objs)

    total_tris = 0
    head_tris = 0
    for piece_key, piece_obj in zip(PIECE_ORDER, part_objs):
        path = os.path.join(OUT_DIR, PART_FILENAME[piece_key])
        tris, _size = export_glb(piece_obj, path)
        total_tris += tris
        if piece_key == "head":
            head_tris = tris
    log("PARTS total tris: %d (budget %d)" % (total_tris, TRI_BUDGET_BODY))
    log("HEAD+beret+eyes tris: %d (budget %d)" % (head_tris, TRI_BUDGET_HEAD))
    if head_tris > TRI_BUDGET_HEAD:
        log("WARNING: head+beret+eyes over budget")
    log("texture bytes: 0 (vertex colours only)")

    log("=== GODOT ORIGINS (pivot in Godot = (x, z, -y) of the part-frame pivot) ===")
    for piece_key in PIECE_ORDER:
        o = godot_origins[piece_key]
        log("  %-24s (%.4f, %.4f, %.4f)" % (piece_key, o.x, o.y, o.z))
    # The two CONTAINER-relative origins the .tscn actually stores for the
    # nested LowerArm/LowerLeg empties (elbow/knee relative to shoulder/hip —
    # same (x, z, -y) map applied to the DIFFERENCE, since it is linear).
    for side in ("l", "r"):
        shoulder = tj["%s-shoulder" % side]
        elbow = tj["%s-elbow" % side]
        rel = elbow - shoulder
        log("  %sarm.lowerarm container (rel to %sarm)   (%.4f, %.4f, %.4f)"
            % (side, side, rel.x, rel.z, -rel.y))
        hip = tj["%s-upper-leg" % side]
        knee = tj["%s-knee" % side]
        rel2 = knee - hip
        log("  %sleg.lowerleg container (rel to %sleg)   (%.4f, %.4f, %.4f)"
            % (side, side, rel2.x, rel2.z, -rel2.y))

    OUT_BLEND = os.path.join(OUT_DIR, "teibi_authored.blend")
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND, compress=True)
    log("wrote %s (%d bytes)" % (os.path.basename(OUT_BLEND), os.path.getsize(OUT_BLEND)))
    log("done")


main()
