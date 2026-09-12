# Cloth that reads as cloth — the FINDINGS

Bead `godot-test1-td8`, a SPIKE THAT MERGES. Owner, 2026-09-12: *"Shirts and clothing
look painted, not natural — just colour on the heroes. Can we make the clothing look
more natural?"*

Subject: **Teibi**, polo + trousers, the plainest garments in the cast. Renderer: the
web one (`--rendering-method gl_compatibility` **plus** the `web` argument, which is what
makes `_emulate_web_settings` resolve the `.web` project overrides a desktop binary
otherwise never sees). Rows: `18_body_3m` — the GAMEPLAY distance, and the row the
decision is actually made on — and `20_torso_1m`, the control that says whether a
column's detail exists at all or only exists at 3 m as a smudge.

* the grid — `grid_27_cloth_spike.png`
* the stride strips — `grid_27_cloth_stride_a.png`, `grid_27_cloth_stride_all.png`

## What each column costs

| column | what it is | tris | Δ tris | glb bytes | texture bytes |
|---|---|---:|---:|---:|---:|
| today | the shipped hero — the control | 13,872 | — | 453,116 | 0 |
| A | folds as geometry | 21,742 | **+57%** | 704,968 | 0 |
| B | AO + cavity baked into the vertex colours | 13,872 | **+0%** | 453,116 | 0 |
| C | 512² fabric albedo on unwrapped shells | — | — | — | **not built — time** |
| D | garments on their own Burley material | 13,872 | +0% | 466,768 | 0 |
| all | A + B + D | 21,742 | +57% | 725,888 | 0 |

`[PERF]` on the SHIPPED path is **unchanged by construction and not by measurement**:
`teibi_skinned.glb` and `teibi_skinned.blend` are byte-identical on this branch (`git
diff` is empty and `build_hero.py --all --check` still says CHECK OK), no `.tscn` was
repointed, and the one Godot-side change (`toon_shading.gd`) is a branch on a material
NAME that the shipped export cannot produce — `export_materials='NONE'`. Every column's
own frame cost is unmeasured; that reading belongs to the rollout bead, on whichever
column the owner picks, on a debug web export.

**The four scratch `.glb` are 1.53 MB of imported resources, and they do NOT ship.** Godot
packs by resource and not by reference, so the Web preset's `exclude_filter` names them
(`export_presets.cfg`) — otherwise a spike nothing loads would still have cost a ~20%
increase in the web download, on the platform CLAUDE.md names as the performance target.

## What reads at 3 m, and what only reads at 1 m

Measured on the rendered PNGs: mean luma and standard deviation over a fixed crop — the
polo panel at 1 m, the whole hero at 3 m. **The standard deviation is the number that
matters**: it is how much variation there is across the crop, i.e. whether anything reads
as a fold at all. A flat painted panel has a low one; that is the owner's complaint
expressed as a number.

| column | 1 m torso: mean | 1 m torso: **sd** | 3 m hero: mean | 3 m hero: **sd** |
|---|---:|---:|---:|---:|
| today | 78.9 | 9.38 | 86.5 | 9.91 |
| A | 78.9 | 9.28 (**−1%**) | 86.4 | 9.91 (**±0%**) |
| B | 78.3 | 9.75 (+4%) | 86.4 | 9.93 (+0.2%) |
| D | 71.6 | 13.00 (**+39%**) | 85.6 | 10.98 (**+11%**) |
| all | 71.2 | 13.27 (+41%) | 85.5 | 11.02 (+11%) |

**A (folds) alone is the surprise, and it is the bead's own hypothesis confirmed the hard
way.** The geometry is there — the 1 m frame shows the crease bands, and the stride strip
shows them deforming with the body without tearing — but under the cast's shading the
variation it adds is **zero**: sd 9.28 against the control's 9.38 at 1 m, and 9.91 against
9.91 at 3 m, identical to three significant figures. `DIFFUSE_TOON` is why. Its two bands
are a lighting THRESHOLD, so a 6 mm crease either falls entirely inside one band (nothing
happens) or straddles the step (a hard edge that does not read as cloth). **Folds under
toon shading are 57% more triangles for no picture.**

