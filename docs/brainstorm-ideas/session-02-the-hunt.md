# Session 02 — The Hunt, the abduction, and the return

**Date:** 2026-08-27 · Owner's idea, polished with Codex over peer-chat.
**Status:** design fiction. Nothing built.

Read [README.md](README.md) for the constraints and [session 01](session-01-recall-anchors.md)
for the identity-gate mechanic this builds on.

---

## The core rule, corrected

**This supersedes session 01 §3.** The owner rejected simultaneity outright:

> Не надо обязательно, чтобы все вчетвером или все трое в каком-то месте. Главное, чтобы в
> процессе игры тебе обязательно было нужно переключаться.
>
> *(There's no need for all four, or even all three, to be in one place. The essential thing
> is only that during play you must switch.)*

So the rule is **sequential gating, not simultaneous holding**:

> A route contains places that only a specific hero can pass. You cannot play as one hero
> the whole way. **You must switch as you go.**

That is the entire requirement, and it is much smaller than what we built.

### What dies

- **Quorum** — the integer that scaled "how many sockets at once" to room size.
- **The phase schedule table** by room size.
- **Simultaneous holds** of any kind.
- **The `AttemptSnapshot` machinery** — attempt ids, monotonic revisions, master-authoritative
  phase completion. If nothing is contested by several players at the same instant, there is
  almost nothing to arbitrate. This deletes what would have been the **first authoritative
  object in the game**, and a genuinely large pile of netcode with it.

Worth being blunt: that was a session's worth of careful design, and it was solving a
problem the owner does not want solved.

### What survives

- **Identity-as-key — and it is now the *only* rule.** A place is passable by *who you are*.
- **The socket→hero table**, unchanged, still drawn from the canon vulnerabilities: pressure
  seal → Windman, steel mass → Tiebi, low vent → Primm, scanner field → Pho-boman.
- **The tower puzzles**, which were already key-and-door rather than simultaneous.
- **Multi-hero hands per peer** — and these are now *more* clearly necessary, not less: a
  route needing all four in sequence must still be completable by a two-player room, so the
  lobby still deals two heroes per peer at that size.

### The one thing that could go wrong

In solo the rule is trivially clear: you meet a gap only Tiebi crosses, you press `E`, you
cross. **In multiplayer it is not.** If a barrier is passable only by whoever is currently
Tiebi, what happens to the other three standing behind it? If each hero merely passes *for
himself*, the party splits and this stops being cooperation at all — it becomes four solo
runs sharing a screen.

**The answer, confirmed and sharpened by codex:** a hero does not *pass* the obstacle, he
**opens it for everybody** — and the gate must be a **shared, persistent route
transformation**, not a personal permission check:

| Hero | Transformation |
| --- | --- |
| Tiebi | moves a mass into a bridge |
| Windman | clears a sealed passage |
| Primm | reaches and unlatches a high/low mechanism |
| Pho-boman | neutralizes a scanner |

> **One hero must be physically present to perform a unique transformation. After it
> succeeds, the route stays changed.**

**And my own wording was the trap.** I wrote *"lifts the gate and holds it"* — codex flagged
that any **sustained hold, countdown, or requirement for followers to cross before release
quietly recreates the simultaneous-gather problem** the owner just rejected. No holding. The
world changes and stays changed.

That keeps the owner's rule exactly — you must still switch, nobody ever gathers — while
making the switching **cooperative rather than parallel**: one player's choice of identity
changes where the whole party can go.

### Two failure modes codex named

**1. Permanent, consequence-free gates make switching a one-time key press.** If every gate
opens forever and costs nothing, one player becomes the doorman and everyone else convoys
behind. The fix: each gate should **reveal the next segment's different identity
requirement**, with traversal and puzzle consequences, and gates must be **distributed so
that every controlled hand has to be selected over the course of a route.**

