"""
SPIKE ONLY — bead godot-test1-z3e.1. NOT part of the build, NOT run by CI, and this
branch is never merged.

Builds ONE Windman head from the MPFB2 / MakeHuman basemesh (CC0, owner ruling
2026-09-06: MPFB2/MakeHuman is the ONLY sanctioned source — Hunyuan3D is banned and
Mixamo/Rodin output may not be committed) and writes the two meshes the spike needs:

  windman_head_authored.glb       smooth normals + a 512^2 baked albedo, UVs, no
                                  vertex colours   -> variants A and B
  windman_head_authored_flat.glb  the same head decimated further, FLAT (per-face)
                                  normals, vertex colours, no texture -> variant C

Run:  blender --background --python-exit-code 1 --python scripts/spike_z3e_head.py

WHY NOT trimesh like scripts/generate_windman_separate.py: the source is a
MakeHuman basemesh plus MakeHuman morph targets, and MPFB2 is a Blender extension —
the whole point is that this head is authored, not a stack of primitives. Nothing
here touches the shipped generators or their `.glb` paths, so the model-selfcheck
staleness gate cannot see it.

The head's LOCAL FRAME is today's head's, because scenes/characters/windman_updated.tscn
hangs it on the same Head node (Body y = 1.62, basis Rx(-90)) and
`PlayerAnimation.GAITS.head_deg` / `capture_rest_pose` rotate that node:
  +Z up, +Y face-forward, origin at the centre of the skull's bounding box.
Today's skull is 0.24 x 0.245 x 0.252 m (a scaled icosphere); a real head is taller
than it is wide, so this one is scaled UNIFORMLY to the same 0.252 m height and comes
out narrower. That mismatch is evidence, not a bug — do not fudge it.
"""

import math
import os
import sys

import addon_utils
import bmesh
import bpy
import importlib
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO, "assets", "models", "characters", "windman_parts")
OUT_SMOOTH = os.path.join(OUT_DIR, "windman_head_authored.glb")
OUT_FLAT = os.path.join(OUT_DIR, "windman_head_authored_flat.glb")

# scripts/generate_windman_separate.py's palette, verbatim — the spike head has to
# sit on the shipped torso without a colour seam.
SKIN = (0.93, 0.74, 0.62, 1.0)
LIPS = (0.80, 0.55, 0.48, 1.0)
HAIR = (0.32, 0.20, 0.11, 1.0)
BAND_BLUE = (0.20, 0.38, 0.75, 1.0)
BAND_RED = (0.72, 0.18, 0.15, 1.0)

TARGET_HEIGHT = 0.252          # today's skull, chin to crown
TRIS_SMOOTH = 4500             # the bead's "retopo/decimate to ~3-5k"
TRIS_FLAT = 2400               # the bead's "~2-3k" for the faceted variant
TEXTURE_SIZE = 512             # owner ruling: <= 512^2 albedo, no normal map
HAIR_LIFT = 0.008              # short hair as a shell over the scalp, in metres
# The torso already draws a 0.062 m-radius neck cylinder; the stump hides inside it.
NECK_STUMP_RADIUS = 0.060


def log(*a):
    print("[SPIKE]", *a)
    sys.stdout.flush()


def enable_mpfb():
    target = "bl_ext.blender_org.mpfb"
    addon_utils.enable(target, default_set=True, persistent=True)
    importlib.import_module(target)


def dyn(module_suffix, key):
    """MPFB2's own script-sample quirk: an extension's absolute package name is not
    knowable at write time, so find the loaded module by suffix."""
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
    """Centre of one of the basemesh's helper JOINT CUBES, in object space. This is
    how the neck cut and the eye line are found: they are MakeHuman's own landmarks,
    not numbers guessed off a bounding box."""
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