**And the `all` column is the other half of that sentence.** Put the same folds under
`DIFFUSE_BURLEY` and they appear — the 1 m `all` frame is the only one in the grid with
cloth-looking creases across the chest and the sleeve, and it is the same geometry column
A already had. So the finding is not "folds do not work", it is **"folds do not exist
under a two-band toon diffuse"**. What they cost is still 57% more triangles, and what
they buy is still almost nothing you can measure at 3 m (`all` 11.02 against D's 10.98).

**B (the bake) is now honest and now small.** The cavity term darkens only genuine
concave geometry — the collar, the armpit, the waistband groove — which on a garment shell
that is convex nearly everywhere is not many vertices: the build log reports a median
darkening of 1.000 and a minimum of 0.315. +4% variation at 1 m, +0.2% at 3 m, for zero
triangles and zero bytes. It is real, it is free, and on its own it does not answer the
owner. (An earlier build of this bead had the curvature sign inverted and darkened convex
RIDGES instead of valleys, which made B look slightly better for entirely the wrong
reason; the numbers above are after the fix.)

**D (the cloth material) is the only column that changes the 3 m frame** — +11% variation
there and +39% at 1 m, and it is visible without measuring: the polo finally has a lit
side and a shadow side that fall off smoothly instead of stepping. That is what
`DIFFUSE_BURLEY` buys. Godot's toon diffuse has **no band count to raise** (the bead
asked; there is no such property on `BaseMaterial3D`, the step is fixed in the shader), so
the middle ground if the owner wants the cast's flatness kept is `DIFFUSE_LAMBERT_WRAP`,
one enum away in `ToonShading.style_cloth`.

### The one confound left in D, stated plainly

D's and `all`'s **cloth reads darker** than the control's — the trousers most obviously.
The mean-luma column is therefore not comparable for those two; the `sd` column is what
the argument rests on.

The cause is **not** the material's own parameters: `split_cloth_material` now writes a
plain white base colour at roughness 1.0 with back-face culling on, which is exactly
Godot's importer default for a mesh with no material, and the exported glTF carries no
`baseColorFactor`, no `roughnessFactor` and no `doubleSided` — verified in the committed
bytes. (An earlier build of this bead left Blender's Principled defaults in place — 0.8
grey at roughness 0.5, double-sided — which multiplied the WHOLE body by 0.8 and is what
darkened Teibi's face and hands in the first grid. That is fixed and the skin is now
identical to the control's.)

What is left is the vertex-colour attribute itself: exporting a material at all changes
how Godot's glTF importer treats `COLOR_0`, and the garments' own colour comes back a
stop down. **Anyone rolling D out must settle that colour space first** — and it is now a
one-variable question, because everything else about the material has been ruled out by
construction.

## The recommended pick

**D + B, and not A.** Concretely: give the garments their own material
(`ToonShading.style_cloth` — Burley, roughness 1.0, no rim) and bake the occlusion and
cavity into the vertex colours that material shades. That pair is the only combination in
this grid that moves the **3 m** frame, which is the frame the game is played at, and it
costs **zero triangles and zero texture bytes** — it stays inside the owner's
vertex-colour ruling and adds 14 KB to a hero.

Against it, and the owner should weigh it: D takes the cast off `DIFFUSE_TOON` for
garments, which is the `y1o.22` ruling. This bead does not ship that — the grid is the
argument, the ruling is the owner's. And the colour-space confound above has to be closed
before it goes anywhere near a shipped hero.

A is a real technique that only becomes visible **on top of D**, and even then only at
1 m — so the honest version is "folds are a close-up feature, this game has no close-ups,
and 57% more triangles is the price of the ones nobody sees." If the owner likes what the
`all` column's chest does, that is the argument for reviving A later, on a tuned
triangle budget.

## Deferred, and why

* **Column C — the 512² fabric albedo with weave and seam stitching on UV-unwrapped
  shells: NOT BUILT.** It is the one column needing a UV layout, a bake target and the
  lane's first texture byte, and the spike ran out of clock. Nothing here approximates it.
  It is also the column most likely to be worth building next, because a weave is the one
  kind of detail that survives distance by being high-frequency — and because B could be
  baked INTO it, making C strictly additive over B as the bead intended.
* **A's triangle cost was not tuned.** +57% against the bead's estimated +15-25%, and
  6,242 tris over the shipped `TRI_BUDGET`. The band-limited subdivide in `fold_garments`
  cuts too wide a window (`FOLD_BAND * 1.4` around three joints). If A is ever revived,
  that is the first knob.
* **The D colour-space question** above — one variable, not yet answered.
* **No Forward+ row**, and no per-column `[PERF]` reading. Both were cut for time; the
  shipped path's zero-delta is argued from construction, not measured.
