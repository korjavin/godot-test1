# Session 03 — The loop: field farms, tower spends

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

## The risk that decides whether this loop is good or miserable

**A puzzle solved by having enough skill points is not a puzzle. It is a stat check.** A tower
full of stat checks makes the farm **mandatory**, and mandatory farming is the difference
between *Hades* and a bad mobile game.

**Proposed rule: skills change reach and margin, never solutions.**

- A gate is opened by **the right identity and nothing else**. No amount of farming
  substitutes for being the right hero.
- What farming buys is **execution comfort**: the longer blink clears the ledge without a
  frame-perfect jump; the longer form gives you time to think; the lower cooldown lets you
  retry sooner.

**Consequence, and it is the point:** the tower is **always beatable at zero skill** by a
player who is good, and farming buys margin for a player who would rather not be. The loop
stays *available* rather than *required*.

### Codex's tightening — adopt this version, not mine

> **Every tower encounter needs a demonstrable zero-rank procedure before any skill can
> improve it.** A longer blink may reach a shortcut or rescue a bad jump, but it cannot be
> the only way to touch the mechanism.

This is strictly better than what I wrote. Mine said *the tower should be beatable at zero
skill* — which is a **hope**. Codex's says *every single encounter must have a known
zero-rank solution* — which is a **rule you can actually check while building a room**. If
you cannot demonstrate the zero-rank procedure, the room is not finished.

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

## Open
- Whether the tree needs a **tower branch** at all, or whether re-tuning the existing effects
  covers it.
- What the HUD shows now that distance is gone — coins and skill points are the obvious
  answer, and both already have widgets.
