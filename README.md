# Crimekickers: The Endless Road 🐊

An endless-runner adventure in the **Crimekickers universe**, built with **Godot 4.5**.

You are a Crimekicker dropped into an infinite, procedurally generated world. A
trail of coins — the **coin road** — winds off toward the horizon. Follow it as
far as you can: the further you get, the meaner and denser the crocodile piglets
chasing you become. Switch between four heroes on the fly, each with their own
signature power, rack up distance and coins, and try to beat your own best run.
Every run generates a brand-new world.

**▶ Play it in your browser: https://korjavin.github.io/godot-test1/**

Works on desktop and on phones — on mobile you literally **step in place to
walk** and **tilt your phone to steer** (device motion sensors), with on-screen
buttons for everything else.

## The Crimekickers

| Hero | Special (F) | What it does |
|---|---|---|
| **Windman** | Air Rush | Launches into fast gliding flight — ~5× walking speed while airborne |
| **Primm** | Phase Step | Blinks straight through a wall or block, always landing safely on the far side |
| **Teibi** | Resize | Cycles small → giant → normal; giant Teibi **crushes** crocodiles on contact (but can't jump) |
| **Phoboman** | Stink Wave | Expanding stench waves send every crocodile nearby fleeing in terror |

Press **R** to switch heroes mid-run. Abilities run on per-hero cooldowns —
watch the radial dial in the top-right.

## How a run works

- **Distance is your score** — how far from the spawn you've pushed. Your best
  distance and coin haul are saved (they survive page reloads) and a **NEW
  BEST** flash greets a record run.
- **Coins pay off**: follow the coin road for a steady trickle, watch for rare
  **purple gems worth 10**, and keep a pickup streak alive for a score
  multiplier of up to ×5. Every 75 coins banks an **extra life** (up to 5).
- **The crocodile piglets mean it**: they outpace a walking player, and get
  faster and more numerous the further you go, while the coin road narrows.
  Running, jumping, and your hero powers are how you stay ahead.
- **3 lives**: a bite costs one (you keep your coins and your spot). Lose them
  all and it's game over — Enter, Space, or a tap starts the next run in a
  freshly generated world.

## Controls

### Desktop
| Key | Action |
|---|---|
| **W / S** | Walk forward / back |
| **A / D** | Turn |
| **Q / E** | Sidestep |
| **Mouse** | Look around |
| **Space** | Jump |
| **Shift** | Run |
| **Ctrl** | Duck |
| **R** | Switch hero |
| **F** | Special ability |
| **P** | Pause |
| **Esc** | Release / recapture the mouse |
| **F3** | Performance overlay |

### Mobile (web build)
Open the game on your phone and tap the start overlay (this also grants iOS
motion permission). Then:
- **Step in place** to walk — your phone's motion sensors detect your steps
- **Tilt** the phone to steer (or toggle to **twist** steering on screen)
- On-screen buttons: **Jump**, **Special**, **Switch hero**
- The **⚙ Tune** panel lets you calibrate step detection and steering live;
  your settings persist between visits

## Running from source

Requires **Godot 4.5** (standard build): https://godotengine.org/download

```bash
# Open in the editor
godot project.godot

# Run the game from the CLI
godot --path . scenes/main.tscn

# Headless web export (needs the "Web" export preset + templates)
mkdir -p build/web && godot --headless --export-release "Web" build/web/index.html

# Serve a local web build (WebAssembly needs HTTP, not file://)
./serve.sh        # macOS/Linux    serve.bat on Windows
```

See [QUICKSTART.md](QUICKSTART.md) for the 5-minute version.

## Multiplayer (dev setup)

2–4 browsers in a room run through the **same** world (shared seed) and see each
other move. The shipping target is the **web build, which needs no extra setup** —
browsers already speak WebRTC.

**Desktop needs one addon.** Godot's desktop builds ship the WebRTC *classes*
but no implementation, so testing with two editor instances needs the official
[`webrtc-native`](https://github.com/godotengine/webrtc-native) GDExtension.
From a fresh clone, one command installs and verifies it:

```bash
./fetch_webrtc_addon.sh
```

It downloads a pinned release, checks the SHA-256, unpacks it to
`addons/webrtc/`, and — if `godot` is on your PATH — proves it works:

```
Checksum OK.
Installed to …/addons/webrtc (gitignored).
Verifying...
WEBRTC OK
```

Then **restart the editor** (Godot loads GDExtensions at startup). You can
re-run the proof at any time:

```bash
godot --headless --path . --import      # only needed on a never-opened clone
godot --headless --path . --script res://scripts/webrtc_addon_check.gd
```

Two instances joining one room, end to end:

```bash
godot --path . scenes/main.tscn   # run this twice; one clicks Host, the other
                                  # pastes the 6-character code into Join
```

Both reach the deployed lobby at `wss://ck.wandergeek.org/ws` by default, so no
local server is needed — see below to point them at your own instead.

`addons/` is **gitignored — the addon is fetched, not vendored.** It is 37 MB of
prebuilt binaries for twelve platform/arch pairs that the production build never
uses (browsers have WebRTC built in), and its bundled libraries are MPL-2.0,
which attaches source-availability duties to anyone redistributing them. The web
export excludes `addons/*` outright, so an installed addon cannot change the
build CI publishes. Without the addon the MP panel says WebRTC is unavailable
and the rest of the game plays as normal.

**Iterating against a local lobby.** Run the Go lobby from `server/`:

```bash
cd server && go run .        # http://localhost:8080, websocket at /ws
```

Then point the clients at it. A build with no override talks to the **deployed**
lobby (`LobbyClient.DEFAULT_LOBBY_URL` = `wss://ck.wandergeek.org`), so an
override is only needed to test against a lobby running on your own machine.

```bash
# Two desktop instances (needs ./fetch_webrtc_addon.sh) — run this twice
godot --path . scenes/main.tscn -- --lobby=ws://localhost:8080

# Or the web build, opened in two tabs
./serve.sh   # then visit http://localhost:8000/?lobby=ws://localhost:8080
```

One side clicks **Host** and shares the 6-character invite code; the other pastes
it into **Join**.

## How it's built

The codebase is written to be read — scripts are heavily commented, explaining
*why* along with *what*. Highlights:

- **Everything is procedural.** The infinite terrain, the decorative blocks,
  the crocodiles, and the coin road are all generated in code, deterministically
  per run — revisit a spot and it's exactly as you left it; restart and the
  world is new. There is no hand-placed scenery.
- **The characters are code too**: their 3D models are generated by Python
  scripts (`scripts/generate_*.py`), and all animation is procedural — sine
  waves on limbs, no keyframes.
- **The audio is synthesized at startup** — every blip, whoosh, and sting is an
  `AudioStreamWAV` baked in code. There are zero audio asset files.
- **Tuned hard for the browser**: MultiMesh batching, per-chunk consolidated
  collision, simulation LOD that sleeps far-away crocodiles, and web-specific
  render settings keep it smooth on a phone.

Architecture notes for contributors (and AI assistants) live in
[CLAUDE.md](CLAUDE.md).

## CI/CD

Every push builds the web export via GitHub Actions
(`.github/workflows/build.yml`). Pushes to `master` deploy straight to GitHub
Pages — merging is releasing.

## In the works

Visual overhaul (art-directed lighting, sky, fog, bloom), first-person view
toggle, giant road bosses, lost-civilization artifacts, biomes (deserts,
forests, rivers, mountains), weather with rain that grounds Windman, and
migrating elephants and giraffes.

## License

See [LICENSE](LICENSE).
