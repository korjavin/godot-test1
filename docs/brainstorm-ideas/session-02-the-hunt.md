# Session 02 — The Hunt, the abduction, and the return

**Date:** 2026-08-27 · Owner's idea, polished with Codex over peer-chat.
**Status:** design fiction. Nothing built.

Read [README.md](README.md) for the constraints and [session 01](session-01-recall-anchors.md)
for the anchor mechanic this builds on.

---

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

Session 01's anchor needs **all four identities**. The moment Primm is taken, **every
four-socket lock in the world becomes unsolvable.**

Treat that as the **crisis, not a bug**. The fourth socket stands there lit and unusable,
and that is the emotional payload — the game does not need to tell you what you lost,
because your hands hit it every time you try. Acts after the abduction must be solvable
with three.

## Hunter robots — capture, not kill

A new enemy class that is **not** a predator, and the distinction is the point:

| | Predators | Hunter robots |
| --- | --- | --- |
| Want | to hurt you | to **retrieve** you |
| Losing to one means | damage, a life | **abduction** — carried to the tower |
| Fiction | the world is hostile | the *workflow* has escalated |

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
moved. Working position:

- The capture must **not** fire off a distance counter at the end of a cutscene trigger.
- The hunter robots must be a **real, escalating threat the player genuinely fights off
  several times first**, so the player has a working model of how they are beaten.
- The capture should land at a moment the player can look back on and believe **they nearly
  prevented it**.

In short: **scripted in outcome, not in texture.**

### B. Multiplayer — whose hero is taken, and what do they do?

If it is always Primm, one specific human is punished for nothing they did, and then has
**nothing to do**. Dead time in a co-op game is fatal.

**Proposal — asymmetric play.** The captured player keeps playing, **as Primm inside the
tower**: weakened, no phasing, because of the steel. The other three approach from outside.
The rescue becomes a **two-sided level** rather than a fetch quest.

The vault supports the state: Primm phases out *himself* at the end of E14, with a field
weakened after 72+ hours in steel. He is not rescued like luggage; he meets them halfway.

*Open: whether that is too much new game to build, and what the cheap version is that still
avoids dead time. Put to codex; answer pending.*

## Open questions

1. **Difficulty on the return leg.** The difficulty gradient keys off distance from origin;
   on the way back that *decreases*, so the game would get easier as the stakes rise —
   exactly backwards. The return needs its own pressure curve (Recall Pressure and the
   hunter density are the obvious candidates).
2. **Solo abduction.** The owner thinks it happens in solo too. With one body holding all
   four heroes, losing Primm means losing a *key*, not a player — probably the cleaner
   version of the same beat, but it needs its own texture.
3. **How many predators, and which.** "Reduce the number" is a ruling; the count and the
   biome dispatch are a tuning job for later.
4. **Does the tower use anchors at all**, or is the interior a different verb set? Sneaking
   is not running.
