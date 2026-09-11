"""
scripts/build_hero.py — ONE SKINNED HERO from the MPFB2/MakeHuman basemesh.

Bead godot-test1-5u3.1 (epic 5u3, SKINNED HEROES). Started as a copy of
scripts/spike_z3e_teibi_body.py with the ten-piece joint SPLIT removed and an
ARMATURE added: the body is now one mesh on MPFB2's `game_engine` rig (53 bones),
exported as one skinned .glb. Everything that was a module constant there is a
`HEROES` row here, so bead 5u3.4 adds windman/primm/phoboman as rows and not as
a second script.

NOT part of the build, NOT run by CI: run by hand.

  perl -e 'alarm 900; exec @ARGV' \
      blender --background --python-exit-code 1 --python scripts/build_hero.py -- teibi
  godot --headless --path . --import        # Godot caches .glb imports

THE TRAPS THIS LANE PAYS FOR (the four in `bd show godot-test1-z3e` NOTES —
MPFB2 enable with default_set=True, no --factory-startup, the full
bl_ext.blender_org.mpfb import path, `--import` after every rebuild — plus
these, which are this bead's own):

 1. WEIGHTS ARE BASEMESH-INDEXED. `HumanService.add_builtin_rig(...,
    import_weights=True)` writes one vertex group per bone off
    weights.game_engine.json, whose indices are RAW BASEMESH indices. The
    helper MASK modifier renumbers vertices, so the rig must be added BEFORE
    `bpy.ops.object.convert()`. (spike_z3e_teibi_body.py's header trap, same
    cause, different victim.)
 2. `convert(target='MESH')` APPLIES AND REMOVES EVERY MODIFIER, the armature
    modifier included — the bone weights survive (they are vertex groups), the
    binding does not. Re-add it with `RigService.ensure_armature_modifier`.
 3. blender_hero.py's conjugation trick (W_blender = Rx(90)·W_godot·Rx(90)^-1)
    is for UNRIGGED parts hung on a .tscn node whose basis is Rx(-90). A
    SKINNED glTF is placed by its own root node and exports Y-up: do NOT copy
    it here. This script builds in Blender's Z-up with +Y = the face, exports
    with `export_yup=True` (the default), and glTF's (x, z, -y) map lands the
    face on Godot's -Z and the character's left on -X, which is what today's
    heroes do (teibi.tscn LeftArm x=-0.18).
 4. A RIG DOES NOT FOLLOW `mesh.vertices[i].co`. The spike reframed by editing
    vertex coordinates; that leaves the bones where they were and the body
    floats off its skeleton. `reframe()` here transforms the mesh DATA and the
    armature DATA with the same matrix (`ID.transform()` on both), so both
    objects keep identity transforms and the rest pose stays consistent.
 5. MAKEHUMAN RESTS IN AN A-POSE (measured: upper arms 41.3 deg off vertical).
    Fixed as REST POSE in Blender (`apply_pose_as_rest`), never in the .tscn —
    an exported rest that is not the game's rest means both animation columns
    start from the wrong arms.
 6. `pose.bones[...].head` / `.tail` / `.matrix` DO NOT FOLLOW `data.transform()`.
    They are evaluated through the depsgraph, `view_layer.update()` does not
    refresh them, and after `reframe()` they answer in the PRE-turn frame. Read
    and write the rest data (`data.bones[...].head_local`, `.tail_local`,
    `.matrix_local`, and `pose.bones[...].matrix_basis`) instead —
    `apply_pose_as_rest`'s docstring has the measurement that cost a rebuild.
"""

import math
import os
import sys

import addon_utils
import bpy
import importlib
from mathutils import Matrix, Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_ROOT = os.path.join(REPO, "assets", "models", "characters")

RIG = "game_engine"
RIG_BONES = 53               # what the epic promises; asserted after the rig lands
ARMS_DOWN_DEG = 5.0          # how far the arms stand off vertical in the shipped rest


def _fingers(side):
    return ["%s_%02d_%s" % (d, n, side)
            for d in ("thumb", "index", "middle", "ring", "pinky")
            for n in (1, 2, 3)]