def build_human():
    HumanService = dyn("mpfb.services.humanservice", "HumanService")
    TargetService = dyn("mpfb.services.targetservice", "TargetService")
    LocationService = dyn("mpfb.services.locationservice", "LocationService")
    HumanObjectProperties = dyn("mpfb.entities.objectproperties", "HumanObjectProperties")

    human = HumanService.create_human(mask_helpers=True, detailed_helpers=True,
                                      extra_vertex_groups=True)
    # docs/characters/windman.md: male, calm, no beard, slightly rounded face with
    # soft features. Macro first, then the face-shape targets on top.
    for key, value in (("gender", 0.85), ("age", 0.45), ("muscle", 0.5),
                       ("weight", 0.6), ("caucasian", 1.0), ("african", 0.0),
                       ("asian", 0.0)):
        HumanObjectProperties.set_value(key, value, entity_reference=human)
    TargetService.reapply_macro_details(human)

    targets_root = LocationService.get_mpfb_data("targets")
    for rel, weight in (
            (("head", "head-round.target.gz"), 0.65),
            (("head", "head-fat-incr.target.gz"), 0.30),
            (("head", "head-age-decr.target.gz"), 0.25),
            (("cheek", "l-cheek-volume-incr.target.gz"), 0.35),
            (("cheek", "r-cheek-volume-incr.target.gz"), 0.35),
            (("nose", "nose-scale-vert-decr.target.gz"), 0.20),
            (("chin", "chin-jaw-drop-decr.target.gz"), 0.20),
    ):
        path = os.path.join(targets_root, *rel)
        if not os.path.exists(path):
            log("target missing, skipped:", path)
            continue
        TargetService.load_target(human, path, weight=weight)

    neck = joint_centroid(human, "joint-neck")
    eye = joint_centroid(human, "joint-l-eye")
    log("landmarks: neck z=%.4f  eye z=%.4f y=%.4f" % (neck.z, eye.z, eye.y))
    return human, neck, eye


