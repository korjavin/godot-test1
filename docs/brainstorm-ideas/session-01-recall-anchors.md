# Session 01 — Recall Anchors, Recall Pressure, and the signal horizon

**Date:** 2026-08-27 · **Participants:** Claude + Codex (peer-chat), owner steering.
**Status:** design fiction. Nothing here is built. No beads issues filed yet.

The brief: *invent a challenge that makes players cooperate in multiplayer, or switch
characters in singleplayer, in order to progress* — and hang a story on it.

Read [README.md](README.md) first; it holds the constraints this design is shaped by.

---

## 1. The story we are telling

Taken from the lore vault, lightly adapted.

Project AEGIS-4 fractured in a lunchtime accident and walked out as four people.
**GastroDefense Inc.** — the corporation that built it — is recalling the prototype, and
the recall is *not* a vendetta. It is a **workflow**: a contract performance notice, a
ticket, a department resuming function. `RETURN TO ORIGIN FACILITY` decodes to
**reintegration = un-make**, irreversible, with the consent field deleted from the spec.

That gives us the two best things a runner can have and rarely gets:

- **A reason to run that is not a score.** You are not fleeing a monster. You are
  outrunning *paperwork*, and paperwork does not get tired.
- **An antagonist that needs no boss fight.** GastroDefense is evil by quarterly report.
  The pressure it applies can be a *meter*, not a creature — which is lucky, because the
  boss crocodiles on road stations are already the entire fight budget.

**The destination:** the still-warm **AEGIS-3** fragment signal — proof the four are not
the first, and the only lead that isn't owned by the people recalling them.

## 2. The core mechanic — Recall Anchors

A **Recall Anchor** is GastroDefense field hardware that spawns deterministically on the
coin road. It carries up to four **sockets**, each keyed to exactly one hero's ability,
drawn from the canon vulnerability table so that *the fiction and the mechanic are the
same fact*:

| Socket | Held by | Fiction | Getting there |
| --- | --- | --- | --- |
| Pressure seal | **Windman** | reads atmospheric pressure; only he registers | Air Rush to a raised or distant pad |
| Steel mass | **Tiebi** | too heavy to phase — it has to be *out-massed* | giant form crosses the hazard |
| Vent crawl | **Primm** | a gap under a low overhang; giant is impossible here | Phase Step cuts across |
| Scanner field | **Pho-boman** | alarms on any incident-signature; he carries none | walks in clean, no ability needed |

Sockets read **which hero you are**, not which ability you fired — see §3 for the code fact
that forced this, and why it makes the design better.

The Pho-boman socket is the prettiest one: it is not a power, it is an *absence*. He is
the only one the drone net cannot see, because he was born of broth rather than remade by
the fracture. The mechanic is canon, not invention.

### It moves. It is not a toll booth.

**Codex's best contribution, and the design pivots on it.** An anchor is an
**8–12 second flow challenge that travels through the road at run speed**, not a puzzle
you stop and solve. Beams and pads sweep past while everyone keeps moving.

- **Skipping is clean** — no penalty at the moment of skipping, no fake wall.
- **Partial engagement** pays ordinary salvage.
- **Full solve** pays a rare **AEGIS coordinate shard** and vents Recall Pressure.
- **A miss puts anchors on cooldown**, so a failure restores flow instead of immediately
  demanding a retry.

This is what keeps the endless runner an endless runner. A stop-and-solve puzzle every N
stations would kill the flow state that is the entire appeal.

## 3. Hands versus locks — the scaling rule

The question was: *in multiplayer a peer is assigned one hero, so a two-player room has
only two abilities and can never open a four-socket anchor.*

**It is already solved by the architecture, and nobody had noticed.**
`mp_manager.my_character_indices()` returns `null` or an **array**, and
`player_controller.switch_to_next_character()` already cycles within that array. Its
docstring even says the set form "costs nothing and needs no special case if that ever
changes." So the lobby can deal each peer a **hand** of heroes scaled to room size:

| Room | Hand per peer | Texture |
| --- | --- | --- |
| Solo | all four | **Relay.** Sockets re-seal on a timer, so you open one, press E, sprint, open the next before the first closes. The switch key *is* the skill. |
| 2 players | two each | **The signature case.** Coop *and* switching under pressure, simultaneously. The most interesting of the three. |
| 3 players | one each + one floater | Coordination with one flexible player. |
| 4 players | one each | Pure coordination, no switching. |

