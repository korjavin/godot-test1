# Session 03 — The loop: the field farms, the tower demands

> **Vocabulary, corrected by the owner:** the tower does not *spend* — **the tower demands**
> (*«башня не тратит, а башня требует»*). The emphasis matters: the tower is not where you
> cash in what you earned, it is **what sets the bar** you have to meet.

**Date:** 2026-08-27 · Owner's structure, stress-tested with Codex.
**Status:** design fiction. Nothing built.

---

## The loop, as the owner gave it

> Мы всегда можем убежать из башни, чтобы побегать по нашей площади, где за нами гонятся
> охотники бесконечно. Там мы можем насобирать коинов через лендмарки и через ящики сокровищ
> и прокачать скиллы. И эти скиллы должны нам помогать обязательно потом внутри башни…
> Игра может быть цикличной: вернулся в башню, почувствовал, что тяжело, что не хватает
> скиллов — пошёл пофармил на площадке, потом вернулся в башню и закончил миссию.

So the game has **two layers**, and you move between them freely:

| | The field | The tower |
| --- | --- | --- |
| Role | **farm** | **campaign** |
| Verb | run, flee, collect | sneak, search, solve |
| Threat | endless hunters, predators | few guards |
| Yields | coins → skill points | story, keys, the mission |
| Ends? | never | yes |

**You can always leave.** The tower is not a commitment, it is a place you enter, spend what
you have, and withdraw from when you run short.

## Why this is the right shape

### 1. It repurposes instead of discarding

Everything already built — endless terrain, hunters, predators, landmarks, treasure, coins —
**keeps its job**. The story does not replace the game we have; it gives it a reason. That is
the single most valuable property of this structure, and it is why it beats every "and then
we build a different game" idea we have considered.

### 2. It answers the question deleting distance left open

When distance died, we had no score. Now we do: **coins → skill points**, and that is not new
work. `progression.gd` already turns lifetime coins into levels into skill points, and it is
deliberately **run-independent** — nothing in restart / new-run / reset touches it.
`best_run_store.gd` merges every field with a monotone `max`.

**A farm loop is precisely the shape the persistence layer already has.** No new system.

### 3. "You can always leave" and "the route stays changed" agree by accident

The owner's rule that you may always withdraw means the tower must be **re-enterable and must
preserve progress between visits**. Codex's rule from session 02 — a hero's transformation
is persistent, a door you opened stays open — says the same thing from the other direction.
Two decisions made for unrelated reasons landed on the same requirement.

## Do the existing skills actually help in a tower?

Checked rather than assumed. The tree's current effects:

`cooldown` · `run_speed` · `streak_burst` · `windman_boost` · `windman_lift` ·
`windman_gravity` · `primm_blink` · `primm_refund` · `teibi_form` · `teibi_small_speed` ·
`teibi_quake` · `phoboman_flee` · `phoboman_radius`

**Most are ability-shaped rather than running-shaped, so the tower relevance is already
there:**

| Effect | Why it matters inside |
| --- | --- |
| `cooldown` | act more often — the broadest one |
| `primm_blink` | reach a mechanism across a gap |
| `teibi_form`, `teibi_small_speed` | more time in giant or micro form |
| `windman_lift`, `windman_boost` | reach height — newly relevant now that verticality is legal |
| `phoboman_radius`, `phoboman_flee` | handle the few guards |
| `primm_refund` | retry a failed reach without waiting |

Only **`run_speed`** and **`streak_burst`** look farm-only. So the connection the owner wants
**mostly exists already** — this is a tuning and level-design job, not a new subsystem.

## Rank gates ARE the content — owner ruling

Codex and I both landed on a rule the owner has **overruled**, and it is worth recording
because we were both wrong in the same direction.

- I proposed: *skills change reach and margin, never solutions* — the tower is always
  beatable at zero skill.
- Codex tightened it to: *every tower encounter needs a demonstrable zero-rank procedure
  before any skill can improve it.*

**The owner rejected both:**

> Вполне может быть, что некоторые препятствия не проходятся на нулевом ранге, и тогда надо
> идти качаться. Наоборот, это наш стимул идти качаться.
>
> *(Some obstacles may simply not be passable at zero rank, and then you have to go level up.
> On the contrary — that is our incentive to go level up.)*

He is right, and the mistake we made was treating a progression gate as a **failure of
design** when it is the **motor of the loop**. If the tower is always beatable as you are,
there is no reason to ever leave it, and the field has no job. **Hitting a wall you cannot
pass is the signal to go farm** — that is the entire point of a two-layer game. This is the
Metroidvania model: the locked door is *content*, not something to apologise for.