def bake_to_plain_mesh(obj):
    """Apply the helper MASK modifier and every macro/target shape key in one go —
    the evaluated mesh is both."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target='MESH')
    return bpy.context.view_layer.objects.active


def cut_head(obj, neck, chin_z):
    """Delete everything below the neck joint and cap the hole.

    THE CUT IS WELL BELOW the joint cube's centre and that is deliberate. The shipped
    torso's neck cylinder tops out at world y = 1.375 while the Head node's origin is
    at 1.62, so ANY head of today's 0.252 m height leaves a 12 cm gap — today's sphere
    hides it by being 0.24 m wide, and a realistically narrow head does not. The stump
    below the chin hangs into that gap and inside the collar; `reframe` scales and
    centres on the SKULL alone, so keeping it costs the head no height."""
    cut_z = neck.z - 0.030
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    doomed = [v for v in bm.verts if v.co.z < cut_z]
    # AND THE STUMP IS TRIMMED TO A COLUMN. 3 cm below MPFB2's neck joint the basemesh
    # has already flared into the trapezius: keeping the whole slab gave the "head" a
    # 0.365 m span, wider than the shipped torso's own shoulders. Everything below the
    # chin further than a neck's radius from the neck joint's axis goes.
    for v in bm.verts:
        if v.co.z >= cut_z and v.co.z < chin_z \
                and Vector((v.co.x - neck.x, v.co.y - neck.y)).length > NECK_STUMP_RADIUS:
            doomed.append(v)
    bmesh.ops.delete(bm, geom=doomed, context='VERTS')
    # One flat cap over the neck stump. It is never seen (the torso's neck is inside
    # it) but an open mesh reads as a hole from below and confuses normal generation.
    boundary = [e for e in bm.edges if e.is_boundary]
    if boundary:
        bmesh.ops.holes_fill(bm, edges=boundary, sides=0)
    bm.to_mesh(me)
    bm.free()
    me.update()
    log("after neck cut: %d verts %d polys" % (len(me.vertices), len(me.polygons)))
    return cut_z


def reframe(obj, chin_z):
    """Move the head into today's head's local frame and scale it to the same height.

    THE TURN IS REAL AND MEASURED, not folklore: MPFB2 puts the `joint-l-eye` cube at
    a NEGATIVE object-space Y, so the basemesh faces -Y, while today's head faces +Y
    (`generate_windman_separate.py` puts the bandage knot at y = -0.122, at the back).
    So the head is turned 180 degrees about Z — both x and y negated, which keeps the
    handedness. `main()` prints the eye landmark's final coordinates and both facts
    are asserted there, because getting this wrong renders a perfectly good head from
    behind and nothing anywhere errors."""
    me = obj.data
    for v in me.vertices:
        v.co.y = -v.co.y
        v.co.x = -v.co.x
    # CROWN TO CHIN, not crown to stump: the neck stump the cut kept must not eat into
    # the 0.252 m the skull is allowed. `chin_z` is where the head ENDS — MPFB2's own
    # `joint-neck` landmark, the height the first draft cut at — so the stump below it
    # hangs past the origin and into the torso's collar and costs the skull nothing.
    # Measuring the chin off the geometry instead (lowest vertex on the face side)
    # found the base of the throat and scaled the whole head down by a quarter.
    crown = max(v.co.z for v in me.vertices)
    chin = chin_z
    scale = TARGET_HEIGHT / (crown - chin)
    for v in me.vertices:
        v.co *= scale
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    centre = Vector(((min(xs) + max(xs)) / 2.0,
                     (min(ys) + max(ys)) / 2.0,
                     (crown + chin) * scale / 2.0))
    for v in me.vertices:
        v.co -= centre
    me.update()
    zs = [v.co.z for v in me.vertices]
    log("reframed: scale %.4f, skull %.3f, extents %.3f x %.3f x %.3f (z %.3f..%.3f)"
        % (scale, (crown - chin) * scale, max(xs) - min(xs), max(ys) - min(ys),
           max(zs) - min(zs), min(zs), max(zs)))
    return scale, centre


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


def paint(obj, eye_z, eye_y):
    """Windman's face, as regions of the shipped palette.

    THE BANDAGE IS COLOUR AND NOT GEOMETRY, deliberately: today's head is a sphere
    with no eye sockets, so its blindfold had to stand proud of the skull to cover
    anything. A real face has sockets, and a band pushed out over them would swallow
    the EARS — which are the whole reason this bead exists ("a face with ears").

    THE HAIR IS BOTH: colour plus a small outward lift of the scalp, because a short
    haircut has a silhouette and a painted skull does not. The lift stops well above
    the ears.
    """
    me = obj.data
    zs = [v.co.z for v in me.vertices]
    top = max(zs)

    band_top = eye_z + 0.022      # just above the eyebrows
    band_mid = eye_z + 0.004      # blue over red, as the reference art has it
    band_bottom = eye_z - 0.024   # just below the eye
    hair_front = band_top + 0.014
    lip_z = eye_z - 0.088
    half_depth = max(abs(v.co.y) for v in me.vertices)

    def region(co):
        # The hairline sits lower at the BACK than at the brow — a haircut, not a cap.
        depth = co.y / max(half_depth, 1e-6)          # +1 nose, -1 nape
        hair_z = hair_front - 0.055 * max(0.0, -depth)
        if co.z >= hair_z:
            return "hair"
        if band_bottom <= co.z <= band_top:
            return "blue" if co.z >= band_mid else "red"
        if lip_z - 0.016 <= co.z <= lip_z + 0.012 and depth > 0.55:
            return "lips"
        return "skin"

    colours = {"hair": HAIR, "blue": BAND_BLUE, "red": BAND_RED,
               "lips": LIPS, "skin": SKIN}
    per_vert = [region(v.co) for v in me.vertices]

    # The hair shell. Lift along the vertex normal so the volume follows the skull;
    # taper it at the hairline so there is no step where hair meets forehead.
    me.calc_loop_triangles()
    normals = [v.normal.copy() for v in me.vertices]
    for i, v in enumerate(me.vertices):
        if per_vert[i] != "hair":
            continue
        taper = min(1.0, (v.co.z - (hair_front - 0.06)) / 0.05)
        v.co += normals[i] * (HAIR_LIFT * max(0.0, taper))
    me.update()

    attr = me.color_attributes.new(name="Color", type='FLOAT_COLOR', domain='POINT')
    for i, name in enumerate(per_vert):
        attr.data[i].color = colours[name]
    # The glTF exporter writes the ACTIVE colour attribute and nothing else.
    me.color_attributes.active_color = attr
    me.attributes.active_color = attr
    counts = {k: per_vert.count(k) for k in colours}
    log("painted:", counts)


def bake_albedo(obj):
    """Bake the vertex colours into one 512^2 albedo on the MakeHuman UV layout.

    Variant A is "the realistic head as the code ships it", and what makes a realistic
    head realistic is a texture — so A gets a real one and a real byte count, capped
    at the owner's 512^2 with no normal map. Cycles + an Emission fed by the colour
    attribute is the cheapest honest bake: it is the vertex colours, resampled, with
    no lighting baked in.
    """
    img = bpy.data.images.new("windman_head_albedo", TEXTURE_SIZE, TEXTURE_SIZE,
                              alpha=False)
    mat = bpy.data.materials.new("windman_head_authored")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    col = nt.nodes.new("ShaderNodeVertexColor")
    col.layer_name = "Color"
    nt.links.new(col.outputs["Color"], emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img

    obj.data.materials.clear()
    obj.data.materials.append(mat)

    # `bpy.ops.object.bake` writes into the ACTIVE, SELECTED image node of the
    # active object's active material — all three, or it answers "No active image
    # found" with no other clue.
    for other in bpy.data.objects:
        other.select_set(False)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    for node in nt.nodes:
        node.select = False
    tex.select = True
    nt.nodes.active = tex

    bpy.context.scene.render.engine = 'CYCLES'
    bpy.context.scene.cycles.samples = 4
    bpy.context.scene.cycles.use_denoising = False
    bpy.context.scene.render.bake.use_pass_direct = False
    bpy.context.scene.render.bake.use_pass_indirect = False
    bpy.context.scene.render.bake.margin = 8
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.bake(type='EMIT')

    # Re-wire the material to USE the baked image, so the exported glTF carries a
    # base-colour texture rather than a vertex-colour node the exporter ignores.
    nt.nodes.remove(emit)
    nt.nodes.remove(col)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.75
    bsdf.inputs["Metallic"].default_value = 0.0
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    img.pack()
    log("baked %dx%d albedo" % (TEXTURE_SIZE, TEXTURE_SIZE))
    return img


def export(obj, path, flat):
    for o in bpy.data.objects:
        o.select_set(o is obj)
    bpy.context.view_layer.objects.active = obj
    for poly in obj.data.polygons:
        poly.use_smooth = not flat
    obj.data.update()
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        # THE .tscn's Rx(-90) IS AUTHORED AGAINST trimesh's OUTPUT, AND TRIMESH DOES
        # NOT CONVERT: `windman_head.glb`'s POSITION accessor is y in [-0.142, 0.127]
        # and z in [-0.126, 0.158], which is `generate_windman_separate.py`'s own
        # Z-up frame vertex for vertex (y = depth, knot at the back; z = height).
        # Godot then reads the glb verbatim, and the Head node's Rx(-90) is exactly
        # what turns that Z-up model into the Y-up world. So this file must be Z-up
        # too: `export_yup=True` writes glTF's own Y-up convention and lays the head
        # on its back, which is what the first pass of shots photographed.
        export_yup=False,
        export_normals=True,
        export_tangents=False,
        # THE FACETED VARIANT SHIPS COLOR_0 AND NO MATERIAL AT ALL, which is exactly
        # what the trimesh-built `windman_head.glb` beside it does — Godot's glTF
        # importer turns a COLOR_0 with no material into a StandardMaterial3D with
        # `vertex_color_use_as_albedo`, and that is the path the whole shipped cast
        # already renders through.
        export_vertex_color='ACTIVE' if flat else 'NONE',
        export_all_vertex_colors=False,
        export_texcoords=not flat,
        export_materials='NONE' if flat else 'EXPORT',
        export_image_format='NONE' if flat else 'AUTO',
    )
    obj.data.calc_loop_triangles()
    log("wrote %s  (%d tris, %d bytes)"
        % (os.path.basename(path), len(obj.data.loop_triangles),
           os.path.getsize(path)))


def main():
    enable_mpfb()
    clear_scene()

    human, neck, eye = build_human()
    obj = bake_to_plain_mesh(human)
    cut_head(obj, neck, neck.z + 0.012)
    scale, centre = reframe(obj, neck.z + 0.012)

    # The landmarks travel with the mesh through reframe() — the 180-degree turn
    # included, which is why the y is negated here too.
    eye_z = eye.z * scale - centre.z
    eye_y = -eye.y * scale - centre.y
    log("eye landmark in head space: y=%.4f (must be > 0, the FACE side) z=%.4f"
        % (eye_y, eye_z))
    if eye_y <= 0.0:
        raise AssertionError("head is facing backwards: eye y=%.4f" % eye_y)

    decimate(obj, TRIS_SMOOTH)
    paint(obj, eye_z, eye_y)

    # C first: it is the same head with a harsher decimation, and it wants the vertex
    # colours that the A/B bake is about to replace with a texture.
    flat_obj = obj.copy()
    flat_obj.data = obj.data.copy()
    bpy.context.collection.objects.link(flat_obj)
    decimate(flat_obj, TRIS_FLAT)
    export(flat_obj, OUT_FLAT, flat=True)

    bake_albedo(obj)
    # Variant A's colour comes from the texture; leaving COLOR_0 on would multiply
    # the two and darken the whole head.
    while obj.data.color_attributes:
        obj.data.color_attributes.remove(obj.data.color_attributes[0])
    export(obj, OUT_SMOOTH, flat=False)
    log("done")


main()
