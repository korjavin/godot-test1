"""
Source of record for the shipped AUTHORED HERO HEADS — beads godot-test1-z3e.2
(Windman, the pilot) and godot-test1-z3e.5 (Primm). NOT part of the build, NOT run
by CI: this script is run by hand to build the authored head assets committed in
assets/models/characters/<hero>_parts/.

Builds ONE hero head from the MPFB2 / MakeHuman basemesh (CC0, owner ruling
2026-09-06: MPFB2/MakeHuman is the ONLY sanctioned source — Hunyuan3D is banned and
Mixamo/Rodin output may not be committed) and writes, for hero <h>:

  <h>_head_authored.glb       smooth normals + a 512^2 baked albedo, UVs, no
                              vertex colours
  <h>_head_authored.blend     the compressed Blender source file

Run:  blender --background --python-exit-code 1 --python scripts/spike_z3e_head.py \\
          -- --hero primm            (default: windman)

EVERY PER-HERO DIFFERENCE IS A `HEROES` ROW and nothing else — the macro sliders,
the face targets, the palette, the painted eyewear stripes and the one height the
head is scaled to. The pipeline below (cut at MakeHuman's neck joint, reframe into
the Head node's local space, decimate, paint, bake, export) is the recipe the owner
picked as VARIANT A on 2026-09-06 and is deliberately identical for every hero.
Adding a hero is a row; it is not a branch.

WHY NOT trimesh like scripts/generate_windman_separate.py: the source is a
MakeHuman basemesh plus MakeHuman morph targets, and MPFB2 is a Blender extension —
the whole point is that this head is authored, not a stack of primitives. Nothing
here touches the shipped generators or their `.glb` paths, so the model-selfcheck
staleness gate cannot see it.

The head's LOCAL FRAME is today's head's, because scenes/characters/<hero>.tscn
hangs it on the same Head node (Body y = 1.62, basis Rx(-90)) and
`PlayerAnimation.GAITS.head_deg` / `capture_rest_pose` rotate that node:
  +Z up, +Y face-forward, origin at the centre of the skull's bounding box.
The generated skull each hero replaces is a scaled icosphere — windman 0.24 x 0.245
x 0.252 m, primm 0.221 x 0.230 x 0.258 m — and a real head is taller than it is
wide, so each one is scaled UNIFORMLY to the same skull height its sphere had and
comes out ~4-5 cm narrower. That mismatch is evidence, not a bug — do not fudge it;
it is the same proportion call the owner deferred on the pilot.
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

TRIS_SMOOTH = 4500             # the bead's "retopo/decimate to ~3-5k"
TEXTURE_SIZE = 512             # owner ruling: <= 512^2 albedo, no normal map

# ============================================================================
# THE HEROES. One row per authored head; the pipeline below reads nothing else.
#
# `palette` is the hero's OWN generator palette, verbatim (generate_<hero>_
# separate.py's `self.colors`), because the authored head sits on a torso that
# generator still builds and a colour seam at the neck would be the first thing
# anyone sees.
#
# `stripes` is the eyewear, painted rather than modelled, listed TOP-DOWN in
# metres relative to the eye landmark; the first stripe containing a vertex wins.
# Both heroes wear something across the eyes and neither wears it as geometry:
# a real face has sockets, and a band pushed proud of them swallows the EARS,
# which are the whole reason this epic exists.
# ============================================================================
HEROES = {
    "windman": {
        # docs/characters/windman.md: male, calm, no beard, slightly rounded face
        # with soft features; the blue-over-red bandage knotted at the back.
        "parts_dir": "windman_parts",
        "target_height": 0.252,     # today's skull, chin to crown
        "macro": (("gender", 0.85), ("age", 0.45), ("muscle", 0.5),
                  ("weight", 0.6), ("caucasian", 1.0), ("african", 0.0),
                  ("asian", 0.0)),
        "targets": ((("head", "head-round.target.gz"), 0.65),
                    (("head", "head-fat-incr.target.gz"), 0.30),
                    (("head", "head-age-decr.target.gz"), 0.25),
                    (("cheek", "l-cheek-volume-incr.target.gz"), 0.35),
                    (("cheek", "r-cheek-volume-incr.target.gz"), 0.35),
                    (("nose", "nose-scale-vert-decr.target.gz"), 0.20),
                    (("chin", "chin-jaw-drop-decr.target.gz"), 0.20)),
        "palette": {"skin": (0.93, 0.74, 0.62, 1.0),
                    "lips": (0.80, 0.55, 0.48, 1.0),
                    "hair": (0.32, 0.20, 0.11, 1.0)},
        "stripes": ((0.004, 0.022, (0.20, 0.38, 0.75, 1.0)),    # blue over red,
                    (-0.024, 0.004, (0.72, 0.18, 0.15, 1.0))),  # as the art has it
        "hair_lift": 0.008,         # short hair as a shell over the scalp, metres
        "hair_front": 0.036,        # hairline above the eye line
        "hair_nape": 0.055,         # how much lower the hairline sits at the back
        # The torso draws a 0.062 m-radius neck cylinder; the stump hides inside it.
        "neck_stump_radius": 0.060,
        # THE ONE OPT-OUT FROM z3e.12's LANDMARK FIX, and it is here to FREEZE
        # SHIPPED ART, not because the basemesh reading is right. Windman's head
        # merged on 2026-09-08 built on the unmorphed joint cubes; his macros move
        # `joint-neck` up by 1.7 cm, so the fixed reading cuts his head in a
        # different place and rebuilds a head ~7% wider for the same skull height.
        # That is a change to a hero the owner has already ruled on, and z3e.12 is
        # a bug about PRIMM — so Windman stays on the old landmarks and his `.glb`
        # stays byte-identical, which is also this bead's regression proof. Flip
        # this to "morphed" (or delete the key) the day the owner wants the
        # corrected Windman, and expect a new grid with it.
        "landmarks": "basemesh",
    },
    "primm": {
        # docs/characters/primm.md: "slim but slightly lean", "slightly elongated
        # face. Eyes sharp and focused; hair short to medium length, dark brown.
        # Wears thin, high-tech goggles across the eyes (transparent lenses with
        # slight blue tint)."
        #
        # BEAD z3e.12, and the whole point of it: the owner looked at the first
        # Primm beside Windman and said "primm looks exactly like windman, same
        # face just without mask". He was right, and the reason was the landmark
        # bug above — the macro sliders had to sit near the basemesh default or
        # the neck cut wandered, so both heroes were built from ONE recipe with
        # different paint. With `morphed` landmarks the sliders are free again,
        # so Primm is now a YOUNGER, LEANER, LONGER-FACED man at the macro level
        # (age 0.30 / weight 0.35 / muscle 0.45 against Windman's 0.45/0.6/0.5)
        # and the targets stack the canon's elongation on top of that rather than
        # doing all the work alone.
        "parts_dir": "primm_parts",
        # primm's generated skull is icosphere(0.115) scaled [0.96, 1.0, 1.12],
        # so chin to crown is 2 * 0.115 * 1.12.
        "target_height": 0.2576,
        "macro": (("gender", 0.90), ("age", 0.30), ("muscle", 0.45),
                  ("weight", 0.35), ("caucasian", 1.0), ("african", 0.0),
                  ("asian", 0.0)),
        "targets": ((("head", "head-oval.target.gz"), 0.80),
                    (("head", "head-scale-vert-incr.target.gz"), 0.50),
                    (("head", "head-fat-decr.target.gz"), 0.60),
                    (("cheek", "l-cheek-bones-incr.target.gz"), 0.50),
                    (("cheek", "r-cheek-bones-incr.target.gz"), 0.50),
                    (("chin", "chin-jaw-drop-incr.target.gz"), 0.40),
                    (("chin", "chin-prominent-incr.target.gz"), 0.40),
                    (("nose", "nose-scale-vert-incr.target.gz"), 0.30),
                    # "Eyes sharp and focused" — narrowed lids, both sides.
                    (("eyes", "l-eye-height2-decr.target.gz"), 0.30),
                    (("eyes", "r-eye-height2-decr.target.gz"), 0.30)),
        # THE ONE PLACE A HERO'S PALETTE LEAVES ITS GENERATOR'S (see the note at
        # the top of the table). Primm's generator skin is Windman's skin to
        # within a rounding error — (0.91, 0.73, 0.62) against (0.93, 0.74, 0.62)
        # — which is half of why the two heads read as one man. This is that tone
        # pulled cooler and paler, and the hair pulled near-black; the seam this
        # risks is against the torso's own neck cylinder, which the 0.048 m stump
        # sits INSIDE and the collar covers.
        "palette": {"skin": (0.90, 0.76, 0.68, 1.0),
                    "lips": (0.76, 0.50, 0.46, 1.0),
                    "hair": (0.18, 0.11, 0.07, 1.0)},
        # A blue lens between two silver frame lines, 5.4 cm of band all told —
        # the height of the generator's own visor slab (a box 0.052 m tall).
        #
        # TWO DEPARTURES FROM THE GENERATOR'S NUMBERS, both measured on the cast
        # row rather than argued: 3.4 cm of band vanished into the blown-out
        # cheek, and so did the generator's pale `visor_lens` (0.66, 0.80, 0.90)
        # even at full height. The generated visor got away with pale because it
        # was a SLAB standing 4 cm proud of a featureless sphere and read by its
        # silhouette; paint on a face with real sockets has no silhouette and
        # must read by contrast alone. This lens is that pale blue pulled toward
        # Windman's bandage blue (0.20, 0.38, 0.75), which is the one piece of
        # painted eyewear in the cast already proven to read at 3 m — still the
        # canon's "slight blue tint", dark enough to survive the grade.
        "stripes": ((0.021, 0.027, (0.70, 0.72, 0.76, 1.0)),    # silver frame, top
                    (-0.021, 0.021, (0.45, 0.62, 0.85, 1.0)),   # blue lens
                    (-0.027, -0.021, (0.70, 0.72, 0.76, 1.0))),  # frame, bottom
        # A DIFFERENT SILHOUETTE FROM WINDMAN'S CROP (0.008 / 0.036 / 0.055), and
        # the difference is the HAIRLINE, not the length: docs/characters/primm.png
        # is short hair swept back off a high forehead with the sides above the
        # ears, where Windman's fringe comes down to the brow. So Primm's hairline
        # sits 1.4 cm higher (0.050 against 0.036) with more volume on the crown to
        # carry the sweep. A first pass at "short to MEDIUM length" put the nape at
        # 0.090 and rendered a bowl cut that covered the temples — the canon's
        # picture wins over its prose here, and the nape stays short.
        "hair_lift": 0.012,
        "hair_front": 0.050,
        "hair_nape": 0.060,
        # Primm's torso neck is the SLIM one, radius 0.050 — a 0.060 stump would
        # poke out of his collar where it hides inside Windman's.
        "neck_stump_radius": 0.048,
    },
}


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


def morphed_coords(obj):
    """Object-space vertex coordinates WITH every macro and target applied.

    `obj.data.vertices[i].co` is the UNMORPHED basemesh: MPFB2 applies macros and
    targets as shape keys, and a shape key does not move `vertex.co`. Evaluating
    the object as it stands does not help either — the helper MASK modifier deletes
    the `joint-*` cubes, which are exactly the landmarks we are here for. So the
    modifiers are switched off for the length of one depsgraph update: the evaluated
    mesh is then the basemesh plus its shape keys, in the same order, so index `i`
    still names the same vertex as `obj.data.vertices[i]` — which is where the
    vertex GROUPS stay readable. The equal-length assert is that guarantee's fence.
    """
    disabled = [m for m in obj.modifiers if m.show_viewport]
    for mod in disabled:
        mod.show_viewport = False
    try:
        bpy.context.view_layer.update()
        evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        mesh = evaluated.to_mesh()
        if len(mesh.vertices) != len(obj.data.vertices):
            raise AssertionError(
                "evaluated mesh has %d verts, basemesh %d: a modifier is still "
                "changing the topology and the vertex groups no longer line up"
                % (len(mesh.vertices), len(obj.data.vertices)))
        coords = [v.co.copy() for v in mesh.vertices]
        evaluated.to_mesh_clear()
    finally:
        for mod in disabled:
            mod.show_viewport = True
    return coords


def joint_centroid(obj, group_name, coords):
    """Centre of one of the basemesh's helper JOINT CUBES, in object space. This is
    how the neck cut and the eye line are found: they are MakeHuman's own landmarks,
    not numbers guessed off a bounding box.

    Group MEMBERSHIP comes from `obj.data` (the only place it lives) and the
    POSITION from `coords` — `morphed_coords`'s evaluated copy, so the landmark
    tracks the macro sliders instead of the basemesh they morphed away from."""
    idx = obj.vertex_groups[group_name].index
    acc = Vector((0.0, 0.0, 0.0))
    n = 0
    for v in obj.data.vertices:
        for g in v.groups:
            if g.group == idx:
                acc += coords[v.index]
                n += 1
                break
    if n == 0:
        raise ValueError("empty vertex group " + group_name)
    return acc / n


def build_human(cfg):
    HumanService = dyn("mpfb.services.humanservice", "HumanService")
    TargetService = dyn("mpfb.services.targetservice", "TargetService")
    LocationService = dyn("mpfb.services.locationservice", "LocationService")
    HumanObjectProperties = dyn("mpfb.entities.objectproperties", "HumanObjectProperties")

    human = HumanService.create_human(mask_helpers=True, detailed_helpers=True,
                                      extra_vertex_groups=True)
    # The hero's own `macro` row, then its `targets` row on top: macro first
    # because `reapply_macro_details` re-derives the basemesh from the sliders and
    # would wipe a face target loaded before it.
    for key, value in cfg["macro"]:
        HumanObjectProperties.set_value(key, value, entity_reference=human)
    TargetService.reapply_macro_details(human)

    targets_root = LocationService.get_mpfb_data("targets")
    for rel, weight in cfg["targets"]:
        path = os.path.join(targets_root, *rel)
        if not os.path.exists(path):
            log("target missing, skipped:", path)
            continue
        TargetService.load_target(human, path, weight=weight)

    # THE MACRO TRAP, paid for on 2026-09-11 building Primm (bead z3e.5) and FIXED
    # on 2026-09-11 by bead z3e.12. The landmarks used to be read straight off
    # `human.data.vertices` — the UNMORPHED basemesh — so every macro slider that
    # moves the skeleton (`age` above all, then `weight`) slid the real head away
    # from them while the numbers stayed frozen. At age 0.35 the cut ran 10 cm
    # high: it sliced the skull in half, `reframe` scaled the remainder up 1.86x,
    # and the run still exited 0 with a plausible-looking log. That constraint —
    # "keep every hero's macro near the basemesh default" — is what made Primm's
    # head Windman's head with a different hat, which is the bug z3e.12 opened on.
    #
    # `morphed_coords` reads the SAME joint cubes off the evaluated (shape-keyed)
    # mesh, so a hero's macros may now move the skull and the cut still lands at
    # the neck. `reframe`'s scale assert stays as the regression fence: it is the
    # one number that shows a cut landing somewhere the landmark is not.
    #
    # `landmarks` is the row key that freezes shipped art built before the fix —
    # today only Windman's, and his row says why. A new hero omits it.
    if cfg.get("landmarks", "morphed") == "basemesh":
        coords = [v.co.copy() for v in human.data.vertices]
    else:
        coords = morphed_coords(human)
    neck = joint_centroid(human, "joint-neck", coords)
    eye = joint_centroid(human, "joint-l-eye", coords)
    log("landmarks: neck z=%.4f  eye z=%.4f y=%.4f" % (neck.z, eye.z, eye.y))
    return human, neck, eye


def bake_to_plain_mesh(obj):
    """Apply the helper MASK modifier and every macro/target shape key in one go —
    the evaluated mesh is both."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target='MESH')
    return bpy.context.view_layer.objects.active


