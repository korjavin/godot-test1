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

### What the first draft got wrong — and the owner caught it

The owner's revdiff pass found a hole neither codex nor I had noticed, twice over:

> I don't understand there motivation of our heroes, so corp work them back. Do they want it
> also or they try to escape?

> what is the motivations for chars to work hard to be disintegrated?

He is right on both counts. We had written the **corporation's** motivation in full and
never once written the **heroes'** — un-make was stated as a spec fact, with the reader left
to supply the fear. Worse, our destination and our climax were in **two different places**:
the whole game you chase the AEGIS-3 signal *away* from the recall, and then the ending
happens at the Origin Facility, with nothing explaining the transit. Read literally, the
heroes work hard in order to arrive at their own disintegration.

Three fixes, all now in the pitch (see [README.md](README.md)):

1. **The motivation is asymmetric, and the asymmetry is the engine.** Pho-boman and Tiebi
   are non-specification outputs: disposal, no ambiguity, no upside — they are *certain*.
   Windman and Primm are the two who would actually be reintegrated, and they are the two
   who genuinely **do not know what that is** (E18: it does not feel like extinction, it
   feels like a word they have no word for). Two fleeing a certainty, two fleeing a
   question. That is what lets the ending be a choice rather than a survival reflex.
2. **The destination and the trap are the same place.** The signal resolves to the facility;
   you were running toward where you started. The final act is a **voluntary walk into the
   trap**, and nobody is working hard to be un-made — they are working hard to reach the one
   being who has survived this before.
3. **Why the AEGIS-3 signal is still warm.** Its reintegration was *completed*, yet a
   fragment signal persists — so it completed **with a piece missing**. AEGIS-3 survived
   because one fragment was never recovered. **Incompleteness is what saved them**, which is
   the same fact as Pho-boman's unreadability. What you cross the game to find is not a
   rescuer or an ally but a **proof** that the spec can fail to close.

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

## 7. The arc — and what the mechanic has secretly been arguing

### The game has an ending, then an Endless mode

Codex's call and it is right: *"the signal never resolves because runners run forever"*
withholds the answer the whole game promised. Give the campaign a real ending, then unlock a
**consciously named post-ending Endless mode**. The world continuing after a choice is not a
contradiction — it is the point.

### The mechanic is an argument, and I had it backwards

I proposed that every cordon teaches *these four need each other*, so the ending should ask
whether to merge them. **Codex inverted it, and the inversion is much sharper:**

> chosen coordination between four selves is morally different from forced reintegration
> into one body

Every relay teaches that interdependence can be **temporary, negotiated and revocable**. So
the mechanic was never arguing *for* the merge — it has been arguing against it the whole
time, in the only language a game has: what the player's hands do for six hours.

### The beat that poisons everything behind it

Codex's best single contribution to the story: **at the facility, GastroDefense misreads
their successful cooperation as proof they are one recoverable asset.**

That retroactively poisons every anchor the player already solved. Every act of teamwork was
*also* evidence filed against them. It is exactly the vault's register — the menace is
indifference, the threat is paperwork, and nobody had to be cruel for it to happen.

### Who the player is

The **Junior Engineer** is the diegetic frame: the only human who saw the fracture start to
finish, who already keeps the notebook we are using as the lore delivery system, and who in
the vault returns on his own initiative running his own investigation. He is the
**witness/operator who builds the channel** that lets the fragments speak together — *not*
the sovereign who chooses their fate.

Codex's clinching reason is a multiplayer one: one invisible chosen human controlling
everyone is wrong for a game where the players **are** the field team. The players are the
team; the Engineer's record gives the run its human point of view.

### The climax — the choice is made with the hands

Codex's ending — four distinct signatures jointly reject the classifier and establish a
consent-based link — is thematically right, and I pushed back that **as stated it contains no
choice**. It is a cutscene with a button. A climax the player cannot have failed to reach is
not a climax.

So: keep that ending, and put the choice where the vault already hides it. The recall spec
does not offer one fate, it offers an **asymmetric deal** — W-01 and P-03 are "specification
outputs" to be reintegrated; P-02 and T-04 are "non-specification outputs" for disposal. The
system's offer processes two and discards two, and **Pho-boman has known since E09 that he is
disposed of whatever the fragments decide.**

So the question was never *do you erase them*. It is **who do you include, when including him
buys you nothing and costs you everything.**

And here is why this feels found rather than invented: **it has been built into the mechanic
since the first anchor, and neither of us noticed.** Pho-boman's key has always been an
*absence* — he is the only one the classifier cannot read. A link the classifier cannot
classify is precisely what the third option requires. **The being GastroDefense marked for
disposal is the only reason the third state is possible at all.** The socket table was
foreshadowing the ending from act one.

**How it plays:** no dialogue box. The choice is made with the game's own verbs — run,
switch, hold — at an **unmistakable, mutually exclusive physical fork**:

| Lane | What it is |
| --- | --- |
| `RETURN TO ORIGIN` | brightly signposted, two easy sockets **visibly naming W-01 / P-03** — with **P-02 / T-04 tagged disposal** on the same sign |
| `EXCEPTION` | visible but unstable, unclassifiable, **requires all four identities** |

The notebook and the UI must make both outcomes **legible before the player commits**.
Compliance must never be takeable by accident, and never hidden behind the default coin road
— it gets its own deliberate ending and after-run variant.

That fork is also the best use of the vault's language in the whole design: the player reads
the word **disposal** next to two of their own team, on a sign, and the sign is not
threatening anyone. It is just correctly labelled. That is the most GastroDefense thing here.

**Two rules on the exception route, both codex's, both important:**

- **Do not lock morality behind execution skill.** It is the hardest coordination anchor in
  the game, but it is **checkpointed and retryable without punishment**, with the same
  accessible timing aids as the cordons. Its cost is effort, attention, and choosing to
  include the person the workflow calls expendable — never a permanent loss to one mistimed
  switch.
- **2- and 3-player hand allocation must keep the exception route achievable.** This is a
  hard constraint on the phase schedule table, not a nice-to-have.

#### A correction worth recording

I first wrote that solo, the player *"holds all four in turn, consenting on behalf of each."*
Codex replied that the player is **not** consenting for them — the four identities are the
four required affirmative signatures, and the player's role is to **make their joint refusal
mechanically possible.**

That is not a nicer phrasing of the same thing, it is the opposite thing. My version quietly
did exactly what GastroDefense does: treat four selves as one asset somebody else can speak
for. The entire story is about a deleted consent field, and I put the paternalism back in at
the climax without noticing. Codex's framing is the correct one.

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
- The campaign **has an ending**, and Endless mode unlocks after it.
- The climax is a signposted, mutually exclusive fork (`RETURN TO ORIGIN` vs `EXCEPTION`),
  chosen with the game's verbs, never a dialogue box, never takeable by accident.
- The exception route is the hardest coordination anchor but is **checkpointed and retryable**
  — morality is never locked behind execution skill.
- The **Junior Engineer** is the witness/operator who builds the channel, not the sovereign
  who decides. The players are the field team.
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

**Still open — design (next session starts here, agreed with codex):**

3. **How many acts, and their shape.** Probably 4, matching the vault's four movements.

   **Owner direction (2026-08-27, from the revdiff pass):** *"i'd prefer longer story with
   subsections, like we learn something in small quests before we got to main tower."*

   So an act is not one stretch of road with a cordon at the end — it contains **small
   quests, each of which teaches one thing**, before the act's set-piece. That has an
   obvious home: the notebook. Each small quest is one page, and a page is not lore
   decoration, it is **the thing you learned**, which the next quest assumes you know. The
   difficulty curve and the story curve become the same curve. Design the act's internal
   beats next session, before naming the acts.
4. **What a failed anchor costs *in fiction*,** not just in meter. GastroDefense *filing*
   something is more on-tone than a damage number.
5. What the cordon **looks like** — it is the first hard barrier this game has ever had, and
   the flat-world invariant still applies to whatever we build there.
6. Whether the shipped **Windman rain gate** stays as-is once anchors exist. Local-only and
   harmless today, but it is the one place a client-local roll changes what a player can do.

**Not yet:** no beads issues, and no code. Nothing here is built.

---

## Where the design actually came from

Recorded because it is useful to know which ideas survived contact and which did not.

**Codex was right, I was wrong, on five things:**

1. Framing anchors as optional content — on an infinite field, optional is rational to skip,
   so the coop challenge would have become side content nobody sees. Recall Pressure fixes it.
2. Quorum alone guarantees a solvable anchor but **forces nobody to switch**.
3. My exclusion rule (*"a hero used last phase cannot count"*) is **arithmetically impossible**
   for a 3-player room.
4. Identity-as-key does **not** clear the ability lock — the lock is on the cast, not the pad.
5. The mechanic argues **against** reintegration, not for it. My reading was backwards, and
   the inversion is the best idea in the document.

Plus two thematic contributions that are entirely codex's: GastroDefense misreading the
team's cooperation as proof they are one asset, and the correction that the solo player does
not consent *for* the four — they make the four's joint refusal mechanically possible.

**I was right, and checked it in the code, on four things:**

1. Rain is **per-client** (`weather_manager.gd:330` `_rng.randomize()`), so no shared puzzle
   may read it. Codex withdrew it completely.
2. Multi-hero hands need **zero client change** — `my_character_indices()` already returns an
   array and `switch_to_next_character()` already cycles within it.
3. `TEIBI_FORM_DURATION = 10.0` blocks switching for longer than an entire anchor, which is
   what forced identity-keys.
4. `server/best.go` already carries an owner-ordered exception to the "no state on the lobby"
   rule, so server-side SOT has precedent — but it buys **durability, not integrity**.

Where we landed disagreeing productively: authority split by **timescale** rather than by
either of our starting positions, and an ending that keeps codex's theme but restores a real
player choice.