# Which bones wear which colour. A vertex takes the region whose bones hold the
# most of its skin weight (argmax) — `paint_body`'s base coat, before the
# geometric band overrides. Shared by every hero; the COLOURS are per row.
COLOUR_BONES = {
    "skin": ["head", "neck_01", "hand_l", "hand_r"] + _fingers("l") + _fingers("r"),
    "shirt": ["spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r",
              "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"],
    "trousers": ["pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r"],
    "shoes": ["foot_l", "foot_r", "ball_l", "ball_r"],
}
# Bone groups the band overrides are SCOPED by, so a belt never bleeds onto a
# leg and a cuff never onto the torso (spike_z3e_teibi_body.py's `piece_*`
# groups, re-expressed on the rig's own groups now that the rig exists).
REGION_BONES = {
    "torso": ["pelvis", "spine_01", "spine_02", "spine_03"],
    "head": ["head", "neck_01"],
    "lowerarm_l": ["lowerarm_l", "hand_l"] + _fingers("l"),
    "lowerarm_r": ["lowerarm_r", "hand_r"] + _fingers("r"),
}

HEROES = {
    "teibi": {
        # docs/characters/tiebi.md: ordinary man, medium build, calm friendly
        # face, no facial hair. spike_z3e_teibi_body.py's numbers, verbatim.
        "macros": {"gender": 0.9, "age": 0.4, "muscle": 0.5, "weight": 0.45,
                   "caucasian": 1.0, "african": 0.0, "asian": 0.0},
        "targets": [(("head", "head-round.target.gz"), 0.30),
                    (("cheek", "l-cheek-volume-incr.target.gz"), 0.18),
                    (("cheek", "r-cheek-volume-incr.target.gz"), 0.18),
                    (("nose", "nose-scale-vert-decr.target.gz"), 0.15),
                    (("chin", "chin-jaw-drop-decr.target.gz"), 0.12)],
        # generate_teibi_separate.py's palette, verbatim (owner ruling: vertex
        # colours, zero texture bytes).
        "colours": {
            "skin":          (0.86, 0.66, 0.54, 1.0),
            "hair":          (0.17, 0.12, 0.09, 1.0),
            "beret_navy":    (0.07, 0.09, 0.19, 1.0),
            "shirt_mustard": (0.87, 0.66, 0.17, 1.0),
            "shirt_collar":  (0.74, 0.55, 0.12, 1.0),
            "trousers":      (0.20, 0.22, 0.28, 1.0),
            "belt":          (0.11, 0.10, 0.11, 1.0),
            "belt_buckle":   (0.55, 0.50, 0.30, 1.0),
            "shoes":         (0.16, 0.11, 0.08, 1.0),
            "lips":          (0.80, 0.55, 0.48, 1.0),
            "eye_white":     (0.92, 0.92, 0.90, 1.0),
            "eye_iris":      (0.22, 0.16, 0.11, 1.0),
        },
        "colour_key": {"skin": "skin", "shirt": "shirt_mustard",
                       "trousers": "trousers", "shoes": "shoes"},
        "beret": True,
        "height": 1.78,      # crown-to-heel, natural MakeHuman proportions
        # The body's decimate target. The beret + eyes are joined AFTER it and
        # cost ~1.4k more; the whole-body ceiling the bead names is 12k.
        "tri_target": 10500,
        "tri_budget": 12000,
        "out_dir": "teibi_parts",
        "stem": "teibi_skinned",
    },
}

HAIR_LIFT = 0.006            # short hair as a shell over the scalp, in metres


def log(*a):
    print("[BUILD]", *a)
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
    spike_z3e_head.py's helper, verbatim."""
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
# The human, the rig
# ---------------------------------------------------------------------------

def build_human(row):
    HumanService = dyn("mpfb.services.humanservice", "HumanService")
    TargetService = dyn("mpfb.services.targetservice", "TargetService")
    LocationService = dyn("mpfb.services.locationservice", "LocationService")
    HumanObjectProperties = dyn("mpfb.entities.objectproperties", "HumanObjectProperties")

    human = HumanService.create_human(mask_helpers=True, detailed_helpers=True,
                                      extra_vertex_groups=True)
    for key, value in row["macros"].items():
        HumanObjectProperties.set_value(key, value, entity_reference=human)
    TargetService.reapply_macro_details(human)

    targets_root = LocationService.get_mpfb_data("targets")
    for rel, weight in row["targets"]:
        path = os.path.join(targets_root, *rel)
        if not os.path.exists(path):
            log("target missing, skipped:", path)
            continue
        TargetService.load_target(human, path, weight=weight)

    joints = {}
    for name in ("neck", "l-shoulder", "r-shoulder", "l-elbow", "r-elbow",
                 "l-upper-leg", "r-upper-leg", "l-knee", "r-knee", "pelvis",
                 "l-eye", "r-eye"):
        joints[name] = joint_centroid(human, "joint-" + name)
    log("joints (raw basemesh space):",
        {k: tuple(round(c, 4) for c in v) for k, v in joints.items()})
    return human, joints