**2. The post-capture path can softlock, and must be audited now.** Once Primm is abducted,
**no mandatory Primm gate may remain** on any route the three can reach. Either three-hero
routes avoid that identity entirely, or **Windman's resonance scar creates a new, explicitly
weaker substitute route** — which is the better answer, because it makes the abduction
*change how the team travels* instead of leaving an accidental dead end. It also gives his
altered kit (see §"In solo you lose a person") a concrete job outside the rescue itself.

## The idea, as the owner gave it

> GastroDefense realises at some point that the heroes are getting away, and starts an
> actual **hunt** — a team of **hunter robots** whose job is to catch the heroes and carry
> them to the corporation's tower.
>
> The heroes' job is to run. While running they overcome obstacles — the predators among
> them — and they **level up**.
>
> Then the twist: at some point, **inevitably, one hero is caught and abducted**. Primm.
> He becomes an unavailable hero. We show it with a cutscene insert, and **the situation
> flips**: the remaining heroes must sneak back **into** the corporation's tower and get
> him out.

Two associated owner rulings:

- **Reduce the number of predators.** They become one obstacle among several rather than
  the whole threat model.
- An **intro video** explaining the premise will be made separately, in another project.

## Why this is stronger than it first looks

### 1. It is the vault's Movement II, almost exactly

`S01E10 — Half-Life` **is** Primm's capture; `S01E14 — Dead Reckoning` **is** the rescue.
So this is canon-supported and we inherit detail instead of inventing it — including the
mechanism, which is perfectly on-tone:

> Primm is captured **not by tactical cleverness** but because the protocol's containment
> unit is a steel-frame holding structure standard for industrial equipment, and its mass
> incidentally constrains his gravity field.

The corporation does not outsmart him. **It just owns a heavy box.** That is exactly the
register the whole design has been reaching for — the menace is indifference.

It also matches his canon vulnerability (*large metal masses*), so the reason he is the one
taken is a property he has had since the first line of his character sheet. Nobody picked
him for plot convenience.

### 2. It gives the endless runner a reason to turn around

This is the problem we danced around for two sessions. An infinite field has no reason to
reverse. Now the first half is **flight** and the second half is a **return** — and session
01's "the destination and the trap are the same place" stops being a clever reveal and
becomes **the literal shape of the game**.

**And the reversal is free in the scoring system.** Verified rather than assumed: CLAUDE.md
says distance is `global_position.x`, and that is **stale**. The real implementation is
`player_controller.gd:879`:

```gdscript
own_distance = maxi(own_distance, int((here - own_distance_origin).length()))
```

Radial from origin, clamped monotone by `maxi`. **Walking back toward the tower does not
reduce your score** — the high-water mark simply stays. (Difficulty scaling is a separate
question and is listed as open below.)

### 3. It makes the story and the mechanic the same event — again

A four-identity gate needs **all four heroes**. The moment Primm is taken, **every
four-socket lock in the world becomes unsolvable.**

Treat that as the **crisis, not a bug**. The fourth socket stands there lit and unusable,
and that is the emotional payload — the game does not need to tell you what you lost,
because your hands hit it every time you try. Acts after the abduction must be solvable
with three.

**And codex supplied the link back to the ending that I had missed:** show the old
four-person solution becoming impossible, then make **the rescue the act that restores the
party's capacity to choose `EXCEPTION`.** The rescue is not a plot detour — it is what buys
back the ability to refuse at the climax. Get him or the third option is closed to you.

## Hunter robots — capture, not kill

A new enemy class that is **not** a predator, and the distinction is the point:

| | Predators | Hunter robots |
| --- | --- | --- |
| Want | to hurt you | to **retrieve** you |
| Losing to one means | a setback — 7% of coins, a knockback | escalating pressure; **abduction only at the authored turn** |
| Fiction | the world is hostile | the *workflow* has escalated |

**Correction to my own earlier claim.** I told the owner the two enemy classes now carry
different stakes — *a predator costs coins, a hunter costs a hero.* **Codex is right that this
cannot be literally true.** Hero abduction cannot be the repeatable field stake: if ordinary
hunter failure removes heroes, the roster collapses over a long session; and if it can only
ever happen once, it cannot carry the field for the rest of the game either.