def cut_head(obj, neck, chin_z, stump_radius):
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
                and Vector((v.co.x - neck.x, v.co.y - neck.y)).length > stump_radius:
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


def reframe(obj, chin_z, target_height):
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
    # the height the skull is allowed. `chin_z` is where the head ENDS — MPFB2's own
    # `joint-neck` landmark, the height the first draft cut at — so the stump below it
    # hangs past the origin and into the torso's collar and costs the skull nothing.
    # Measuring the chin off the geometry instead (lowest vertex on the face side)
    # found the base of the throat and scaled the whole head down by a quarter.
    crown = max(v.co.z for v in me.vertices)
    chin = chin_z
    scale = target_height / (crown - chin)
    # THE TRIPWIRE for `build_human`'s macro trap: a head cut at a landmark the
    # morph has walked away from is still a closed, exportable, entirely wrong
    # mesh, and the only number that shows it is this one. A sane build lands
    # near 1.0 (windman 1.044, primm 1.02) because both skulls are scaled to the
    # height of the icosphere they replace; the half-a-skull that this bead
    # caught came out at 1.86.
    if not 0.8 <= scale <= 1.3:
        raise AssertionError(
            "reframe scale %.3f is out of band: the crown is %.3f m above the "
            "chin landmark, which is not a head. Almost certainly a macro slider "
            "(age, weight) moved the mesh away from the unmorphed joint cubes — "
            "see build_human's comment." % (scale, crown - chin))
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