def add_rig(human):
    """TRAP 1: before `convert()`, because the weights JSON is basemesh-indexed."""
    HumanService = dyn("mpfb.services.humanservice", "HumanService")
    armature = HumanService.add_builtin_rig(human, RIG, import_weights=True)
    if armature is None:
        raise AssertionError("add_builtin_rig returned None for rig " + RIG)
    bones = len(armature.data.bones)
    log("rig %r: %d bones, armature %r" % (RIG, bones, armature.name))
    if bones != RIG_BONES:
        raise AssertionError("expected %d bones, got %d" % (RIG_BONES, bones))
    # The armature object owns the human's old location; both are at the origin
    # for us, but keep the invariant explicit — `reframe()` bakes into DATA and
    # assumes both objects are at identity.
    armature.location = (0.0, 0.0, 0.0)
    human.location = (0.0, 0.0, 0.0)
    return armature


def report_weights(obj, armature, label):
    """Every vertex of the body must be driven by SOME bone, or it stays behind
    when the hero walks. Prints the five worst so a hole is nameable."""
    bone_names = {b.name for b in armature.data.bones}
    bone_group_ids = {vg.index for vg in obj.vertex_groups if vg.name in bone_names}
    totals = []
    for v in obj.data.vertices:
        totals.append(sum(g.weight for g in v.groups if g.group in bone_group_ids))
    totals_sorted = sorted(range(len(totals)), key=lambda i: totals[i])[:5]
    worst = [(i, round(totals[i], 5)) for i in totals_sorted]
    unweighted = sum(1 for t in totals if t <= 0.0)
    log("%s: %d verts, %d with ZERO bone weight, 5 lowest %s"
        % (label, len(totals), unweighted, worst))
    if unweighted:
        raise AssertionError("%d vertices carry no bone weight" % unweighted)


def bake_to_plain_mesh(obj, armature):
    """Apply the helper MASK modifier and every macro/target shape key in one go.
    TRAP 2: this also drops the armature modifier, so put it back."""
    RigService = dyn("mpfb.services.rigservice", "RigService")
    bpy.context.view_layer.objects.active = obj
    for o in bpy.data.objects:
        o.select_set(o is obj)
    bpy.ops.object.convert(target='MESH')
    obj = bpy.context.view_layer.objects.active
    has_armature = any(m.type == 'ARMATURE' for m in obj.modifiers)
    log("after convert: %d verts, armature modifier survived: %s"
        % (len(obj.data.vertices), has_armature))
    if not has_armature:
        RigService.ensure_armature_modifier(obj, armature)
        log("re-added the armature modifier (TRAP 2)")
    return obj


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


def reframe(obj, armature, target_height):
    """
    TRAP 4. Turn the human 180 degrees about Z (MakeHuman faces -Y, this game's
    frame faces +Y), scale it uniformly to `target_height` crown-to-heel, centre
    it on X and drop its heels to z=0 — applying the SAME matrix to the mesh data
    and to the armature data, so the bones move with the skin and both objects
    keep an identity object transform.

    Returns the matrix, so a joint centroid measured on the raw human can be
    carried into the same frame.
    """
    zs = [v.co.z for v in obj.data.vertices]
    xs = [v.co.x for v in obj.data.vertices]
    crown, heel = max(zs), min(zs)
    scale = target_height / (crown - heel)
    # Rz(180) first, then the uniform scale, then the recentre. The x centre is
    # measured pre-turn, so it is negated by the turn like every other x.
    centre_x = (min(xs) + max(xs)) / 2.0
    m = (Matrix.Translation(Vector((centre_x * scale, 0.0, -heel * scale)))
         @ Matrix.Scale(scale, 4)
         @ Matrix.Rotation(math.pi, 4, 'Z'))
    obj.data.transform(m)
    armature.data.transform(m)
    obj.data.update()
    zs2 = [v.co.z for v in obj.data.vertices]
    log("reframed: scale %.4f height %.4f (z %.4f..%.4f)"
        % (scale, max(zs2) - min(zs2), min(zs2), max(zs2)))
    return m