So hunters are **escalating pressure** — they cut off routes, force detours, threaten a larger
loss.

> **⚠ Superseded in part, 2026-08-27.** The owner has since made capture **systemic**: a
> hunter that catches you takes **whichever hero was active**, and takes him for real. So
> hunters do *not* cost what predators cost — see "Capture is systemic" below. What survives
> from this section is that hunters must **catch rarely**, which is now more important than
> ever, because each catch is expensive.

**The owner's ruling makes this explicit, and adds a lever:**

> охотник забирает героя — это правильно, но в целом мы, наверное, должны немножко читить,
> так чтобы охотники пугали и мотивировали бегать по полю, но не особенно часто забирали.
>
> *(A hunter taking a hero is right, but broadly we should cheat a little, so that hunters
> frighten and motivate you to keep moving, without actually taking someone very often.)*

So the hunter is a **threat generator, not a loss generator.** The *appearance* of danger is
frequent; the *realisation* of it is rare and largely authored. Near-misses, cut-off routes
and closing pursuit do the work; actual capture is spent sparingly.

**One condition on which this depends entirely: the mercy has to be invisible.** A player who
notices the game is pulling its punches loses the fear immediately, and once lost it does not
come back — a hunter that has visibly failed to catch you twice is scenery.

**Codex supplied the principled way to do it, and it is better than "hunters make mistakes":
tune the mercy in the encounter director, *before contact*, and keep the local hunter rules
completely honest.**

- Spawn most hunts with **at least one viable escape route** and no instant surround.
- Vary approach angle, terrain obstruction, squad composition and warning time.
- Cap simultaneous pursuers; enforce a cooldown after a hard chase.
- **Adjust those hidden setup variables — never grab range or collision after the player has
  already been caught.**
- Once a hunter visibly *earns* a grab, **resolve it consistently.**

Then rarity comes from **favourable encounter geometry plus player counterplay**, not from an
actor visibly pulling its punch. And the thing players *do* learn — how hunters turn, how they
see, how they lose line of sight — is **healthy mastery rather than exposed mercy.** That is
the distinction my "plausible mistakes" version blurred: a mistake the player can predict is
still a tell.

They are the Retrieval Division made visible, and the vault has them: the
**GD-SURVEY-ENTRÉE … GD-SURVEY-DESSERT** field-survey fleet — food-safety inspection units
given an unvalidated asset-recovery firmware update. Machines never designed for this,
doing it anyway, badly and effectively.

**And they are blind to Pho-boman**, who carries no incident-signature. That is already
load-bearing in session 01's socket table, and it now pays off twice: he is the one they
cannot take, which is precisely why he is the one who can walk into the tower.

## The two hard problems

### A. Making an inevitable capture feel earned, not scripted

A scripted loss of agency is the classic way to make an audience feel cheated rather than
moved. **Codex's rule solves it, and it is sharper than mine:**

> **Do not make the player fail at the stated goal.**

- **Telegraph the steel containment** long before it matters, and let players **repel
  earlier probes** — so they have a working model of how hunters are beaten.
- At the capture, set a **survivable objective they genuinely can accomplish**: hold the
  route, tag the carrier, get the others clear, choose which resource gets spent.
- **The outcome is fixed; their performance sets the rescue state** — carrier route, alarm
  level, supplies, allies, which tower entrance is open to them.

So the near-save is **honest rather than fake**: Primm is caught because the heavy cage is a
corporate procedure, while **the team wins the part it was told it could win.** The player
never fails; they are simply not asked to prevent the unpreventable — and every bit of
effort they spent is carried forward into the rescue instead of discarded.

In short: **scripted in outcome, never in texture, and never in the player's own objective.**

### B. Multiplayer — whose hero is taken, and what do they do?

If it is always Primm, one specific human is punished for nothing they did, and then has
**nothing to do**. Dead time in a co-op game is fatal.

