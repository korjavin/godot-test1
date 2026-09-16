# Roof flicker in the procedural city band — bead godot-test1-6n1

The two numbers this bead changes live on `EndlessTerrain`'s
`WEB_SHADOW_NORMAL_BIAS` / `WEB_SHADOW_SPLIT_1`, with their argument in the banner
above them and in `apply_sun_shadow`'s docstring. **This file is the evidence**: the
frames, how they were taken, and the alternatives that were measured and rejected.

## What the owner saw

"There is flickering on house's roofs" — the pitched `BoxKind.WEDGE` roofs of the
procedural CITY band (`terrain_biomes.gd::_spawn_city_content`), on the web build.

## What it is

**Directional shadow acne**, not geometry. Proved by A/B, not by arithmetic:

| frame | roofs |
|---|---|
| `6n1_band_bisect_shadows_on.png` | dense diagonal bands across every roof slope, cross-hatch on every plaster wall |
| `6n1_band_bisect_shadows_off.png` — the same spot with the `DirectionalLight3D`'s `shadow_enabled = false` | completely clean |

That pair is the bead's bisect step and it is deliberately taken in the tool's
DEFAULT configuration (desktop `gl_compatibility`, so the engine's 4096 px shadow
map), not the web one — acne is *worse* at web's 1024, so a 4096 frame that already
shows it is the conservative demonstration. Two processes, same seed, same spot;
the geometry, the camera and every prop are identical between them.

`6n1_band_web_before.png` and `…_before_next_frame.png` are two consecutive frames
with the camera crept 0.3 m: the bands **re-space and shift** between them. That
crawl is the flicker.

**Cause 3 (toon banding) is excluded by code, not just by a frame.**
`toon_shading.gd` is applied to the cast and the tower only; the chunk batch's
material is `assets/shaders/world_block.gdshader`, `diffuse_burley`, with no toon
band to alias. **Cause 1 (z-fighting)** — the coplanar pair PR #334 lifted, hull top
vs roof underside — face opposite ways under `cull_back` and are never both
rasterized. That branch was abandoned and nothing from it is reused.

## How the frames were taken, and why that is not a detail

`--rendering-method gl_compatibility` **is not the web build**. It switches the
renderer; every `.web` project-setting override resolves on the `web` FEATURE TAG,
which a desktop binary never carries. A plain `gl_compatibility` capture therefore
still renders at the engine's desktop `directional_shadow/size` of **4096**, with 4x
MSAA and full internal resolution — four times the shadow resolution the web build
ships, on the one axis this bead is about. The bead's first set of A/B frames was
taken that way and had to be retaken.

`scenes/style_shots.tscn` now carries the recipe so nobody repeats it:

```
godot --rendering-method gl_compatibility --path . scenes/style_shots.tscn \
      -- <outdir> only=2b_city_band,1_field web
```

(`only=` is a substring test against the shot NAME, so both shots have to be named:
`only=2b_city_band` alone emits one PNG and none of the field evidence below. The
same substring rule also throws in `11_field_bridge_deck`, which contains `1_field`;
ignore it.)

`web` forces the three `.web` keys (shadow atlas 1024, MSAA off, internal scale 0.8)
**and** asks the game for its own web-gated tuning through
`EndlessTerrain.apply_sun_shadow(true)` — plus `fov = 97`, `player_controller`'s
`FOV_MAX`. The FOV matters for the same reason the atlas does: a cascade is fitted
to the camera sub-frustum, so the widest FOV the player ever holds is the worst case
for its texel size, and the tool's frozen pose is a standing one.

`6n1_band_web_*.png` and `6n1_field_web_*.png` are that command's two shots. The
`before` half of each pair is the same command with `WEB_SHADOW_NORMAL_BIAS` /
`WEB_SHADOW_SPLIT_1` set back to the scene's desktop values (0.8 and 0.1).
`6n1_field_web_contact_*.png` are not separate shots: they are the same field frames
cropped 840x540 around the tall slab's foot and scaled 6x, by hand.

## Why the shadow map could not resolve it

`DirectionalLight3D`'s own defaults in Godot 4.5, read off a fresh instance:
`directional_shadow_mode = 2` (**4** splits), `directional_shadow_split_1 = 0.1`,
`shadow_normal_bias = 2.0`. `main.tscn` deliberately drops to
`directional_shadow_mode = 1` (**2** splits, half the shadow passes) — but it kept
`split_1` at the 4-split default and *lowered* the normal bias to 0.8.

With two splits and `max_distance = 55`, `split_1 = 0.1` puts the near cascade over
0–5.5 m and makes the far cascade carry **5.5–55 m**. On web's 1024 px map at the
running FOV, that far cascade's texel is over a tenth of a metre.