### The safeguard: legibility, not difficulty

The danger here is **not** that a gate is hard. It is that a gate is **ambiguous**. If an
obstacle is merely difficult, the player cannot tell whether they are failing because they
lack the **rank**, lack the **execution**, or have the **wrong idea entirely** — and that is
the miserable version: banging your head against something that was never going to work, or
farming for an hour to beat something that only wanted a better jump.

My rule was *"a gate may be rank-gated, but it must be legibly rank-gated."* **Codex made it
stronger, and the addition is the important half:**

> A hard gate must be **diagnosable *and* forecastable**. Before repeated failure, the player
> can tell **which capability is insufficient**, and **that field progress can improve it.**

Legibility identifies the wall. **Forecastability tells the player what a trip to the field
will actually change** — otherwise they understand the gate is rank-locked and still go farm
*blindly*, which is the same misery wearing a different hat.

**Validity test for any gate we build:** after one inspection or one attempt, the player can
say *"I need more of **this** ability, and running the field can provide it."*

### How a gate says that without a label

No floating `REQUIRES BLINK RANK 3`. Instead, give every capability a **stable diegetic
language**:

- A demand gate is a **purpose-built corporate interface**, never ordinary geometry — a
  phase receptacle, a mass cradle, a lift vane, a classifier screen.
- Its **visible calibration bands and sockets** show the capability *category* and the *scale*
  required. The hero's current effect is drawn in **the same visual language**, so a short
  Blink and a far phase receptacle **visibly do not match**.
- On the **first deliberate attempt**, a distinct *insufficient capacity* response: the
  mechanism reacts **partway**, the hero says what is lacking, and the notebook records a
  short phrasing — *"Primm's phase must reach farther."* **An explanation once, not a HUD
  label everywhere.**
- The skill screen then makes the direction of improvement obvious. Exact rank numbers are
  optional; what the player needs is certainty that this is an **upgrade problem, not an
  execution mystery.**

### Two obstacle classes, unmistakable on sight

| | **Challenge spaces** | **Demand gates** |
| --- | --- | --- |
| What | ordinary terrain, guards, moving hazards, puzzles | standardized corporate mechanisms |
| Nature | **skill-expressive** — the base kit can solve them; ranks give safety, speed, recovery, an optional shortcut | **hard progression locks** |
| They invite | **an attempt** | **inspection** |

The reason this distinction earns its keep: **both may use a gap, or a guard.** A broad
physical gap is a *challenge*; a **phase receptacle across it** is a declared *Primm demand*.
Consistent silhouette, material, lighting and inspection feedback are what stop the player
from mistaking one for the other — and mistaking them is exactly how a player ends up farming
for a jump or grinding their face on a lock.

### Checkpoints

> Use a visible tower **checkpoint after each permanent route change**, so exit is safe
> without making every cleared room permanently empty.

This is what makes "you can always leave" safe to act on: the withdrawal point is visible and
earned by the route change you just made, rather than being a save-anywhere that erases all
tension.

## What persists between tower visits — settled

**Structure persists; population resets.** The governing sentence:

> **Never erase an earned answer, but allow the next room's tactical challenge to return.**

| Persists | Resets |
| --- | --- |
| opened doors, bridges, permanent route transformations | ordinary guards and patrol positions |
| **demand-gate unlocks** | temporary and timed mechanisms |
| completed quest stages and story pages | ordinary combat outcomes |
| unique keys | temporary and timed switches |
| defeated **named** set-pieces | loose movable objects |
| rescued-party state | alarms |
| lifetime coins, levels, skill ranks | unfinished in-room puzzle configuration |

Economy follows the same line: **tower chests and unique rewards are one-time**; **field coins
are renewable at a controlled rate.** So the field can be farmed and the tower cannot — which
is what keeps the two layers doing different jobs instead of competing.

This resolves both halves of the risk. Nothing you *solved* is taken back, so leaving is never
punished; but nothing you *cleared* stays empty, so the tower never degrades into a checklist
you grind down room by room.

**A met demand gate never re-locks.** Once you have gone out, earned the rank and opened it,
its opened state persists exactly like a door or a bridge. A player must not leave, farm,
open a gate, and then find it shut again on the next visit — *that turns earned progression
into upkeep*, which is the one way to make this loop feel like a job.

> The tower **demands** a capability at a decisive threshold. It does not repeatedly charge
> the player for having earned it.

## Open
- Whether the tree needs a **tower branch** at all, or whether re-tuning the existing effects
  covers it.
- What the HUD shows now that distance is gone — coins and skill points are the obvious
  answer, and both already have widgets.