**The captured player keeps playing, as Primm inside the tower.** Weakened, no phasing,
because of the steel. The vault supports the state: Primm phases out *himself* at the end of
E14, with a field weakened after 72+ hours in steel. He is not rescued like luggage — he
meets them halfway.

**But not as a second full level.** I proposed a fully simultaneous two-sided level and
codex was right to push back: that needs separate objectives, networking, fail-state rules,
pacing, and *content for both teams* — a second game, effectively.

**The cheap version, which is what we build: a bounded Primm-in-the-cell role.**

The Primm player searches **one containment block**. They:

- read and **mark patrols and routes** for the team outside;
- operate **two or three physical systems from inside** — release a lock, kill a scanner,
  lower an interior lift.

No phasing, no combat loop, **no solo escape**. The three outside reach the corresponding
points. **Every inside action gives the outside team an immediate opening**, so the captured
player is *essential* rather than sidelined — which is the actual requirement. Dead time was
the problem; a second game was never the solution.

If it plays well, expand that block into the richer two-sided rescue later.

## Owner rulings — all four questions answered (2026-08-27)

### 1. Distance is removed entirely

> Забей на градиент… мы можем убрать совсем эту механику про расстояние.

Not "fix the gradient" — **delete the distance mechanic.** This is larger than it sounds and
it is a simplification, not a loss:

- The return-leg problem **dissolves**. There is no longer a number that behaves wrongly
  when you walk back, so the whole difficulty-inversion question disappears with it.
- Session 01's *"signal resolution, not kilometres"* framing retires too — there are no
  kilometres left to contrast against. Progress is quests and story, full stop.
- **The game stops being a score chase and becomes an adventure.** That is the real content
  of this ruling, and every other decision in this session points the same way.

**What it touches** (scope, not resistance): `best_run_store.gd` persists best distance and
merges it to the lobby via `/best`; `game_over_ui.gd` and the HUD display it;
`mp_manager.gd` sums shared distance across the room. Removing the *mechanic* means deciding
what those surfaces show instead. Most other `distance` references in the codebase are
ordinary geometry (LOD radii, spawn checks) and are unaffected.

### 2. Keep every predator — reduce the count

> Оставляем всех, как сейчас, и этих микробоссов, и всех на свете, просто уменьшаем их
> количество. Игра должна стать чуть попроще, потому что мы добавляем квесты, у игрока
> должно быть время.

All species stay, mini-bosses included. Only the **density** drops, and the reason is design
reasoning rather than taste: **quests need time.** A player solving a puzzle cannot also be
sprinting from a wolf pack. Difficulty is being *rebalanced toward attention*, not lowered
out of mercy.

Note this is compatible with the existing rule that entity counts are never reduced *as an
optimization* — this is a **design** change, which is exactly the sanctioned reason.

### 3. The tower is puzzles, not field gates

> в башне тоже будут какие-то охранники, но их будет мало. И там в башне у нас будет в
> основном загадки, квесты… типа найти ключ, потом ключом открыть комнату.

Few guards. Mostly **puzzles and quests** — find a key, use the key to open a room.

So the game has **two tempos**, and that is a feature:

| | Outside | Inside the tower |
| --- | --- | --- |
| Verb | run | sneak, search, solve |
| Locks | identity gates you hit at speed | static gates you stand and think about |
| Threat | hunters and predators | few guards |

The identity-key idea carries across both — *who you are* is still what opens things — but
outside it is a reflex under time pressure and inside it is a deliberate choice. Same idea,
opposite tempo.

### 4. In solo you lose a *person*, not a key

> в соло тоже должен теряться игрок. Просто нужно придумать, как одна личность из этих
> четырёх связанных меняется.

I had proposed that solo loses a *key* rather than a player. **The owner rejected that**, and
set the brief: work out how **one personality among the four linked ones changes.**

The requirement, stated precisely: **the abduction must damage the survivors, not merely
shorten the roster.** A roster is a menu, and pressing `E` past a missing entry is an
inventory event, not a bereavement.