def apply_pose_as_rest(armature, obj, arms_down_deg):
    """
    TRAP 5. Swing both upper arms from MakeHuman's A-pose down to
    `arms_down_deg` off vertical, then bake that pose as the REST pose: apply
    the armature modifier on the skin, `pose.armature_apply()` on the bones,
    re-add the modifier.

    Done by hand rather than through `RigService.apply_pose_as_rest_pose`,
    which walks MPFB2's own basemesh/asset relations — after `convert()` and the
    beret/eye join this is a plain mesh with none of that bookkeeping left.

    The rotation is computed in ARMATURE space from the bone's own rest
    direction, so it needs no knowledge of the bone's roll: whatever axis
    `upperarm_l` happens to be built on, `rotation_difference` finds the turn
    that takes the arm from where it points to straight down. Children (forearm,
    hand, fingers) are parented and follow.

    TRAP 6, and it cost a whole rebuild and a whole re-shoot. EVERYTHING HERE IS
    READ AND WRITTEN THROUGH `armature.data`, never through `pose.bones[...].head
    / .tail / .matrix`, because `reframe()` moved the rig by transforming its
    DATA and the evaluated pose does not follow that until the depsgraph catches
    up — `view_layer.update()` does not make it. Measured: after the 180-degree
    reframe, `pose.bones["upperarm_l"].tail - .head` still read
    (+0.660, +0.005, -0.751), the PRE-turn direction, so the left arm was swung
    onto the right arm's side and the exported rest came out with both arms
    5 degrees off vertical THE SAME WAY. `data.bones[...].head_local` /
    `.tail_local` / `.matrix_local` are plain rest data and are current the
    instant `data.transform()` returns.

    So the pose is written as `matrix_basis` — the bone-local delta — by
    conjugating the wanted ARMATURE-space rotation through the bone's own rest
    basis, exactly the trick `style_shots.gd`'s `_bone_pose()` uses on the Godot
    side for the same reason (MakeHuman bones carry rolls).
    """
    RigService = dyn("mpfb.services.rigservice", "RigService")
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode='POSE')
    ang = math.radians(arms_down_deg)
    wanted = {}
    for side, sign in (("l", -1.0), ("r", 1.0)):
        bone = armature.data.bones["upperarm_" + side]
        d = (bone.tail_local - bone.head_local).normalized()
        want = Vector((sign * math.sin(ang), 0.0, -math.cos(ang)))
        wanted["upperarm_" + side] = want
        rest = bone.matrix_local.to_3x3()
        local = rest.inverted() @ d.rotation_difference(want).to_matrix() @ rest
        armature.pose.bones["upperarm_" + side].matrix_basis = local.to_4x4()
        log("upperarm_%s: A-pose %s -> want %s"
            % (side, tuple(round(v, 4) for v in d),
               tuple(round(v, 4) for v in want)))
    bpy.ops.object.mode_set(mode='OBJECT')

    bpy.context.view_layer.objects.active = obj
    for o in bpy.data.objects:
        o.select_set(o is obj)
    for mod in list(obj.modifiers):
        if mod.type == 'ARMATURE':
            bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.context.view_layer.objects.active = armature
    for o in bpy.data.objects:
        o.select_set(o is armature)
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    RigService.ensure_armature_modifier(obj, armature)

    # SIGNED, and asserted on the REST data the bake just wrote — the one reading
    # that cannot be stale and the one the .glb is exported from. The first draft
    # logged `Vector.angle()`, which is unsigned, so it printed a contented
    # "5.0 deg" for both arms while one of them pointed into the hip.
    for name, want in wanted.items():
        bone = armature.data.bones[name]
        got = (bone.tail_local - bone.head_local).normalized()
        log("%s rest is now %s" % (name, tuple(round(v, 4) for v in got)))
        if (got - want).length > 1e-3:
            raise AssertionError(
                "%s rest %s is not the direction asked for %s"
                % (name, tuple(got), tuple(want)))


