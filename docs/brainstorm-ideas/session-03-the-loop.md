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

*Put to codex; answer pending.*

## Open

- **What persists between tower visits, and what resets.** If everything persists, the tower
  becomes a checklist you grind down. If nothing persists, the owner's go-out-and-farm loop
  punishes you for leaving. Put to codex.
- Whether the tree needs a **tower branch** at all, or whether re-tuning the existing effects
  covers it.
- What the HUD shows now that distance is gone — coins and skill points are the obvious
  answer, and both already have widgets.