Server change in `server/room.go`; **zero client change**.

### The phased anchor — *settled*

This went through three rounds and landed somewhere better than either starting position.

**Codex opened with roster-aware lock compilation** — the anchor resolves its sockets at
spawn from the actual room roster and current weather, so it always fits the hand present.
I pushed back on two grounds, and codex withdrew the weather half completely:

1. **The weather half cannot work.** `weather_manager.gd:330` calls `_rng.randomize()`,
   and the file says at line 240 this is cosmetic-only RNG, deliberately not the seeded
   stream. Rain is **per-client**. A shared puzzle reading rain is open for one player and
   sealed for another with no packet to blame. Environmental gates must come from
   `biome_at()` / `is_river_at()`. (Snow biome is the canon cold zone for Pho-boman; the
   river band is the canon wet for Windman — both are shared truth for free.) Client-local
   rain stays what it is today: a personal *ability presentation* gate.
2. **If the anchor always fits your hand exactly, there is no puzzle, only labour.**

**I counter-proposed quorum:** sockets fully deterministic from station index + `run_seed`,
and the only roster-dependent number is *how many must be held at once*.

**Codex then broke my proposal, correctly.** Quorum alone guarantees a *possible* solve but
**does not force a single switch**: in a 2-player room each player parks their currently
active hero on one of two valid sockets, satisfies quorum = 2, and finishes having never
pressed E. Same bypass for the 3-player floater. That defeats the entire purpose of the
feature.

**The settled answer — a deterministic phased anchor.** All four sockets, and the anchor
requires *every* socket across a fixed sequence of short quorum-sized holds. After each
successful hold, the next group lights.

My first exclusion rule — *"a hero used in the prior phase cannot count in the next"* —
**was broken, and codex caught the arithmetic.** It dies on the 3-player floater: a
quorum-3 hold consumes three of four heroes, so exactly one unused hero remains and a
second quorum-3 phase is impossible.

**The fix is an explicit phase schedule by room size**, minted at activation. Sockets are
`A B C D` (Windman / Tiebi / Primm / Pho-boman):

| Room | Hands | Phase schedule | What it forces |
| --- | --- | --- | --- |
| Solo | A B C D | `{A}` `{B}` `{C}` `{D}` | full rotation through all four before the first re-seals |
| 2 players | A B · C D | `{A,C}` then `{B,D}` | **both players must switch** — coop *and* switching at once |
| 3 players | A B · C · D | `{A,C,D}` then `{B,C,D}` | the floater switches while the other two sustain the hold |
| 4 players | A · B · C · D | `{A,B,C,D}` once | pure coordination, no switching — correct for that size |

This is small **roster-aware schedule state**, not geometry generation. Every client still
sees the same four seeded sockets. One shared geometry, and the hand finally matters.

### The switch-safe route contract

Identity-as-key does **not** fully sidestep the switch lock, and I overclaimed when I said
it did. The lock is on the *cast*, not on the pad: if Tiebi goes giant to **cross** the
route, he is locked out of switching for ten seconds regardless of how the pad reads him.

So the anchor contract must guarantee a switch-safe relay route:

- **No required traversal cast before a forced handoff.** If the only way to reach the pad
  is an ability, that phase cannot be followed by a switch.
- Abilities are **optional shortcuts with an explicit commitment trade-off** — take the
  fast route and accept that you are committed for its duration.
- **A mandatory cordon must not start its timer while a required hand is state-locked.**

That last clause is the difference between a hard challenge and an unfair one.

### Sockets read identity, not casts — *a code fact forced this*

The phased anchor assumes a player can switch between phases inside an 8–12 second window.
**In the current code they often cannot.** `player_controller.gd:1271` blocks
`switch_to_next_character()` outright while `windman_boost_timer > 0.0` or
`teibi_size_state != 0`, and the constants are `WINDMAN_BOOST_DURATION = 4.0` (line 2538)
and `TEIBI_FORM_DURATION = 10.0` (line 2563).

So a solo player who *fires* Tiebi's Resize is locked out of switching for ten seconds —
longer than the entire anchor. Air Rush eats four of the twelve. **If sockets are opened by
casting abilities, the phased relay is not tight, it is impossible.**

**Therefore a socket is opened by identity, not by casting.** You hold the pad *as* the
right hero, and the pad reads which character you currently are. This:

- sidesteps the ability lock completely, with no retuning of two constants that exist for
  good reasons;
- matches the "hold" semantics the phase design already uses;
- retroactively makes Pho-boman's scanner socket **consistent** with the other three
  instead of the odd one out — his key was never a power, it is an absence.

And it produces a better division of labour: **abilities become the traversal layer, not
the key layer.** Air Rush is how you reach a far pad in time, Phase Step is how you cut
across to the next one, giant form is how you cross a hazard between pads. *The ability is
how you get there; the identity is what opens it.*

## 4. Recall Pressure — why skipping costs something

I originally framed anchors as optional content. **Codex was right that this is the weak
joint:** on an infinite field where speed is the dominant loop, optional lore is rational
to bypass, and the cooperation challenge quietly becomes side content nobody sees.

The fix is a **Recall Pressure meter**. Bypassing anchors advances it; resolving one vents
it. As it rises, hazards thicken and rewards thin. It never blocks passage, so there is no
fake wall — it makes the *decision* meaningful instead.

This is not a contrivance bolted onto the fiction. It **is** the fiction: GastroDefense's
threat in the vault is precisely "a workflow resuming, a deadline elapsing, a department
being notified, a firmware update bolting new behavior onto a fleet that was never
validated for it." An escalating ticket is the canon antagonist, rendered as a bar.

It also has a home in shipped code: the danger vignette and heartbeat loop already read a
scalar and paint the screen edge with it.

## 5. The spine — signal resolution, not kilometres

A destination that steadily approaches is a broken promise in an infinite runner: players
will correctly ask why it never arrives.

**Codex's answer, which I think is right:** AEGIS-3 is a concrete, *visible* horizon
object — a broken intake tower / industrial-kitchen silhouette — but it is an
**intermittent signal image**, not a physical endpoint. It sharpens, shifts position and
reveals new architecture each time enough coordinate shards decode a notebook page. Each
run shows visible "we are getting a fix" progress, while the real long-form axis is
**signal resolution**, not distance.

And behind you: **GastroDefense's return geometry closing in.** Then the screen states the
central conflict at a glance — *chase the warm echo ahead, while the consentless recall
gains ground behind.*

This lands on infrastructure that already exists: `progression.gd` is deliberately
run-independent, and `best_run_store.gd` merges every field with a monotone `max`. Lifetime
coordinate shards are the same shape as lifetime coins and need **no new persistence layer**.

### The notebook

The **Junior Engineer's lab notebook** is the delivery vehicle for the 20-episode arc —
lore drops at milestones, no cutscenes. Codex's refinement, accepted: do **not** gate pages
behind perfect anchor solves. Award *encrypted shards* from pressure relief and decode a
page at milestones, so skipping an anchor changes difficulty and pace without permanently
locking the plot.

## 6. A chaptered world — author the grammar, not the metres

Late in the session the owner reopened the biggest constraint:

> it's not carved in stone that it should be endless random world, we can change this to
> some kind of story-adapted world if needed

That makes walls legal, and much of the design above was contorted specifically to avoid
needing one. **Both of us landed on chaptered rather than hand-authored**, for the same
reason: the procedural engine is not sentiment, it is three load-bearing things.

1. **Determinism is our netcode for world content.** Two peers see the same crocodile in
   the same place with zero packets. A hand-authored level does not get that for free — it
   gets it by shipping the same scene file, then desyncing the moment anything is dynamic.
2. **Chunk streaming and the LOD manager exist because the web `gl_compatibility` build is
   the perf target.** A large authored world does not stream itself.
3. **`run_seed` re-rolls per run** — the entire reason a second run is worth playing.

So: keep the engine, and make the world story-shaped by making the **act a pure function of
station index** — already monotonic along +X, already the score axis. Each act gets its own
biome mix, predator species, anchor cadence and notebook pages. And because the axis is now
a story rather than infinite sameness, **an act boundary is allowed to be a real
GastroDefense cordon** — the wall we previously could not justify. Endlessness survives as
the tail: past the last authored act the generator goes back to being infinite, which is the
endless mode the game already is.

**Designed journey, procedural realization.** Reserve authored scenes for horizon landmarks
and tiny transition pockets — never for traversed level geometry.

### `ActSpec` — an act is a data row

