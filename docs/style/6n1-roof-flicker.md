# Roof flicker in the procedural city band — bead godot-test1-6n1

`scenes/main.tscn`'s `DirectionalLight3D` cannot carry a comment (Godot rewrites
`.tscn` files and drops them), so the reasoning behind its two changed numbers
lives here, next to the frames it was measured on.

## What the owner saw

"There is flickering on house's roofs" — the pitched `BoxKind.WEDGE` roofs of the
procedural CITY band (`terrain_biomes.gd::_spawn_city_content`), on the web build.

## What it is

**Directional shadow acne**, not geometry. Proved by A/B, not by arithmetic:

| frame | roofs |
|---|---|
| shipped light, `gl_compatibility` | dense diagonal bands across every roof slope, cross-hatch on every plaster wall |
| same frame, `shadow_enabled = false` | completely clean |

`docs/style/6n1_band_web_before.png` and `…_before_next_frame.png` are two
consecutive frames with the camera crept 0.3 m: the bands **re-space and shift**
between them. That crawl is the flicker.

The pair of coplanar faces PR #334 lifted (hull top vs roof underside) is not the
cause and never could be — they face opposite ways under `cull_back` and are never
both rasterized. That branch was abandoned.

## Why the shadow map could not resolve it

The light ran `directional_shadow_mode = 1` (PSSM, **2 splits**) at
`directional_shadow_max_distance = 55` while `directional_shadow_split_1` sat at
Godot's default **0.1**. That default is tuned for the 4-split mode; with two
splits it puts the near cascade over 0–5.5 m and makes the far cascade carry
**5.5–55 m** — on web a 1024 px map (`project.godot`:
`lights_and_shadows/directional_shadow/size.web`), i.e. a texel of roughly 0.1 m.

A wedge slope sits ~29° off horizontal against a sun 35° above the horizon, so its
surface runs close to grazing to the light: the depth error across one texel is
`texel × tan(angle)`, several times the texel itself. `shadow_normal_bias = 0.8` —
already below the engine's own 2.0 default for a directional light — offsets by
less than one texel and never reached it.

## The change

```
shadow_normal_bias      0.8  ->  3.0
directional_shadow_split_1   (absent, default 0.1)  ->  0.35
```

Both are needed and each was measured alone:

- **split alone** (0.35, bias untouched) — bands get finer, do not go away.
- **normal bias alone** — 2.0 barely moves it; 5.0 cleans the slope by pushing the
  lookup so far along the normal that the roof stops being shadowed at all, i.e. it
  buys a clean frame with a wrong one.
- **together** — clean and correct: the slope keeps the shadow it should have, the
  eave line stays crisp, every cast shadow stays attached to its caster.

0.35 also makes the *far* cascade finer, not coarser: it now covers 19–55 m instead
of 5.5–55 m. Nothing about the number of shadow passes changes.

## No peter-panning

`docs/style/6n1_field_web_before.png` / `…_after.png` — the open-field props at the
same frozen pose. Before: the tall slab and the crates carry the same striping.
After: clean, and every contact shadow is still anchored at its caster's foot.

## Both renderers

`docs/style/6n1_band_forwardplus_*.png` — on desktop Forward+ (2048 px map) the
roofs were already clean; the change only softens the serrated comb along the
wall/eave junction. It is not a regression on desktop.

## Perf

Same cascade count, same shadow passes, same draw calls — 256 in the band on
`gl_compatibility` before and after (`[PERF]` line of `scenes/style_shots.tscn`).
Two light properties; no shader, no geometry, no RNG draw.

## One line removed

`directional_shadow_blur = 1.2` went with it. `DirectionalLight3D` has no such
property in Godot 4.5 — probed live on the loaded scene:
`"directional_shadow_blur" in light` is `false` and `shadow_blur` reads its 1.0
default. The line has never done anything; it only claimed the shadows were blurred.

## Not fixed here

A handful of band houses stand close enough that one roof prism intersects its
neighbour's, and the two near-parallel slopes interleave in a small dithered patch
(visible near the ridge in `6n1_band_web_after.png`). That is a placement question
for `_biome_spot_ok`, not a lighting one, and it is a separate bead.