def paint(obj, eye_z, cfg):
    """The hero's face, as regions of ITS OWN generator palette.

    THE EYEWEAR IS COLOUR AND NOT GEOMETRY, deliberately: today's head is a sphere
    with no eye sockets, so Windman's blindfold had to stand proud of the skull to
    cover anything and Primm's visor was a box slab in front of one. A real face has
    sockets, and a band pushed out over them would swallow the EARS — which are the
    whole reason this bead exists ("a face with ears"). `cfg["stripes"]` is that band,
    top-down in metres about the eye landmark; first match wins.

    THE HAIR IS BOTH: colour plus a small outward lift of the scalp, because a short
    haircut has a silhouette and a painted skull does not. The lift stops well above
    the ears.
    """
    me = obj.data
    palette = cfg["palette"]
    stripes = cfg["stripes"]
    hair_lift = cfg["hair_lift"]

    hair_front = eye_z + cfg["hair_front"]
    hair_nape = cfg["hair_nape"]
    lip_z = eye_z - 0.088
    half_depth = max(abs(v.co.y) for v in me.vertices)

    def region(co):
        # The hairline sits lower at the BACK than at the brow — a haircut, not a cap.
        depth = co.y / max(half_depth, 1e-6)          # +1 nose, -1 nape
        hair_z = hair_front - hair_nape * max(0.0, -depth)
        if co.z >= hair_z:
            return "hair"
        for i, (low, high, _colour) in enumerate(stripes):
            if eye_z + low <= co.z <= eye_z + high:
                return i
        if lip_z - 0.016 <= co.z <= lip_z + 0.012 and depth > 0.55:
            return "lips"
        return "skin"

    colours = {"hair": palette["hair"], "lips": palette["lips"],
               "skin": palette["skin"]}
    for i, (_low, _high, colour) in enumerate(stripes):
        colours[i] = colour
    per_vert = [region(v.co) for v in me.vertices]

    # The hair shell. Lift along the vertex normal so the volume follows the skull;
    # taper it at the hairline so there is no step where hair meets forehead.
    me.calc_loop_triangles()
    normals = [v.normal.copy() for v in me.vertices]
    for i, v in enumerate(me.vertices):
        if per_vert[i] != "hair":
            continue
        taper = min(1.0, (v.co.z - (hair_front - 0.06)) / 0.05)
        v.co += normals[i] * (hair_lift * max(0.0, taper))
    me.update()

    attr = me.color_attributes.new(name="Color", type='FLOAT_COLOR', domain='POINT')
    for i, name in enumerate(per_vert):
        attr.data[i].color = colours[name]
    # The glTF exporter writes the ACTIVE colour attribute and nothing else.
    me.color_attributes.active_color = attr
    me.attributes.active_color = attr
    counts = {k: per_vert.count(k) for k in colours}
    log("painted:", counts)