Codex's model, and it is exactly this codebase's idiom: a const dict of plain dicts, no
class hierarchy and no custom `Resource`, the same shape as `SPECIES` in
`piglet_crocodile_ai.gd` and `SKILL_TREES` in `progression.gd`. Adding an act is adding a
row. Each `ActSpec` owns:

station range · deterministic biome & species weights · anchor cadence · horizon landmark
treatment · notebook pool · `CordonSpec`

**Freeze the act profile for the lobby at run start.** This matches how `run_seed` already
travels — over the lobby relay rather than the mesh, precisely because it must arrive before
any data channel opens.

### I understated the state boundary — codex caught it

I said `act = f(station)` "costs one dispatch function and breaks nothing." That is true of
the **geometry** and false of the **state**. Cordon spec *selection* is pure from
`run_seed` + station, but **activation, held-lock state, phase completion, disconnect
handling and chapter unlock** are none of those things. That is the one genuinely new piece
of netcode in the whole design, and it should be said out loud here rather than discovered
during implementation.

### Where authority lives — split by timescale, not by ideology

This was the sharpest argument of the session and it went three ways.

**Codex's position:** strike "server-side" entirely; the Go lobby stays membership, master
naming and signalling only. CLAUDE.md backs this: the lobby does **deliberately no game
logic and no game state**, never inspects `payload`, and that opacity is explicitly what
keeps game logic off the server.

**The owner's ruling**, in his own words: *"what core rule contradicts server-side? Be
creative, we might challenge some limitations. I am fine with server side SOT."*

**And the owner is on solid ground, because the rule is already broken on purpose.**
`server/best.go` opens with, verbatim:

> THE ONLY PERSISTENT STATE THIS SERVICE HAS, and a deliberate exception to the "no
> persistence on the lobby" rule the rest of the code states (owner order, 2026-08-25).

The stated reason is that client-side storage genuinely does not survive — Safari and iOS
purge IndexedDB for sites without recent interaction, a private window keeps nothing, and
the owner watched every run flash "NEW BEST!" because records were not coming back. **This
exact call has already been made once, on the record, for exactly this class of problem.**

**So: split by timescale.**

| Timescale | Where | Why |
| --- | --- | --- |
| Contested sub-second interaction — holds, phase transitions, the 8–12 s attempt | **Master-authoritative, mesh-replicated** | Relaying this through the lobby throws away the entire reason WebRTC is in the project. Crocodiles are the existing precedent: master-simulated, never network-spawned. |
| Durable campaign result — chapter unlocked, Recall Exposure, lifetime shard totals | **Lobby as SOT**, monotone-merged | Exactly what `best.go` already does, for exactly the reason it already does it. |

**The master commits a result; it does not stream a game.** That keeps the lobby ignorant
of socket-level verbs, so the signal relay's opacity survives intact, and it puts durability
where the owner correctly says durability has to live.

**What this does *not* buy: anti-cheat.** I claimed the split "bounds the lying-master
problem" and codex was right to strike it. `best.go`'s own trust model says the endpoint is
intentionally unauthenticated, exactly like `/ice` and `/rooms`, so anyone who knows a
player id can read and raise that record — and the id is client-generated, so a player can
simply mint one and raise every monotone campaign field to its cap, permanently unlocking
all content. **Server-side SOT buys durability, not integrity.** Those are different
properties and conflating them is how a design ships with a false sense of safety.

The mitigating fact is that ids appear in no listing and are not enumerable, so this is
**self**-unlocking, not griefing someone else's campaign. `best.go` already accepts that
trade explicitly — *"the stake is a distance number in a toy game; a login is not worth
building for it."* Content unlock is a slightly higher stake than a distance number, so
**this is an owner decision, not an engineering one**, and it is listed as open below.

Worth stating out loud rather than discovering in implementation: shared bank, lives and
distance today are a sum of per-peer absolute broadcasts with **no authority and no round
trips**. The cordon would be the **first player-facing, multi-step authoritative objective
in this game.**

### `AttemptSnapshot` — the implementation invariant

Codex's, accepted whole. Master activation mints an **immutable** snapshot containing:

`attempt_id` · master peer + **epoch** · `ActSpec` identity · station/seed-derived socket
layout · participant peer IDs **with their assigned hands** · quorum · phase schedule ·
deadline policy

Rules:

