# Roof flicker in the procedural city band — bead godot-test1-6n1

`scenes/main.tscn`'s `DirectionalLight3D` cannot carry a comment (Godot rewrites
`.tscn` files and drops them), so the reasoning behind its two changed numbers
lives here, next to the frames it was measured on.

## What the owner saw

"There is flickering on house's roofs" — the pitched `BoxKind.WEDGE` roofs of the
procedural CITY band (`terrain_biomes.gd::_spawn_city_content`), on the web build.

## How the frames were taken, and why that is not a detail

Every `6n1_*_web_*.png` here is the desktop binary running
`--rendering-method gl_compatibility` **plus** the three `.web` project-setting
overrides forced on at runtime, because a rendering method is not a feature tag:
`.web` overrides resolve on the `web` tag, which is true only in a browser. Without
forcing them a "web" capture silently runs at the engine's desktop
`directional_shadow/size` of **4096**, 4x MSAA and full internal resolution — 4x the
shadow resolution the web build ships, which is exactly the axis this bead is about.
So the captures force:

```
RenderingServer.directional_shadow_atlas_set_size(1024, true)   # size.web
viewport.msaa_3d        = MSAA_DISABLED                         # msaa_3d.web
viewport.scaling_3d_scale = 0.8                                 # scale.web
camera.fov              = 97.0                                  # FOV_MAX: the game is played RUNNING
```

The FOV matters for the same reason: a cascade's texel size is fitted to the camera
sub-frustum, so the widest FOV the player ever holds is the worst case, not the
standing 75 the tool's frozen pose uses.

## What it is

**Directional shadow acne**, not geometry. Proved by A/B, not by arithmetic:

| frame | roofs |
|---|---|
| shipped light | dense diagonal bands across every roof slope, cross-hatch on every plaster wall |
| same frame, `shadow_enabled = false` | completely clean |

`6n1_band_web_before.png` and `…_before_next_frame.png` are two consecutive frames
with the camera crept 0.3 m: the bands **re-space and shift** between them. That
crawl is the flicker.

The pair of coplanar faces PR #334 lifted (hull top vs roof underside) is not the
cause and never could be — they face opposite ways under `cull_back` and are never
both rasterized. That branch was abandoned.

## Why the shadow map could not resolve it

`DirectionalLight3D`'s own defaults, read off a fresh instance in Godot 4.5, are
`directional_shadow_mode = 2` (**4** splits), `directional_shadow_split_1 = 0.1`,
`shadow_normal_bias = 2.0`. `main.tscn` deliberately drops to
`directional_shadow_mode = 1` (**2** splits, half the shadow passes) — but it kept
`split_1` at the 4-split default and *lowered* the normal bias to 0.8.

With two splits and `max_distance = 55`, `split_1 = 0.1` puts the near cascade over
0–5.5 m and makes the far cascade carry **5.5–55 m**. On web's 1024 px map, at the
running FOV, that far cascade's texel is over a tenth of a metre.

A wedge slope sits ~29° off horizontal (`CITY_ROOF_RISE_FACTOR` 0.28, so a rise over
run of 0.56) against a sun 35° above the horizon, i.e. close to grazing to the light,
where the depth error across one texel is several texels deep. `shadow_normal_bias`
is measured in **texels**, not metres, so 0.8 of a 0.1 m texel never reached it.

## The change

```
shadow_normal_bias            0.8  ->  3.0
directional_shadow_split_1    (absent, engine default 0.1)  ->  0.35
```

Both are needed and each was measured alone:

- **split alone** (0.35, bias untouched) — bands get finer, do not go away.
- **normal bias alone** — 2.0 barely moves it; 5.0 cleans the slope by pushing the
  lookup so far along the normal that the roof stops being shadowed at all, i.e. it
  buys a clean frame with a wrong one.
- **together** — clean and correct: the slope keeps the shadow it should have, the
  eave line stays crisp, every cast shadow stays attached to its caster.

### The cascade trade, both halves

`split_1 = 0.35` is not free, and the cost lands where the player is looking:

- **near cascade** 0–5.5 m → **0–19.25 m**: its bounding sphere grows ~3.5x and its
  texel with it. Since `shadow_normal_bias` is a texel multiple, the world-space
  offset applied to everything within 19 m grows by that factor *on top of* the
  0.8 → 3.0 change.
- **far cascade** 5.5–55 m → **19.25–55 m**: smaller sphere, finer texel, so the
  distance band that was worst gets better.

That is the whole point of moving the split: it takes resolution away from a 5.5 m
bubble nobody can see acne in (nothing is within 5.5 m of a third-person camera but
the hero's own feet) and spends it on the 5–30 m band where the houses actually are.
The price is the larger normal offset near the camera, and `6n1_field_web_contact_*`
is the measurement of what that costs — see below.

## No peter-panning — measured, not argued

`6n1_field_web_before.png` / `…_after.png` are the open-field props at the same
frozen pose and the true web settings. Before: the terraced slabs, the crates and
the boulder all carry the same striping. After: clean.

`6n1_field_web_contact_before.png` / `…_after.png` are the contact line of the tall
slab prop, blown up 6x — the one place a bigger normal offset would show as a light
gap between a caster's foot and its shadow. It goes the other way: **before** there
is a pale gap between the slab's base and its cast shadow (the coarse cascade was
leaking light into the contact, the same leak that lit the roof slopes), and
**after** the shadow reaches the base. The nominal pull-in from the larger offset is
a few centimetres at a 35° sun — a couple of pixels at this framing — and the
contact reads tighter, not looser.

## Both renderers

`6n1_band_forwardplus_*.png` — desktop Forward+ at the engine's default **4096 px**
map (`project.godot` sets only `size.web`; the base setting is unset). There the
roofs were already clean and the change only softens the serrated comb along the
wall/eave junction. Not a regression on desktop.

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
(visible near the ridge in the band's after frame). That is a placement question for
`_biome_spot_ok`, not a lighting one, and it is a separate bead.