**The answer, agreed with codex.** The loss is felt through the remaining *bodies*, and the
vault names the mechanism: Windman and Primm are the two true fragments of one original,
their incident-signature resonance is strongest between exactly those two, and E10 says that
at the moment of capture **Windman feels the gap where the resonance used to be, and has no
word for it.**

So when Primm is taken, it is **Windman who changes** — because he lost half of himself
rather than a colleague. *You do not lose one hero; you lose one hero and damage another.*
Codex: *"Windman is the only survivor for whom Primm's absence is literally a wound."*

Make it **specific**, not a stat change: altered idle and movement silhouette, broken or
delayed voice responses, different reactions to the others, and a resonance scar that pulls
his attention towerward.

#### Change the kit — do not nerf it

**This is where the idea breaks if we are careless**, and codex named it exactly: if "damage"
means *permanently making the player worse at normal play, after an outcome they were never
allowed to avoid*, that reads as **designer punishment, not grief.**

So Windman's old resonance behaviour **becomes something else**: an unstable but more precise
**rescue-facing** ability — expose a route, sense Primm's containment, interact with tower
systems — carrying a situational cost or a loss of flexibility. He is genuinely not the same
person, he remains **fully viable**, and his new state *matters to the rescue*. Grief without
punishment.

#### Two textures, both corrected by codex

- **The `E` stumble happens once** — at the moment the player first tries to select Primm
  after the capture. My version had it fire every time; codex is right that this *"turns
  remembrance into input latency."* Afterwards the empty slot stays **visibly present**, with
  a small non-blocking echo rather than a hitch.
- **The compass is not a permanent arrow.** I proposed a direction indicator you cannot
  switch off; codex is right that an exact permanent compass *trivializes navigation and
  becomes visual noise*, especially once the tower is obvious anyway. Instead the **scar is
  always present**, but the *direction* pulses or distorts at meaningful junctions and near
  Primm-related systems. **Inescapable as a feeling, not as a GPS** — information only when
  it creates a choice.

## Capture is systemic — heroes are the lives

**Owner ruling, 2026-08-27, and it is the largest single change to the failure system:**

> This type of character that was active on moment of hunter bot caught you now considered
> caught and prisoned in the hq, and player should play without it until liberated in hq.
> **If all caught — game over.**

So:

- **Any hero can be captured, repeatedly** — whoever was *active* at the moment of the catch.
  Not only Primm, and not only once.
- The captured hero is **imprisoned in the HQ** and unavailable until you go and free him.
- **All four captured = game over.** Game over is back, in a new shape.

### What this actually does

**Heroes are now the lives.** We removed lives; they have returned as *the roster itself* —
four heroes, four lives. Except that unlike a life, each one is **recoverable**, and the
tower is where you recover it.

That fuses the failure system with the campaign. The tower stops being optional in a way no
coin penalty could ever have achieved: you do not go there because the story asks, you go
there because your team is in it.

It also finally gives the two enemy classes genuinely different stakes, which is what we had
been reaching for and never quite had:

| | Predator | Hunter |
| --- | --- | --- |
| Costs | **7% of coins**, a knockback | **the active hero** |
| Recoverable? | the coins are gone | yes — by going in after him |

And it makes "hunters catch rarely" *more* important, not less. When a catch was worth 7%,
leniency was flavour. Now every catch is expensive, so the encounter-director tuning above is
load-bearing.

### The failure mode this creates — and it is severe

**The softlock risk multiplies.** The existing rule was "no mandatory Primm gate may remain
while Primm is captive." That is now nowhere near sufficient, because **any subset of the
roster can be captive at once** — fifteen non-empty subsets for four heroes.

The catastrophe is easy to state: the only route to the cells passes a scanner field that
**only Pho-boman** can cross, and Pho-boman is the one in the cell. Three heroes still free,
no game-over triggered, and the run is dead.

My proposed fix was to strip identity gates from the prison route. **The owner's answer is
better:**

> должно быть много путей, hq должен быть масштабен
>
> *(there should be many paths; the HQ should be large-scale)*