# ---------------------------------------------------------------------------
# Colour (spike_z3e_teibi_body.py's paint_body, on the rig's own groups)
# ---------------------------------------------------------------------------

def _group_weight(v, ids):
    return sum(g.weight for g in v.groups if g.group in ids)


def paint_body(obj, tj, row):
    """Base region colour by bone-weight argmax, then geometric BAND overrides
    (belt, cuffs, collar) scoped by bone region, then the face detail."""
    colours = row["colours"]
    colour_key = row["colour_key"]
    me = obj.data
    name_to_id = {vg.name: vg.index for vg in obj.vertex_groups}

    def ids(bones):
        return {name_to_id[b] for b in bones if b in name_to_id}

    region_ids = {r: ids(bones) for r, bones in COLOUR_BONES.items()}
    scope_ids = {r: ids(bones) for r, bones in REGION_BONES.items()}

    pelvis_z = tj["pelvis"].z
    neck_z = tj["neck"].z
    eye_z = (tj["l-eye"].z + tj["r-eye"].z) / 2.0
    # No joint-l-wrist helper exists; the forearm is roughly as long as the upper
    # arm, so estimate the wrist a forearm-length past the elbow.
    wrist_z = {s: tj["%s-elbow" % s].z
               - (tj["%s-shoulder" % s].z - tj["%s-elbow" % s].z) * 0.85
               for s in ("l", "r")}

    per_vert = [None] * len(me.vertices)
    for i, v in enumerate(me.vertices):
        region = max(region_ids, key=lambda r: _group_weight(v, region_ids[r]))
        key = colour_key[region]

        in_torso = _group_weight(v, scope_ids["torso"]) > 0.4
        if in_torso and abs(v.co.z - pelvis_z) <= 0.025:
            key = "belt"
            if v.co.y > 0.06 and abs(v.co.x) < 0.05:
                key = "belt_buckle"
        elif any(_group_weight(v, scope_ids["lowerarm_" + s]) > 0.4
                 and abs(v.co.z - wrist_z[s]) <= 0.02 for s in ("l", "r")):
            key = "shirt_collar"   # cuff — the generator's darker-mustard ring
        elif in_torso and neck_z - 0.03 <= v.co.z <= neck_z + 0.015:
            key = "shirt_collar"
        per_vert[i] = key

    # THE HEAD REGION: lips, eyebrows, hair — spike_z3e_head.py's paint(),
    # position-relative-to-the-eye-line rather than by skinning weight.
    head_ids = scope_ids["head"]
    lip_z = eye_z - 0.088
    hair_front = eye_z + 0.036
    half_depth = max((abs(v.co.y) for v in me.vertices
                      if _group_weight(v, head_ids) > 0.4), default=1e-6)
    for i, v in enumerate(me.vertices):
        if _group_weight(v, head_ids) <= 0.4:
            continue
        depth = v.co.y / half_depth
        hair_z = hair_front - 0.05 * max(0.0, -depth)
        if v.co.z >= hair_z:
            per_vert[i] = "hair"
        elif lip_z - 0.014 <= v.co.z <= lip_z + 0.010 and depth > 0.55:
            per_vert[i] = "lips"
        elif eye_z + 0.028 <= v.co.z <= eye_z + 0.040 and depth > 0.45:
            per_vert[i] = "hair"   # eyebrows, above the eye line

    counts = {}
    for k in per_vert:
        counts[k] = counts.get(k, 0) + 1
    log("paint counts:", counts)

    attr = me.color_attributes.new(name="Color", type='FLOAT_COLOR', domain='POINT')
    for i, key in enumerate(per_vert):
        attr.data[i].color = colours[key]
    me.color_attributes.active_color = attr
    me.attributes.active_color = attr

    # The hair shell — lift along the vertex normal, tapered at the hairline.
    me.calc_loop_triangles()
    normals = [v.normal.copy() for v in me.vertices]
    for i, v in enumerate(me.vertices):
        if per_vert[i] != "hair" or _group_weight(v, head_ids) <= 0.4:
            continue
        taper = min(1.0, (v.co.z - (hair_front - 0.05)) / 0.04)
        v.co += normals[i] * (HAIR_LIFT * max(0.0, taper))
    me.update()


