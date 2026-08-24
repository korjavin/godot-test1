# Lobby service

The only server in the multiplayer architecture. It does **signalling, membership
and master-naming** — and nothing else. No game logic, no game state, no database:
rooms live in memory, and a restart simply drops them (clients re-create a room
from its invite code).

Everything else about the multiplayer feature is peer-to-peer.

## Protocol

Connect a websocket to `wss://<host>/ws?room=<CODE>&name=<label>`.

- An **empty or unknown** `room` creates one; the code comes back in the welcome
  frame. Codes are 6 characters from an alphabet with no `0/O/1/I/L`.
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
  exercise every acceptance criterion by hand, TURN included.
- `GET /ice` — the `RTCPeerConnection` config, built from the STUN/TURN
  environment variables, so credentials never get baked into the game build.
- `GET /healthz` — `{"ok":true,"rooms":N}`.

## Running it locally

```bash
cd server
go test -race ./...     # the acceptance criteria, over real websockets
go run .                # then open http://localhost:8080 in two tabs
```

## Deploying

Standard git-ops compose stack: CI builds the image, pins it on the `deploy`
branch and pokes Portainer, which re-pulls.

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
