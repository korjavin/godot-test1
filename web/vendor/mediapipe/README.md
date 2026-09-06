# MediaPipe Tasks Vision — pinned, fetched at build time, served from our own nginx

The face detector behind the cartoon camera's crop box (bead `godot-test1-xtr.12`).
`scripts/voice_chat.gd`'s `VOICE_JS` loads these files into a Web Worker, at
2–4 Hz, **only** after a room is joined and the Camera button has been pressed.

## Why the files come from OUR origin and never a CDN

The owner's ruling (2026-09-06): **never a runtime CDN.** MediaPipe's own docs
load the fileset from `cdn.jsdelivr.net`, and its `FilesetResolver` takes any
path — so it takes ours. Two reasons and both are load-bearing: a CDN outage
would silently degrade every player to the centre crop with nothing saying so,
and every player's session would be announced to a third party on camera-on.

## The binaries are NOT in git — they are fetched at build time

They are ~12 MB, and a binary in history is permanent weight on every clone and
every CI checkout, forever. So this directory holds only `vendor.lock` (the bill
of materials: package, version, per-file sha256, and the model's url), this
README and the LICENSE. **`scripts/fetch_vendor.sh` downloads the rest**,
verifies every sha256, and refuses to install anything that does not match.

```bash
sh scripts/fetch_vendor.sh              # populate this directory
sh scripts/fetch_vendor.sh build/web    # ...and install into an export
```

`.github/workflows/build.yml` calls it twice — fetch before the export so a bad
pin fails in seconds, install after — and `./serve.sh` calls it once for a local
debug export, so CI and the developer rig run the same code and cannot drift. It
is idempotent: a directory that already matches the lock downloads nothing.

**A build-time fetch is not a runtime CDN.** The ruling is about what the
player's browser loads, which is still only ever our own nginx; nothing here runs
on a player's machine, and the verified bytes are baked into the image.

Re-pinning is: change the version and the shas in `vendor.lock`, run the script.
Nothing else names a version or a url.

## Why 1.0.1, and why four files out of fifteen

**The pin is 1.0.1 because it is the first version that ships an IIFE bundle**,
and that decides the whole design. `vision_bundle.js` defines a `Vision` global,
so the detector worker is a CLASSIC worker doing `importScripts(...)`. The 0.10.x
line ships ESM and CommonJS only, which forces a module worker — and a module
worker has no `importScripts`, so the library's own wasm loader

```js
if (typeof importScripts !== 'function') { document.createElement('script') … }
```

takes its DOM branch and reaches for a `document` that no worker has. It fails
every time. The IIFE is the branch the library is actually written for.

It is paid for in bytes: 1.0.1's wasm is 11.76 MB against 0.10.21's 9.57 MB
(3.43 MB against 2.90 MB gzipped, which is what a player really downloads — see
the gzip note below). Both are inside the owner's ~4 MB ruling on the wire, and
the extra 2.2 MB buys a worker that needs neither module-worker support nor
dynamic `import()` inside a worker.

**Only the SIMD build is here.** The package also ships
`vision_wasm_nosimd_internal.{js,wasm}` and `vision_wasm_module_internal.{js,wasm}`
— another 22 MB between them — the first of which
`FilesetResolver.forVisionTasks()` asks for on a browser without WASM SIMD.
Doubling the repository's weight for that case buys nothing: WASM SIMD has
shipped in Chrome 91, Firefox 89 and Safari 16.4, and a browser without it simply
404s the loader, the detector fails to construct, and `VOICE_JS` settles on the
**centre crop** — the same rung it settles on for a browser with no
`OffscreenCanvas` (Safari 16 and older), a blocked download, or a camera pointed
at no face. The fallback is the feature's own ladder, not a hole.

The `.map` files, the ESM and CommonJS bundles, `vision.d.ts` and the other task
models are all omitted for the same reason: nothing loads them.

**Do not gzip these by hand.** `web/nginx.conf` compresses `application/wasm` and
the bundle on the fly (11.76 MB → 3.43 MB on the wire; 3.58 MB for all four files,
MEASURED through the pinned nginx image), and GitHub Pages does its own. A committed `.gz` would be a second copy to keep in step.

## Model

`blaze_face_short_range.tflite` is BlazeFace short-range (float16), the model
MediaPipe's own Face Detector guide names for a face **within 2 m of the
camera** — which is the owner's desktop case verbatim. Model card and licence:
<https://ai.google.dev/edge/mediapipe/solutions/vision/face_detector>.
