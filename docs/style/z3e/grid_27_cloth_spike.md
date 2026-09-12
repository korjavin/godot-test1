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
| D | garments on their own Burley material | 13,872 | +0% | 467,000 | 0 |
| all | A + B + D | 21,742 | +57% | 726,128 | 0 |

`[PERF]` on the SHIPPED path is **unchanged by construction and not by measurement**:
`teibi_skinned.glb` and `teibi_skinned.blend` are byte-identical on this branch (`git
diff` is empty and `build_hero.py --all --check` still says CHECK OK), no `.tscn` was
repointed, and the one Godot-side change (`toon_shading.gd`) is a branch on a material
NAME that the shipped export cannot produce — `export_materials='NONE'`. Every column's
own frame cost is unmeasured; that reading belongs to the rollout bead, on whichever
column the owner picks, on a debug web export.

## What reads at 3 m, and what only reads at 1 m

Measured on the rendered PNGs: mean luma and standard deviation over a fixed crop — the
polo panel at 1 m, the whole hero at 3 m. **The standard deviation is the number that
matters**: it is how much variation there is across the cloth, i.e. whether anything
reads as a fold at all. A flat painted panel has a low one; that is the owner's complaint
expressed as a number.

| column | 1 m torso: mean | 1 m torso: **sd** | 3 m hero: mean | 3 m hero: **sd** |
|---|---:|---:|---:|---:|
| today | 79.9 | 9.08 | 86.5 | 9.86 |
| A | 79.8 | 8.97 (**−1%**) | 86.5 | 9.86 (**±0%**) |
| B | 77.9 | 9.99 (+10%) | 86.4 | 10.00 (+1.4%) |
| D | 69.5 | 13.23 (**+46%**) | 85.2 | 11.32 (**+15%**) |
| all | 71.4 | 12.57 (+39%) | 85.5 | 11.07 (+12%) |

**A (folds) is the surprise, and it is the bead's own hypothesis confirmed the hard
way.** The geometry is there — the 1 m frame shows the crease bands on the sleeve and the
torso, and the stride strip shows them deforming with the body without tearing — but the
variation it adds to the picture is **zero**: sd 8.97 against the control's 9.08 at 1 m,
and 9.86 against 9.86 at 3 m, i.e. identical to three significant figures. `DIFFUSE_TOON`
is why. Its two bands are a lighting THRESHOLD, so a 6 mm crease either falls entirely
inside one band (nothing happens) or straddles the step (a hard edge that does not read
as cloth). **Folds under toon shading are 57% more triangles for no picture.** That is
the single most useful thing this spike learned, and it is why A is not the pick.

**B (the bake) is the cheapest honest win and it is small.** +10% variation at 1 m for
zero triangles and zero bytes — the collar, the waistband crease and the armpit do
darken. At 3 m it is +1.4%, which is inside what anyone would call noise. It is real, it
costs literally nothing, and on its own it does not answer the owner.

**D (the cloth material) is the only column that changes the 3 m frame** — +15% variation
there and +46% at 1 m, and it is visible in the grid without measuring: the polo finally
has a lit side and a shadow side that fall off smoothly instead of stepping. That is what
`DIFFUSE_BURLEY` buys. Godot's toon diffuse has **no band count to raise** (the bead
asked; there is no such property on `BaseMaterial3D`, the step is fixed in the shader),
so the middle ground if the owner wants the cast's flatness kept is
`DIFFUSE_LAMBERT_WRAP`, one enum away in `ToonShading.style_cloth`.

**A CONFOUND IN D AND `all`, stated plainly: the SKIN went dark.** In both columns Teibi's
face and hands render several stops darker than the control. That is not the Burley
diffuse — it is the export: exporting materials at all changes how Godot's glTF importer
treats the vertex-colour attribute, so D's albedo is not comparable to the other columns'
even though its SHADING is. The mean-luma column above is therefore unreadable for D and
`all`; the sd column still means what it says, because a uniform albedo shift does not
change how much variation there is across a panel. **Anyone rolling D out must fix the
vertex-colour space first**, and the fix belongs in `build_hero.py`'s export, not in the
material.

## The recommended pick

**D + B, and not A.** Concretely: give the garments their own material
(`ToonShading.style_cloth` — Burley, roughness 1.0, no rim) and bake the occlusion and
cavity into the vertex colours that material shades. That pair is the only combination in
this grid that moves the **3 m** frame, which is the frame the game is played at, and it
costs **zero triangles and zero texture bytes** — it stays inside the owner's vertex-colour
ruling and adds 14 KB to a hero.

Against it, and the owner should weigh it: D takes the cast off `DIFFUSE_TOON` for
garments, which is the `y1o.22` ruling. This bead does not ship that — the grid is the
argument, the ruling is the owner's.

A is a real technique that this renderer cannot pay for. If the owner wants folds anyway,
they only become visible **on top of D** (see the `all` column at 1 m, where the bands
finally read), and even then only at 1 m — so the honest version is "folds are a
close-up feature, and this game has no close-ups."

## Deferred, and why

* **Column C — the 512² fabric albedo with weave and seam stitching on UV-unwrapped
  shells: NOT BUILT.** It is the one column needing a UV layout, a bake target and the
  lane's first texture byte, and the spike ran out of clock. Nothing here approximates it.
  It is also the column most likely to be worth building next, because a weave is the one
  thing that survives distance by being high-frequency — and because B could be baked
  INTO it, making C strictly additive over B as the bead intended.
* **A's triangle cost was not tuned.** +57% against the bead's estimated +15-25%, and
  6,242 tris over the shipped `TRI_BUDGET`. The band-limited subdivide in
  `fold_garments` cuts too wide a window (`FOLD_BAND * 1.4` around three joints). Given
  the finding above — folds buy nothing under toon — tuning it was not worth the rebuild;
  if A is ever revived, that is the first knob.
* **No Forward+ row**, and no per-column `[PERF]` reading. Both were cut for time; the
  shipped path's zero-delta is argued from construction above, not measured.