A wedge slope sits ~29° off horizontal (`CITY_ROOF_RISE_FACTOR` 0.28, a rise over run
of 0.56) against a sun 35° above the horizon — close to grazing to the light, where
the depth error across one texel is several texels deep. `shadow_normal_bias` is
measured in **texels**, not metres, so 0.8 of a 0.1 m texel never reached it.

## The change, and why it is web-only

```
shadow_normal_bias          0.8  ->  3.0     (WEB ONLY)
directional_shadow_split_1  0.1  ->  0.35    (WEB ONLY)
```

`scenes/main.tscn` is left carrying the desktop values. Web is a quarter of the
desktop map in each axis, and `shadow_normal_bias` is texel-denominated, so the same
number means four times the world-space offset there. Desktop had no acne to remove
at 4096 — so applying the retune globally would have been a pure cost, and a
measured one. `6n1_forwardplus_global_retune_before.png` / `…_after.png` are that
measurement and the reason this is gated: desktop Forward+ with the retune applied
**globally**, which is what an earlier commit on this branch shipped and what revmux
round 02 rejected. A near-camera **thin** caster (a lamp pole) has its shadow break
into a stipple — the fraction of pixels below 45% luma in that foreground crop falls
0.1136 → 0.0694, a 39% loss, while a mid-field house-shadow control is unchanged
(0.2345 → 0.2311). A thin caster's shadow is one or two texels wide, and a tripled
normal offset walks the lookup off it.

Those two frames are kept precisely because they are the evidence for the gate: the
next author who asks "why not just set 3.0 globally?" needs them, and they document
a state this branch no longer ships. That is the whole of CLAUDE.md's "visual
changes are web-gated".

Both numbers are needed, and each was measured alone:

- **split alone** (0.35, bias untouched) — bands get finer, do not go away.
- **normal bias alone** — 2.0 barely moves it; 5.0 cleans the slope by pushing the
  lookup so far along the normal that the roof stops being shadowed at all, i.e. it
  buys a clean frame with a wrong one.
- **together** — clean and correct: the slope keeps the shadow it should have, the
  eave line stays crisp, every cast shadow stays attached to its caster.

Also measured and rejected: `shadow_bias` 0.3 / 0.5 / 1.0 / 1.5 (no visible effect
on this artefact under `gl_compatibility`), and `directional_shadow_max_distance`
55 → 35 (bands remain, and it shortens every shadow in the game).

### The cascade trade, both halves

`split_1 = 0.35` is not free, and the cost lands near the camera:

- **near cascade** 0–5.5 m → **0–19.25 m**: its bounding sphere grows ~3.5x and its
  texel with it. Since `shadow_normal_bias` is a texel multiple, the world-space
  offset applied to everything within 19 m grows by that factor *on top of* the
  0.8 → 3.0 change.
- **far cascade** 5.5–55 m → **19.25–55 m**: smaller sphere, finer texel, so the
  distance band that was worst gets better.

That is the point of moving the split: it takes resolution away from a 5.5 m bubble
a third-person camera has nothing in and spends it on the 5–30 m band the houses are
in. The price is the larger normal offset near the camera, and
`6n1_field_web_contact_*` is the measurement of what that costs.

## No peter-panning — measured, not argued

`6n1_field_web_before.png` / `…_after.png` are the open-field props at the same
frozen pose and the true web settings. Before: the terraced slabs, the crates and
the boulder all carry the same striping. After: clean.

`6n1_field_web_contact_before.png` / `…_after.png` are the contact line of the tall
slab prop, blown up 6x — the one place a bigger normal offset would show as a light
gap between a caster's foot and its shadow. It goes the other way: **before** there
is a pale gap where the coarse cascade leaked light into the contact (the same leak
that lit the roof slopes), and **after** the shadow reaches the base. The nominal
pull-in from the larger offset is a few centimetres at a 35° sun — a couple of
pixels at this framing — and the contact reads tighter, not looser.

## Desktop is untouched, by construction rather than by a frame

There is no desktop A/B of the SHIPPED state here because there is nothing to
compare — `6n1_forwardplus_global_retune_*` above documents the rejected global
version, not this one. `apply_sun_shadow`
returns on its first line when `is_web` is false, and the only other change to
`scenes/main.tscn` is the deletion of `directional_shadow_blur = 1.2`, which
`DirectionalLight3D` has no property for in Godot 4.5 — probed live on the loaded
scene, `"directional_shadow_blur" in light` is `false` and `shadow_blur` reads its
untouched 1.0 default. The line never did anything; it only claimed the shadows were
blurred. So a desktop or editor frame is bit-for-bit what it was before this bead.