def bake_albedo(obj, hero):
    """Bake the vertex colours into one 512^2 albedo on the MakeHuman UV layout.

    Variant A is "the realistic head as the code ships it", and what makes a realistic
    head realistic is a texture — so A gets a real one and a real byte count, capped
    at the owner's 512^2 with no normal map. Cycles + an Emission fed by the colour
    attribute is the cheapest honest bake: it is the vertex colours, resampled, with
    no lighting baked in.
    """
    img = bpy.data.images.new("%s_head_albedo" % hero, TEXTURE_SIZE, TEXTURE_SIZE,
                              alpha=False)
    mat = bpy.data.materials.new("%s_head_authored" % hero)
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


def parse_hero():
    """`blender ... --python this.py -- --hero primm`. Blender swallows everything
    before the bare `--`, so only what follows it is ours."""
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    hero = "windman"
    if "--hero" in argv:
        hero = argv[argv.index("--hero") + 1]
    if hero not in HEROES:
        raise SystemExit("unknown hero %r; known: %s"
                         % (hero, ", ".join(sorted(HEROES))))
    return hero


def main():
    hero = parse_hero()
    cfg = HEROES[hero]
    out_dir = os.path.join(REPO, "assets", "models", "characters", cfg["parts_dir"])
    out_glb = os.path.join(out_dir, "%s_head_authored.glb" % hero)
    log("building the %s head -> %s" % (hero, out_glb))

    enable_mpfb()
    clear_scene()

    human, neck, eye = build_human(cfg)
    obj = bake_to_plain_mesh(human)
    cut_head(obj, neck, neck.z + 0.012, cfg["neck_stump_radius"])
    scale, centre = reframe(obj, neck.z + 0.012, cfg["target_height"])

    # The landmarks travel with the mesh through reframe() — the 180-degree turn
    # included, which is why the y is negated here too.
    eye_z = eye.z * scale - centre.z
    eye_y = -eye.y * scale - centre.y
    log("eye landmark in head space: y=%.4f (must be > 0, the FACE side) z=%.4f"
        % (eye_y, eye_z))
    if eye_y <= 0.0:
        raise AssertionError("head is facing backwards: eye y=%.4f" % eye_y)

    decimate(obj, TRIS_SMOOTH)
    paint(obj, eye_z, cfg)

    img = bake_albedo(obj, hero)
    # Variant A's colour comes from the texture; leaving COLOR_0 on would multiply
    # the two and darken the whole head.
    while obj.data.color_attributes:
        obj.data.color_attributes.remove(obj.data.color_attributes[0])
    export(obj, out_glb, flat=False)

    # THE SIDECAR, written HERE and not by the exporter, and AFTER the export on
    # purpose: `export_format='GLB'` EMBEDS the albedo, and giving the image a
    # `filepath` before the export puts that name in the .glb and moves 24 bytes.
    # So nothing drops a readable copy beside the model, and the copy
    # PROVENANCE.md promises "as the readable source of the bake" was a fossil
    # from an earlier export that quietly rotted — bead z3e.12 found Primm's still
    # showing the z3e.5 palette next to a .glb built from a new one. Nothing in
    # the game loads it; it is written so the row stays true.
    sidecar = os.path.join(out_dir, "%s_head_authored_%s.png" % (hero, img.name))
    img.filepath_raw = sidecar
    img.file_format = 'PNG'
    img.save()
    log("wrote %s (%d bytes)" % (os.path.basename(sidecar), os.path.getsize(sidecar)))

    for o in bpy.data.objects:
        for m in o.modifiers:
            if m.type == 'MULTIRES':
                raise AssertionError("Object %s carries MULTIRES modifier" % o.name)
    for attr in obj.data.attributes:
        if "sculpt" in attr.name.lower() or "multires" in attr.name.lower():
            raise AssertionError("obj.data has sculpt/multires layer %s" % attr.name)
    if hasattr(obj.data, "sculpt_vertex_colors") and obj.data.sculpt_vertex_colors:
        raise AssertionError("obj.data has sculpt_vertex_colors")

    out_blend = os.path.join(out_dir, "%s_head_authored.blend" % hero)
    bpy.ops.wm.save_as_mainfile(filepath=out_blend, compress=True)
    log("wrote %s (%d bytes)" % (os.path.basename(out_blend), os.path.getsize(out_blend)))
    log("done")


if __name__ == "__main__":
    main()