# ---------------------------------------------------------------------------
# Beret + eyes (spike_z3e_teibi_body.py's, unchanged but for the head weights)
# ---------------------------------------------------------------------------

def _apply_all_transforms(obj):
    bpy.context.view_layer.objects.active = obj
    for o in bpy.data.objects:
        o.select_set(o is obj)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def _make_ring(r_in, r_out, height, name, vertices=18):
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


def build_beret(colours, crown_z, embed=0.032):
    """generate_teibi_separate.py's beret — dome, brim, headband, nub, tilted
    7/-11 degrees — seated on the crown. `embed` sinks the dome's own centre
    3.2 cm below the crown, which is where the generator wears it: a beret sits
    IN the scalp with its top third showing, and anchoring its lowest vertex on
    the crown floats the whole assembly 17 cm off the head (measured on the
    z3e.10 spike)."""
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

    tilt = (Matrix.Rotation(math.radians(7), 4, 'X')
            @ Matrix.Rotation(math.radians(-11), 4, 'Y'))
    seat = Matrix.Translation(Vector((0.015, 0.004, crown_z - embed)))
    beret.data.transform(seat @ tilt)
    beret.data.update()

    attr = beret.data.color_attributes.new(name="Color", type='FLOAT_COLOR',
                                           domain='POINT')
    for i in range(len(beret.data.vertices)):
        attr.data[i].color = colours["beret_navy"]
    beret.data.color_attributes.active_color = attr
    beret.data.attributes.active_color = attr
    return beret


def build_eyes(colours, l_pos, r_pos, radius=0.012):
    """Two small spheres at the eye joints, white with a dark iris on the +Y
    (face) side — `mask_helpers=True` deleted MakeHuman's own eyeball helpers
    and MPFB2's eye ASSETS are a separate download."""
    spheres = []
    for pos, side in ((l_pos, "L"), (r_pos, "R")):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=10, ring_count=6,
                                             location=(pos.x, pos.y, pos.z))
        eye = bpy.context.active_object
        eye.name = "Eye" + side
        _apply_all_transforms(eye)
        attr = eye.data.color_attributes.new(name="Color", type='FLOAT_COLOR',
                                             domain='POINT')
        for i, v in enumerate(eye.data.vertices):
            attr.data[i].color = colours["eye_iris"] \
                if v.co.y - pos.y > radius * 0.55 else colours["eye_white"]
        eye.data.color_attributes.active_color = attr
        eye.data.attributes.active_color = attr
        spheres.append(eye)
    for o in bpy.data.objects:
        o.select_set(o in spheres)
    bpy.context.view_layer.objects.active = spheres[0]
    bpy.ops.object.join()
    eyes = bpy.context.active_object
    eyes.name = "Eyes"
    return eyes


def join_rigid(target, extra, bone):
    """Join `extra` into `target` with every one of its vertices weighted 1.0 to
    `bone`. The join happens AFTER the rig so MPFB2's automatic weights are
    never asked to guess for a beret; the group is written by hand instead."""
    vg = extra.vertex_groups.new(name=bone)
    vg.add(list(range(len(extra.data.vertices))), 1.0, 'REPLACE')
    bpy.context.view_layer.objects.active = target
    for o in bpy.data.objects:
        o.select_set(o is target or o is extra)
    bpy.ops.object.join()
    return bpy.context.active_object


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