**Redundancy, not removal.** Identity gates stay meaningful everywhere — including on the
routes to the cells — and safety comes from there being *more than one way through*. Mine
would have made the most important corridor in the game the blandest one.

And it turns a hand-audit into a **checkable graph property**:

> For every non-empty subset **S** of free heroes, **at least one route to the cells must be
> traversable by S alone.**

With the captives being precisely the heroes *not* in S — so a hero in a cell can never be
the one who opens a gate on the way to his own cell. That makes `tower_selfcheck` load-bearing
rather than nice-to-have: on a large graph, subset reachability is not something a human can
eyeball, and the check can enumerate all fifteen subsets mechanically.

**The cost is real and is being priced in [session 04](session-04-the-tower.md).** "Large,
with many paths" collides with three commitments already on the table: every quest
solo-completable in any order, every subset able to reach the cells, and a project with no
level-design pipeline and a web `gl_compatibility` performance target. It is the biggest
content commitment proposed in any of these sessions.

*Open, with the architect: whether the authored Primm beat survives as the scripted
introduction to a mechanic that is systemic thereafter (my instinct: yes — it teaches the
rule instead of springing it), what a captive player does in multiplayer when several are
taken at once, and whether game over is a hard restart or something softer given "the game is
the world".*

## What triggers the abduction — the owner named this as the hard part

Confirmed by him that it happens (*"at some point they will get prim, yes"*), and then:

> hard part it to decide when we are ready, what the trigger, we need to figure out it, I
> believe we will consider metric as skill points

**Skill points are the sensible metric** — distance is deleted, and skill points are the one
number that reliably tracks how equipped the player is.

**But a bare threshold breaks two ways.** A player who deliberately does not farm never
crosses it, so **the plot simply never fires** — we would have gated the story on a number
the player is free to decline to earn. And a threshold can trip in a **dramatically
meaningless moment**, mid-field, because a counter ticked over while they were picking up
coins.

**Settled: skill points are a *floor*, not a trigger.** The abduction requires both, and the
two jobs stay separate:

- **Readiness floor** — prevents the three-hero aftermath from being unfair.
- **Story beat** — determines *where and why* Primm is taken.

### Make it a *relevant capability* floor, not a point count

Codex's correction, and it matters: **generic skill points can be hoarded, or spent entirely
on farm-only `run_speed` / `streak_burst`** — neither of which says anything about tower
readiness. A player could cross a numeric threshold while being no better equipped than
before.

So count the **tower-relevant power actually available to the three survivors** — spent
relevant ranks, plus any unspent points the player could immediately allocate — or require a
small, visible **rescue-prep bundle**. This matters especially in multiplayer, where
progression is personal and one player's hoarding is not the party's readiness.

### At the beat but under the floor: stage it, don't stall it

**Do not silently wait.** My instinct was to quietly make the last stretch generous; codex is
right that **explicit beats invisible**. Instead, enter a visible **pre-capture staging
state**:

- The hunters have **found the route**.
- The party recognises it **cannot survive the next escalation**.
- The field offers **marked catch-up quests** with generous but **finite** coin rewards.

The player now understands *both* what they need and where to get it. **The capture then
fires on return to the marked narrative location — never on a random pickup.** Nobody wanders
around wondering why the plot stopped.

### Not the Nth hunter failure

I asked whether being cornered by hunters could itself be the trigger. **No** — it punishes
the player who is already struggling and makes expert players *delay a required story beat*.

Instead the hunter encounter is the **texture** of a capture that floor-plus-beat has already
decided. Once both conditions are met, the party faces an escalating, **playable** hunt:
success changes the rescue state — alarm, route, supplies, intel, allies — but **Primm's steel
containment is the fixed ending of that encounter.**

This is the same rule as before, applied again: *the player is allowed to win the objective
they were actually given, and is never tricked into believing they can avoid the unavoidable.*

## Still open

- What the score/HUD surfaces show now that distance is gone.
- The tower's puzzle vocabulary beyond key-and-door.
- Exact predator density numbers.
