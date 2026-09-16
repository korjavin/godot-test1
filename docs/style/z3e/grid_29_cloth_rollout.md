# The cloth rollout — what shipped, and every number behind it

Bead `godot-test1-21m`, the rollout of spike `godot-test1-td8`. Owner, 2026-09-12, on
`grid_27_cloth_spike.png`: **"i choose A+B+D"** — folds as geometry, baked AO/cavity in
the vertex colours, and the garments on their own Burley material. All three are now
every hero's default path in `scripts/build_hero.py`; the spike's `--variant` flag and
its four scratch `teibi_cloth_*.glb` are deleted.

* the grid — `grid_29_cloth_rollout.png` (today | shipped, per hero, `18_body_3m` and
  `20_torso_1m` on the web renderer, plus a Forward+ column at 3 m)
* the stride strips — `grid_29_cloth_stride_{teibi,windman,primm}.png`
* the mirror — `grid_29_cloth_remote_avatar.png`
* the control — `grid_29_cloth_predators.png`

Renderer for every "web" figure: `--rendering-method gl_compatibility` **plus** the `web`
argument, which is what makes `_emulate_web_settings` resolve the `.web` project
overrides. Seed, spot, pose and camera are `style_shots.gd`'s own and identical in both
columns, so a today/shipped pair differs only in the hero.

## 1. What it costs

| hero | tris before | tris shipped | Δ | glb bytes before | after | texture bytes |
|---|---:|---:|---:|---:|---:|---:|
| teibi | 13,872 | 16,536 | **+19.2%** | 453,116 | 557,364 | 0 |
| windman | 14,743 | 17,421 | **+18.2%** | 503,076 | 608,864 | 0 |
| primm | 13,178 | 15,474 | **+17.4%** | 432,332 | 520,696 | 0 |

The bead's budget was +15-25% per hero and the spike's untuned column A was **+57%**
(21,742 on Teibi). What closed the gap is the width of the SUBDIVIDED band, not the fold
amplitude: the spike cut every garment edge within 21 cm of a joint and 9 cm of a hem,
which on a 183 cm hero is half the body. `CREASE_BAND` (28 mm) and `GATHER_BAND` (14 mm)
are those bands scaled onto the budget, measured and re-measured — 0.042/0.020 came out
at +29.5% on Teibi before the final pair. The same two numbers are now the displacement's
gaussian envelope (`FOLD_TAPER`), so a 42 mm crease wave cannot run out past the vertices
that resolve it and alias into noise.

The budget is **asserted in `fold_garments` itself**, per hero, as a fraction of the
pre-fold triangle count (`FOLD_TRIS_MIN` / `FOLD_TRIS_MAX`) — the only pass that adds a
triangle is the one that checks. `TRI_BUDGET` rose 15,500 → 18,500 behind it.

Per-pass log, from the `--all` build:

| hero | folds | bake (garment verts, darkening min/median) | material (cloth polys / total) |
|---|---|---|---|
| teibi | 1,167 edges, +1,332 verts, 13,208 → 15,872 tris (+20.2%) | 3,553, 0.315 / 0.994 | 4,497 / 11,071 |
| windman | 1,176 edges, +1,339 verts, 14,116 → 16,794 tris (+19.0%) | 3,394, 0.315 / 0.977 | 4,271 / 11,633 |
| primm | 1,020 edges, +1,148 verts, 13,154 → 15,450 tris (+17.5%) | 4,226, 0.315 / 0.988 | 5,532 / 10,536 |