def export_glb(obj, armature, path):
    """
    SMOOTH, and deliberately not through `predator_parts.export_faceted()`.
    CLAUDE.md calls that "the one export seam for every generated `.glb`
    (heroes included)", and three things put this lane outside it: the y1o
    faceted ruling is WAIVED FOR THE FOUR HEROES by the owner (bd show
    godot-test1-z3e NOTES, 2026-09-06); `export_faceted` is trimesh code and
    cannot be called from Blender at all, its Blender port being
    `blender_hero.py`'s opt-in `--faceted`; and the predecessor this script is a
    copy of (`spike_z3e_teibi_body.py:669`) smooth-shades the same MPFB2 body
    the same way. Flat normals on an organic basemesh are also what tore the
    hero outline into cracks (bead z3e.9).
    """
    for o in bpy.data.objects:
        o.select_set(o is obj or o is armature)
    bpy.context.view_layer.objects.active = armature
    for poly in obj.data.polygons:
        poly.use_smooth = True
    obj.data.update()
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        # TRAP 3: a SKINNED glTF is placed by its own root node. Y-up (the
        # default), not blender_hero.py's Z-up part convention.
        export_yup=True,
        export_skins=True,
        export_normals=True,
        export_tangents=False,
        # Every one of the 53 bones is exported: `export_def_bones=True` would
        # drop the non-deform ones, and the Godot-side assert (and the humanoid
        # bone map) want the whole game_engine rig.
        export_def_bones=False,
        export_vertex_color='ACTIVE',
        export_all_vertex_colors=False,
        export_texcoords=False,
        export_materials='NONE',
        export_image_format='NONE',
        export_animations=False,
    )
    obj.data.calc_loop_triangles()
    tris = len(obj.data.loop_triangles)
    size = os.path.getsize(path)
    log("wrote %s (%d tris, %d bones, %d bytes)"
        % (os.path.basename(path), tris, len(armature.data.bones), size))
    return tris, size


def assert_no_multires(objs):
    for obj in objs:
        for mod in getattr(obj, "modifiers", []):
            if mod.type == 'MULTIRES':
                raise AssertionError("%s carries a MULTIRES modifier" % obj.name)


def build(hero):
    row = HEROES[hero]
    enable_mpfb()
    clear_scene()

    human, joints = build_human(row)
    armature = add_rig(human)
    report_weights(human, armature, "basemesh (pre-convert)")

    obj = bake_to_plain_mesh(human, armature)
    decimate(obj, row["tri_target"])
    m = reframe(obj, armature, row["height"])
    tj = {name: m @ p for name, p in joints.items()}
    log("joints (game frame):", {k: tuple(round(c, 4) for c in v) for k, v in tj.items()})

    # The two asserts the lane keeps: the face looks at +Y and the character's
    # LEFT shoulder is at -X, which glTF's (x, z, -y) turns into Godot's -Z and
    # -X — today's heroes' convention (teibi.tscn LeftArm x=-0.18).
    if tj["l-eye"].y <= 0.0 or tj["r-eye"].y <= 0.0:
        raise AssertionError("body facing backwards: eye y=%.4f/%.4f"
                             % (tj["l-eye"].y, tj["r-eye"].y))
    if tj["l-shoulder"].x >= 0.0:
        raise AssertionError("left shoulder not at negative x: %.4f" % tj["l-shoulder"].x)
    log("ASSERT OK: face +Y, joint-l-shoulder x=%.4f (< 0)" % tj["l-shoulder"].x)

    paint_body(obj, tj, row)

    if row["beret"]:
        crown_z = max(v.co.z for v in obj.data.vertices)
        obj = join_rigid(obj, build_beret(row["colours"], crown_z), "head")
    obj = join_rigid(obj, build_eyes(row["colours"], tj["l-eye"], tj["r-eye"]), "head")

    apply_pose_as_rest(armature, obj, ARMS_DOWN_DEG)
    report_weights(obj, armature, "skinned body (beret + eyes joined)")
    assert_no_multires([obj, armature])

    zs = [v.co.z for v in obj.data.vertices]
    log("final body: height %.4f m (z %.4f..%.4f), %d verts"
        % (max(zs) - min(zs), min(zs), max(zs), len(obj.data.vertices)))

    out_dir = os.path.join(OUT_ROOT, row["out_dir"])
    os.makedirs(out_dir, exist_ok=True)
    obj.name = hero.capitalize()
    armature.name = armature.data.name = "Armature"
    tris, _size = export_glb(obj, armature,
                             os.path.join(out_dir, row["stem"] + ".glb"))
    if tris > row["tri_budget"]:
        raise AssertionError("%d tris over the %d budget" % (tris, row["tri_budget"]))
    log("texture bytes: 0 (vertex colours only)")

    blend = os.path.join(out_dir, row["stem"] + ".blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)
    log("wrote %s (%d bytes)" % (os.path.basename(blend), os.path.getsize(blend)))
    log("done")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    heroes = argv or ["teibi"]
    for hero in heroes:
        if hero not in HEROES:
            raise SystemExit("unknown hero %r (have: %s)"
                             % (hero, ", ".join(sorted(HEROES))))
        build(hero)


main()
