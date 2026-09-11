"""ONE skin grade for the whole hero cast, because the render grade is one thing.

Bead godot-test1-z3e.14, owner 2026-09-11 on the face grids: "very white, nothing
can be made out". Imported by everything that paints hero skin — the two Blender
lanes (`spike_z3e_head.py`, `build_hero.py`) and the generators whose bodies those
authored heads sit on (`generate_windman_separate.py`; Primm's left with bead
godot-test1-5u3.6, and `build_hero.py` grades his skinned body instead)
— the same way they all already reach `predator_parts.export_faceted`:

    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from hero_skin import SKIN_GRADE, graded

WHY A FACE NEEDS IT AND A T-SHIRT DOES NOT. The lit toon band is albedo x sun (1.25,
warm) x `tonemap_exposure` 1.05 against `tonemap_white` 1.2, and glow then blooms
everything over `glow_hdr_threshold` 0.85 (the environment in `scenes/main.tscn`). At
the generators' 0.93 skin the lit band lands ABOVE the white point, so a face — one
large, nearly co-planar surface at one angle to the sun — clips to paper white all at
once and takes the nose, the lips, the eye sockets and the cheek volume with it. The
clothes survive the same grade because they are dark (navy, mustard, denim, brick) and
because a sleeve is read by its silhouette, not by its shading.

MEASURED with `scripts/clipped_fraction.py` on `17_head_face`, as the fraction of face
pixels at or over Rec.709 luma 0.97 (Forward+ / gl_compatibility+web):

             before            after
    windman  21.1% / 68.5%     0.00% / 0.00%
    primm    20.9% / 63.4%     0.18% / 1.39%
    teibi    100.0% / 99.8%    0.18% / 0.00%    (the skinned body, build_hero.py)

0.47 IS READ OFF A CURVE, NOT GUESSED. Scaling a head's `albedo_color` at runtime
prices a candidate albedo without a rebuild, and on the web row — the harsher of the
two — effective skin 0.67 gave 51.7% clipped, 0.58 gave 23.1%, 0.47 gave 0.06%. The
shipped number then held on every one of the six cells above.

THE OTHER HALF OF THE FIX IS NOT HERE, and this is the pointer to it. Grading alone
left Windman and Primm at 28% and 34% on the web row, because they are the only meshes
in the cast whose colour is a baked albedo TEXTURE (the owner's variant-A ruling)
rather than vertex colours, and `gl_compatibility` was reading that texture about a
gamma too bright. `ToonShading.style()` now sets `albedo_texture_force_srgb` on that
renderer only — read the comment there, it carries the measurement — which is what
takes those two cells to 0.00% and 1.39%. The two changes are one fix in two halves:
this constant stops the paint being too light for the grade, that flag stops one
renderer lightening it again.

WHAT IS DELIBERATELY NOT GRADED, so nobody reads an omission as an oversight: hair
(0.32 and below is nowhere near the white point, and darkening it closes the gap the
haircut is read by); the eyewear — Windman's cloth band, Primm's goggle frame and lens
— because cloth and glass are not skin and are meant to sit brighter than the face;
`eye_white` at 0.92, which clips and is supposed to (that clip is most of Teibi's 0.2%
Forward+ residual); and the crowd's own copy of the hero palette in `crowd_manager.gd`,
which is out of scope by the owner's 2026-09-06 ruling.
"""

# The one number. Every hero's own palette stays its own — this is the exposure, not
# the paint — so a hero's rows still read as the colour someone picked for him.
SKIN_GRADE = 0.47


def graded(colour):
    """`colour` (rgb or rgba, tuple or list) darkened by `SKIN_GRADE`.

    The alpha, and the sequence type, are preserved: the generators hold their palette
    as lists that trimesh reads as vertex colours, the Blender lanes hold tuples.
    """
    out = [c * SKIN_GRADE for c in colour[:3]] + list(colour[3:])
    return type(colour)(out)