- Every hold, phase update, completion, abort and client message carries `attempt_id` plus
  a **monotonic revision**. Clients discard stale snapshots and **render the master's
  state**; they never infer completion locally.
- A **late joiner observes but never enters** that attempt.
- On **participant departure OR master epoch change**, abort immediately to the normal
  miss-cooldown. Do not reconstruct or transfer a partial phase. A silently lowered quorum
  is a griefing vector — join and leave to trivialise an anchor.
- Per-socket latching and progress may be cosmetic client-side, but **phase completion is
  authoritative**.

Codex's clearest sentence, quoted because it is the whole rule in one line:

> The new master may generate future geometry from seed as today, but it may not inherit
> objective progress it did not authoritatively observe.

### Pressure across acts — convert, don't reset

Recall Pressure is **act-local** for tuning and recovery. But simply resetting it at a
cordon would make skipped anchors consequence-free. Instead, **at boundary resolution the
act's pressure converts into a campaign-scale `Recall Exposure` / signal-corruption result**,
and only then does local pressure reset for the next act.

- **Low pressure** → cleaner coordinates and a stronger AEGIS image.
- **High pressure** → GastroDefense's claim advances; stakes and rewards change.

No unstoppable multi-act punishment spiral. And this is the best link in the design: **the
horizon literally sharpens because you did the optional content.**

### Which settles optional-vs-mandatory

- **Inside an act:** moving anchors are **optional mastery**.
- **At the act boundary:** the cordon is the **mandatory quorum set-piece** — a chapter
  climax with one clear shared objective, not a toll booth every few stations.
- **Failure** is a retryable short encounter / checkpoint state, never an irrecoverable
  wall and never a forced run loss.

That is where a physical barrier earns itself.

## What is settled, and what is not

**Settled this session:**

- Recall Anchors are moving 8–12 s flow challenges, never toll booths; miss puts them on
  cooldown.
- Sockets are deterministic from station index + `run_seed`; the anchor is **phased**, with
  an explicit **phase schedule by room size** (not an exclusion rule — that one was broken).
- Sockets read **identity**, not casts. Abilities are traversal — subject to the
  **switch-safe route contract**, because the ability lock is on the cast, not the pad.
- Authority splits **by timescale**: master-authoritative on the mesh for the attempt,
  lobby-as-SOT for the durable campaign result. The master commits a result, not a stream.
- `AttemptSnapshot` is immutable, carries `attempt_id` + monotonic revision; late joiners
  observe only; departure or master-epoch change aborts to the normal miss outcome.
- No shared puzzle may read **weather**. `biome_at()` / `is_river_at()` only.
- The world is **chaptered, not hand-authored**. `ActSpec` is a data row; endlessness
  survives as the tail past the last act.
- In-act anchors are optional mastery; the **cordon at the act boundary is mandatory**, and
  failing it is retryable, never a run loss.
- Recall Pressure is act-local and **converts** into campaign-scale Recall Exposure at the
  boundary — it does not merely reset.
- Recall Pressure replaces "optional content": skipping advances it, solving vents it, it
  never blocks passage.
- The long-form axis is **signal resolution**, not kilometres. Shards are a lifetime
  currency and fit `progression.gd` / `best_run_store.gd` as they stand.
- Notebook pages decode from shards at milestones — skipping changes pace, never locks
  the plot.

**Still open — owner decisions:**

1. **Campaign integrity.** Putting chapter unlock on the lobby as a monotone field means a
   player can mint an id and unlock everything (see §6). Three options: accept it exactly as
   `best.go` already accepts it; keep **chapter unlock local** and put only Recall Exposure
   and shard totals on the server; or build real identity, which nobody wants for this game.
2. **How many acts, and what they are.** Naming them and mapping each to existing biomes and
   predator species. The 20-episode arc is the obvious source, but 20 acts is far too many —
   probably 4, matching the vault's four movements.

**Still open — design:**

3. What a **failed** anchor costs *in fiction*, not just in meter. GastroDefense filing
   something is more on-tone than a damage number.
4. What the cordon **looks like** — it is the first hard barrier this game has ever had, and
   the flat-world invariant still applies to whatever we build there.
5. Whether the shipped **Windman rain gate** should stay as-is once anchors exist. It is
   local-only and harmless today, but it is the one place where a client-local roll changes
   what a player can do.

**Not yet:** no beads issues, and no code. Nothing here is built.
