# Lobby service

The only server in the multiplayer architecture. It does **signalling, membership
and master-naming** — and nothing else. No game logic, no game state, no database:
rooms live in memory, and a restart simply drops them (clients re-create a room
from its invite code).

Everything else about the multiplayer feature is peer-to-peer.

## Protocol

Connect a websocket to `wss://<host>/ws?room=<CODE>&name=<label>`.

- An **empty or unknown** `room` creates one; the code comes back in the welcome
  frame. Codes are 6 characters from an alphabet with no `0/O/1/I/L`; anything
  else is refused with a `malformed room code` error, since the room map is keyed
  by these strings and a client does not get to pick the key or its length.
- A room holds at most **4** members (the game's player cap); the fifth gets an
  `error` frame and is closed.

### Server → client

| type | fields | when |
|---|---|---|
| `welcome` | `you`, `room`, `master`, `members[]`, `heroes{}`, `pool[]` | first frame, always |
| `peer_join` | `peer{id,name}` | someone joined |
| `peer_leave` | `id` | someone left |
| `master` | `id` | the master changed |
| `heroes` | `heroes{hero:id}` | a hero was claimed or released |
| `signal` | `from`, `payload` | another peer relayed something to you |
| `error` | `error` | your last message was rejected |

### Client → server

| type | fields | effect |
|---|---|---|
| `signal` | `to` (peer id, or `""` for everyone), `payload` (anything) | relayed verbatim |
| `hero` | `hero` (one of `pool`, or `""` to release) | claims a hero, broadcasts `heroes` |
| `stalled` | `id` (the current master) | one vote that the master has stalled |
| `ping` | — | replies `pong` |

The lobby **never inspects `payload`** — WebRTC offers, answers and ICE candidates
all travel through the same relay.

### Master naming

The master is the **oldest surviving member**. It is re-named when the master
disconnects, and when strictly more than half of the *other* members send a
`stalled` report naming it (2 of 3 non-master peers, 1 of 1, and so on). Stall
*detection* is client-side and belongs to a later phase; the lobby only counts the
votes. A peer voted out is never elected again while the room lives — unless every
remaining member has been voted out, in which case the slate is wiped rather than
leaving the room master-less.

### Other routes

- `GET /` — a plain-JS test page (embedded in the binary). Open it in two tabs to
  exercise every acceptance criterion by hand, TURN included. **In production this
  page is shadowed by the game client** — see [Routing](#routing) below; reach it
  by running the lobby locally, or by hitting the container directly on the host.
- `GET /ice` — the `RTCPeerConnection` config, built from the STUN/TURN
  environment variables, so credentials never get baked into the game build. It is
  fetched cross-origin (the game is on GitHub Pages, the lobby on its own host),
  so it sends `Access-Control-Allow-Origin` — honouring `LOBBY_ALLOWED_ORIGINS`
  rather than a blanket `*`, because the body *is* the TURN credentials.
- `GET /healthz` — `{"ok":true,"rooms":N}`.

## Running it locally

```bash
cd server
go test -race ./...     # the acceptance criteria, over real websockets
go run .                # then open http://localhost:8080 in two tabs
```

## Routing

The stack serves two containers on one hostname. Traefik matches the most
specific router first (higher `priority` wins), so:

| router | rule | priority | container |
|---|---|---|---|
| `godot-lobby` | ``Host(`$LOBBY_HOST`) && (Path(`/ws`) \|\| Path(`/ice`) \|\| Path(`/healthz`))`` | 10 | this service |
| `godot-web` | ``Host(`$LOBBY_HOST`)`` | 1 | the Godot web export on nginx |

So `https://$LOBBY_HOST/` is the **game**, and the lobby keeps exactly the three
paths it needs. The consequence to remember: the embedded test page at `/` is
unreachable in production — it is not gone, just out-ranked. Add a path to the
lobby's rule if you ever need it back.

The client image is `ghcr.io/korjavin/godot-test1-web`, built from the same web
export that goes to GitHub Pages (so the game is served from both). Both it and the
lobby image are SHA-pinned on the `deploy` branch — see *Deploying* below.

Both containers need `Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: require-corp` on the game's HTML — Godot's export
needs `SharedArrayBuffer` — which is the whole of `web/coop-coep.conf`.

## Deploying

Standard git-ops compose stack: CI builds the images, pins them on the `deploy`
branch and pokes Portainer, which re-pulls.

**One job owns the deploy branch.** `deploy-stack` in
`.github/workflows/build.yml` builds *both* images (lobby from `server/`, client
from the web export), pushes them tagged with the commit SHA — never `:latest` —
then rewrites both `LOBBY_IMAGE` and `WEB_IMAGE` in this directory's compose file
in a single commit and force-pushes `deploy`. It is gated on this workflow's test
job, which it calls (`workflow_call`) rather than copying — `needs:` cannot reach
across workflows, so without that a master push could publish a lobby that fails
`go test`. The branch is maintained by
force-push, so a second workflow writing it would reset it to its own checkout and
clobber the other's pin; keeping one writer is why `lobby.yml` now only tests.
The cost, accepted: the lobby image rebuilds on every master push rather than only
on `server/**` changes. To roll back, set `LOBBY_IMAGE`/`WEB_IMAGE` in the stack's
environment to an older `:<commit-sha>` tag.

1. **GitHub secret** — Settings → Secrets → Actions → `PORTAINER_REDEPLOY_HOOK`,
   the stack's webhook URL from Portainer. (The workflow skips the poke when the
   secret is absent, so the image still publishes without it.)
2. **DNS** — an `A` record for `LOBBY_HOST` and one for the TURN realm, both
   pointing at the Docker host.
3. **Firewall** — open `TURN_LISTEN_PORT` (3478) on TCP+UDP and the
   `TURN_MIN_PORT..TURN_MAX_PORT` range (49160–49200) on UDP. coturn runs on the
   host network, so these are host ports.
4. **Portainer stack** — repository `https://github.com/korjavin/godot-test1`,
   branch **`deploy`** (not master), compose path **`server/docker-compose.yml`**,
   and the environment variables from [.env.example](.env.example). The four
   without a usable default are `LOBBY_HOST`, `TURN_URL`, `TURN_PASSWORD` and
   `TURN_EXTERNAL_IP`.
5. **First deploy** — push to master (or run the *Lobby service* workflow by hand),
   then hit the webhook once from Portainer.

Traefik terminates TLS and proxies the websocket upgrade with no extra
configuration, so the client URL is `wss://${LOBBY_HOST}/ws`.

### Verifying TURN

Open `https://${LOBBY_HOST}/` and press **Test TURN**: it fetches `/ice` and
gathers candidates with `iceTransportPolicy: 'relay'`, so any candidate at all
proves coturn answered and accepted the credentials. Same check as
[trickle-ice](https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/),
which also works if you paste the `/ice` values into it by hand.

`TURN_EXTERNAL_IP` is the usual thing to get wrong: coturn advertises relay
candidates on that address, so a stale or private value yields candidates that
gather fine and connect to nobody.