(The per-hero final Δ differs from the folds' own Δ because accessories — the beret, the
eyes, Primm's coat tails — join after the fold pass and were always in the total.)

**Primm's coat tails are cloth now too**, and they are the one garment `dress_shells`
cannot mark: they are NEW geometry (`attach_tails`), so they carried no garment vertex
group and would have shaded as skin — a coat whose flaps are not made of the coat.
`build()` adds their 16 vertices to the cloth group after the join, and the bake moved
after the accessory joins so they are occluded and shaded with the rest of the coat.

## 2. The spike's open variable, closed

The spike left one: *"with a material present the cloth reads a stop darker — what is
left is how the importer treats `COLOR_0`. Anyone rolling D out must settle that colour
space first."*

**It is not the importer and it is not `COLOR_0`.** Dumped side by side in Godot 4.5, the
material Godot builds for a hero that exports NO material and the two it builds for a hero
that exports `HeroSkin` + `HeroCloth` are identical in every property it exposes:

```
no material:  albedo=(1,1,1,1) vc_as_albedo=true vc_is_srgb=false metallic=0 rough=1 cull=back tex=<null>
HeroSkin:     albedo=(1,1,1,1) vc_as_albedo=true vc_is_srgb=false metallic=0 rough=1 cull=back tex=<null>
HeroCloth:    albedo=(1,1,1,1) vc_as_albedo=true vc_is_srgb=false metallic=0 rough=1 cull=back tex=<null>
```

and the `COLOR_0` arrays are the same values (mean over the split mesh, weighted by
vertex count, reproduces the unsplit mesh's mean to within the seam vertices the split
duplicates: 0.4160/0.3272/0.1973 against 0.4083/0.3210/0.1964 on 239 more vertices).

What darkens the garment is **the shading recipe, which is the pick itself**:

* `DIFFUSE_TOON` at roughness 1.0 lights a surface whose normal is perpendicular to the
  key light at roughly HALF power; `DIFFUSE_BURLEY` lights it at zero and climbs with
  N·L. A hero's legs and the sides of a torso live near that angle under this game's low
  sun, which is exactly where the difference lands.
* the cast's rim light is extra brightness at the silhouette, and a garment does not get
  one any more — by the owner's pick, because a rim traces a silhouette and a fold is
  inside it.

So the answer to "must the shipped colours match today's" is: **the mean cannot match and
the reason is the thing that was chosen.** Today's garments were also brighter than their
own authored palette colour — Windman's `shorts_brown` (0.42, 0.30, 0.18), which is a
mid-brown, rendered at luma 189 where the colour itself is 153; shipped it reads 99.
Teibi's polo is the case where the panel happens to face the light and the match is
exact: authored 213.6, shipped 212.4.

`DIFFUSE_LAMBERT_WRAP` — the middle ground the spike nominated, one enum away in
`ToonShading.style_cloth` — was measured and **does not buy the trade**: at roughness 1.0
Godot's wrap term peaks at 0.5, so it recovers almost none of the luma (windman −43.0%
against Burley's −47.8%) while giving up half the variation that is the whole point
(sd +166.8% against +317.8%). It is recorded here so nobody re-runs it.

**This is the one thing left for the owner**, and it is a look question, not a bug: the
garments read materially darker on surfaces angled away from the sun. The knobs, in
increasing order of walking back the pick, are `style_cloth`'s diffuse mode, its rim, and
an albedo gain on the cloth material (which cannot match all three heroes at once — the
deficit is 13%, 48% and 54%, because it depends on how each garment faces the light).

## 3. The numbers

Rec.709 luma on the displayed pixels, mean and standard deviation over a fixed crop given
in fractions of the frame, the same crop in both columns. **The sd is the number the
argument rests on** — it is how much variation there is across the crop, i.e. whether
anything reads as a fold at all. A flat painted panel has a low one; that is the owner's
complaint expressed as a number.

### 3 m, the gameplay distance — the whole hero (crop `0.44, 0.27, 0.56, 0.72`)

| hero | renderer | today mean | shipped mean | Δ | today sd | shipped sd | Δ |
|---|---|---:|---:|---:|---:|---:|---:|
| teibi | web | 191.29 | 176.12 | −7.9% | 55.50 | 70.66 | **+27.3%** |
| windman | web | 195.50 | 182.48 | −6.7% | 48.24 | 60.43 | **+25.3%** |
| primm | web | 172.61 | 158.14 | −8.4% | 64.29 | 82.22 | **+27.9%** |
| teibi | Forward+ | 191.77 | 169.24 | −11.8% | 58.40 | 64.88 | +11.1% |
| windman | Forward+ | 193.27 | 177.66 | −8.1% | 59.35 | 61.84 | +4.2% |
| primm | Forward+ | 181.51 | 159.23 | −12.3% | 55.80 | 70.12 | +25.7% |

### 3 m — the GARMENT alone, web

| hero | crop | today mean | shipped mean | Δ | today sd | shipped sd |
|---|---|---:|---:|---:|---:|---:|
| teibi polo | `0.470, 0.370, 0.528, 0.450` | 244.32 | 212.39 | −13.1% | 6.12 | **44.96** |
| windman shorts | `0.478, 0.495, 0.518, 0.560` | 189.26 | 98.89 | −47.8% | 10.80 | **45.11** |
| primm trousers | `0.487, 0.505, 0.522, 0.565` | 112.78 | 51.73 | −54.1% | 26.43 | **43.90** |

### 1 m torso (crop `0.45, 0.30, 0.53, 0.52`), web

| hero | today mean | shipped mean | Δ | today sd | shipped sd | Δ |
|---|---:|---:|---:|---:|---:|---:|
| teibi | 244.20 | 209.41 | −14.3% | **1.36** | **45.65** | +3267% |
| windman | 217.96 | 187.26 | −14.1% | 37.41 | 62.97 | +68.3% |
| primm | 117.97 | 69.35 | −41.2% | 52.02 | 69.11 | +32.8% |

Teibi's 1 m torso is the whole bead in one figure: **sd 1.36**. Eight thousand pixels of
polo with a standard deviation of half a percent is not a garment, it is a fill colour —
"shirts and clothing look painted, not natural", measured. It is 45.65 now.

## 4. What must NOT have changed, and did not

**Predators.** `toon_shading.gd` is shared with all ~490 crocodiles, the bosses, the
hunter robots and the HQ's guards, so the cloth branch had to be unreachable for them —
it is, because nothing but a skinned hero exports a material named `HeroCloth`. Measured
on the same two portrait frames before and after, crop `0.30, 0.15, 0.70, 0.85`:

| frame | today | shipped | Δ mean | Δ sd |
|---|---:|---:|---:|---:|
| `25_hunter_quarter` | 156.86 | 156.88 | **+0.01%** | +0.0% |
| `26_tower_guard_side` | 181.56 | 181.56 | **+0.00%** | +0.0% |

**The remote mirror.** A teammate's avatar is styled by `remote_avatar.gd`'s own subtree
walk, not by the local player's — two call sites of one recipe. `grid_29_cloth_remote_avatar.png`
is the local Teibi and a `RemoteAvatar` Teibi side by side, and `mp_selfcheck`'s new cloth
check asserts it permanently for every playable character: the `HeroCloth` surface must be
DIFFUSE_BURLEY with no rim, a DIFFUSE_TOON + rim surface must survive beside it, and
exactly three of the four characters may carry cloth at all (Phoboman's generated part
tree is the negative control). Mutation-tested: flipping `style_cloth`'s rim back on turns
it red with the right message.

**`[PERF]`, on the web stand-in.** Per-shot readings at `18_body_3m`:

| hero | today avg ms | shipped avg ms | today draws | shipped draws |
|---|---:|---:|---:|---:|
| teibi | 10.46 | 9.28 | 263 | 248 |
| windman | 8.16 | 13.92 | 105 | 217 |
| primm | 11.23 | 13.81 | 273 | 217 |

**These readings are noise and are reported as such**: the draw count for the SAME shot
swings 105 → 273 between two runs of the same build, because what the streamer has loaded
around the spot at the moment of measurement dominates a single hero's cost by two orders
of magnitude. The frame time moves in both directions. What is NOT noise, and is
structural, is the draw call the material split costs: a hero's mesh is two surfaces where
it was one, so **+1 draw call per hero on screen** — three heroes is +3, which the bead
named in advance and accepted. The `27_remote_avatar` shot, the only frame in the set with
two skinned heroes in it, ran at 9.10 ms / 220 draws.

## 5. Deferred

* **Column C** (512² fabric albedo, weave + seams on unwrapped shells): still not built,
  still not picked. It remains the column most likely to survive 3 m, and the one that
  would spend this lane's first texture byte.
* **A real web export reading.** Every "web" figure here is a desktop binary in
  `gl_compatibility` with the `.web` overrides, which is the stand-in this repo has always
  used; nothing in this bead needed the real export and nothing here claims one.
* **The garment luma gap** (section 2) is the owner's call and is not a defect.