## Perf

Same cascade count, same shadow passes, same draw calls — 256 in the band on
`gl_compatibility` before and after (`[PERF]` line of `scenes/style_shots.tscn`).
Two light properties written once at startup; no shader, no geometry, no RNG draw.

## Not fixed here

A handful of band houses stand close enough that one roof prism intersects its
neighbour's, and the two near-parallel slopes interleave in a small dithered patch
(visible near the ridge in the band's after frame). That is a placement question for
`_biome_spot_ok`, not a lighting one, and it is a separate bead.

---

# Correction — bead godot-test1-p0g1 (2026-09-16): the wedge was inside-out

**Everything above is still true about the shadow acne, and the two web numbers
stay. What it was taken on was wrong.** The `BoxKind.WEDGE` unit mesh was wound
counter-clockwise from outside — the right-hand rule — and Godot's front face is the
CLOCKWISE one, so under `world_block.gdshader`'s `cull_back` all eight of its
triangles faced in. Measured in-engine over `ChunkBatch.unit_mesh(kind)`, one
`Plane(v0, v1, v2).normal.dot(face centroid)` per triangle: CUBE 12/12 outward,
SPHERE 64/64, CONE 60/60, CYLINDER 96/96, ROCK 64/64 — **WEDGE 0/8**.

So the band's roofs never drew as pitched. Both slopes and both gables were culled;
what read as a roof was the wedge's BASE quad seen from above, and the base spans the
full roof footprint at exactly the hull's top face (`terrain_biomes.gd` puts the roof
centre at `height + rise/2`, so base y == hull top y to the millimetre). Two
MultiMesh draws, two coplanar front faces: a z-fight whose winner moves with the
camera, which is the owner's "the roof goes transparent for a moment, I see a white
ceiling" — the hull's lit `CITY_PLASTER_A` showing through.

Three consequences for this document:

1. **"Cause 1 (z-fighting) — the coplanar pair PR #334 lifted, hull top vs roof
   underside — face opposite ways under `cull_back` and are never both rasterized"
   was wrong as written**, and wrong only because of the winding. With the flip it
   becomes true, which is why #334's lift is not re-added: there is nothing left to
   lift apart.
2. **The acne frames above were taken on that base quad**, a horizontal face, not on
   the ~29° slopes the arithmetic reasons about. `WEB_SHADOW_NORMAL_BIAS` 3.0 and
   `WEB_SHADOW_SPLIT_1` 0.35 are kept — `p0g1_band_web_before.png` /
   `p0g1_band_web_after.png` are the same `style_shots` recipe as `6n1_band_web_*`,
   retaken either side of the winding flip, and **the now-real slopes carry no acne
   and no peter-panning**, so there is nothing to retune and no follow-up filed.
   `1_field` was retaken in the same two runs and is unchanged (a wedge-only mesh
   edit cannot reach it); draw calls are identical either side — band 241/241, field
   218/219, bridge 305/305.
3. **"Not fixed here" above is resolved, not deferred.** The dithered patch was not
   two roof prisms interleaving: across 138 wedge colliders within 400 m of a band
   spot, **no two wedge AABBs intersect at all**. The patch was this same base quad
   against the hull top under it, and it is gone in `p0g1_band_web_after.png` at the
   same houses. Closed bead `godot-test1-c2i` stays closed.

The fix is `chunk_batch.gd::_build_unit_wedge_mesh()` emitting each triangle
clockwise, and nothing else: no vertex moved, so `UNIT_WEDGE_POINTS`, the collider,
the footprints and the RNG stream are untouched. `batch_selfcheck` check 1 now
measures that rule per triangle for every kind, which is the thing that was missing —
it asserted flat normals and unit-cube reach, and neither says which side of a face
the camera may see.

Acceptance frames, hero standing on a band-house ridge at seed 12345, same stance
either side, default camera:

| pair | before | after |
|---|---|---|
| `gl_compatibility`, web sun shadow | `p0g1_ridge_gl_before.png` | `p0g1_ridge_gl_after.png` |
| Forward+ | `p0g1_ridge_forwardplus_before.png` | `p0g1_ridge_forwardplus_after.png` |

`p0g1_ridge_walk_after_a.png` / `…_b.png` are two consecutive frames while walking
the ridge: the roof does not change. The same walk before the flip put a
plaster-white sample on a visible slope centre in 8 of 9 `gl_compatibility` frames
and 10 of 12 Forward+ frames, and in 0 of 10 and 0 of 13 after it.
