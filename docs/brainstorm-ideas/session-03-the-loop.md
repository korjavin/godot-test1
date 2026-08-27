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

## No lives, no game over — the game is endless

**Owner ruling, 2026-08-27:**

> Механика с жизнями и с окончанием игры больше не нужна… Когда тебя поймали крокодилы —
> тебя отбрасывает назад, забирая часть монет, часть опыта, но ты остаёшься. В меню можно
> будет продолжить игру и можно начать новую.

So death is replaced by **setback**: a predator catches you, knocks you back, takes part of
what you have — and **you continue.** The menu offers **Continue** and **New game**.

### Where the game is saved today (he asked)

Not cookies. Three layers, all owned by `best_run_store.gd`:

| Layer | What |
| --- | --- |
| Local — desktop | `ConfigFile` at `user://best_run.cfg` |
| Local — web | `window.localStorage` (a pre-existing `user://` record is still *read* on web, so nobody's old record is orphaned) |
| Server | `GET`/`POST <lobby>/best?id=<player id>` on the same Go lobby the multiplayer uses |

The player id is **per browser profile and per install**, so a second device starts a fresh
record — nothing transfers one.

### The invariant this ruling collides with

**"Losing part of your experience" breaks something load-bearing.**
`progression.gd:18-21`, verbatim:

> Levels are LIFETIME-CUMULATIVE. **Coins are never deducted**, so … monotone `max` merge and
> stop worrying about ordering, retries and stale [replies].

Monotonicity is not a nicety — **it is why the three-layer save works at all.** All three are
reconciled by a plain `max`, which is exactly what makes a late server reply harmless and
every retry free. The moment a number can go *down*, `max` stops being a valid merge, and we
would need real conflict resolution across three layers with **no authority anywhere**.

### Resolution — the owner asked the better question

I first proposed a carried-vs-banked split (you lose what you are holding, never what you
handed in). **The owner rejected it** — he did not find the concept legible, and he was
solving a different problem than I was. He wants the simple thing: **a flat 7% of coins taken
on death**, no pools, no banking.

And then he asked the question neither codex nor I had asked:

> Почему мы не можем монотонность строить не на монетах, а на чём-то ещё?
>
> *(Why can't we build monotonicity on something other than the coins?)*

**We can — but my first version of it was wrong, and codex broke it with a counterexample.**

I proposed three counters — `earned`, `spent`, `lost` — each max-merged, with
`wallet = earned − spent − lost`. **That can go negative:**

```
both devices see earned = 100
device A spends 100 coins        →  spent = 100, lost = 0
device B dies and loses 7 coins  →  spent = 0,   lost = 7
componentwise max merge          →  wallet = 100 − 100 − 7 = −7
```

**Two independently max-merged consumers of the same pool are unsafe.**

### The correct shape: one earn counter, one debit counter

```
coin_wallet = max(0, lifetime_earned_coins − lifetime_debited_coins)
```

**Both purchases and death losses increment the same `lifetime_debited_coins`.** Every local
operation preserves `debited ≤ earned`, and therefore componentwise `max` preserves it too —
because whichever device produced `max(debited)` had that value under *its own* earned, which
is itself ≤ `max(earned)`. The wallet cannot merge negative.

### And I had the units wrong

Verified in the code: `lifetime_coins` counts **coins**; `spent_points` counts **skill
points**; and unspent points are `maxi(0, level * POINTS_PER_LEVEL - spent_points)`. These are
**two different currencies**, and my single equation silently mixed them. The shipped model is
two equations:

```
coin_wallet          = lifetime_earned_coins − lifetime_debited_coins
unspent_skill_points = level(lifetime_earned_coins) * POINTS_PER_LEVEL − spent_skill_points
```

Levels derive from **gross lifetime earnings**, so **levels never fall** — which is what the
owner confirmed he wants. Both of his statements hold at once: *levels are genuinely
lifetime-cumulative, and coins drop 7% on death.*

### Two corrections to things I asserted

**It is not a PN-counter, and the error is not always in the player's favour.** I claimed
scalar max-merge was a PN-counter that erred kindly. Neither is true. Two scalar maxima are
not a multi-writer PN-counter, and **concurrent *earnings* are under-counted the same way
spends are** — `+20` on each of two devices merges as `+20`, not `+40`. Exact multi-device
accumulation needs per-device components summed, or a single authoritative writer. Scalar max
may still be an acceptable cheap policy, but it can lose the player money, not only save them
money.

**Store the resolved integer, never a percentage log.** At death, compute 7% of the wallet
visible *at that moment*, pick one explicit rounding rule, increment the debit counter **once**,
and save immediately. A retried `POST` then carries the same absolute total and stays
idempotent. A percentage log would need ordering and historical balances to replay correctly.

### Continue / New game — I was wrong, this is not free

I told the owner this mapped cleanly onto shipped code and that nothing needed inventing.
**That was wrong**, and codex caught it. Verified:

- `run_seed` appears **zero times** in `best_run_store.gd` — **the seed is not persisted at
  all.**
- `endless_terrain` does `seed_rng.randomize()` then `set_run_seed(seed_rng.randi())` at
  startup — **a fresh random world every launch.**

So **Continue cannot mean "keep the world" today, because there is no saved world to keep.**
Nor can New Game mean merely "new seed" once the tower has persistent doors, quests,
checkpoints and capture state. The real contract:

- **Continue** — load the saved seed, tower/campaign state, last checkpoint, roster and story
  state, and the banked profile.
- **New Game** — after confirmation, create a fresh campaign: new seed, closed tower routes,
  reset quests and capture state, **and every hero back to zero skills and zero coins.**

### There is no meta-layer — the game *is* the world

**Owner ruling, and it is a real simplification:**

> Когда начинаем новую игру, все герои начинаются с нуля, с нулевыми скиллами, с нулевыми
> монетами… У нас вообще нет игры и мира, у нас всегда одно и то же. Игра — это одно и то же,
> что и мир.

So **skills and coins are world state, not account state.** There is no meta-progression
surviving a New Game, and no separation between "the game" and "the world" — one save *is*
one world *is* one game.

**This inverts a shipped design decision**, which is worth stating plainly rather than
discovering later: `progression.gd` is today deliberately **run-independent** — nothing in
restart, new-run or reset touches lifetime coins. Under this ruling, New Game must reset
exactly what that file was built never to reset.

#### And it breaks the save key, not just the save contents

This is the sharp edge. `best_run_store.gd` keys its record on **one player id per install**
and merges every field by monotone `max`. That was correct while progress only ever grew.

**It is now actively wrong:** start a New Game, drop to zero, and the next merge sees the
server's remembered maximum and **restores the campaign you just abandoned.** Max-merge does
not just fail to help here — it resurrects deleted progress.

**Fix: the record must be keyed per *world*, not per player** — player id **plus a save id**.
Then `max`-merge stays valid *within* a save, and a New Game starts a new record instead of
colliding with the old one. Nothing about the merge logic changes; only what it is keyed on.

**Necessary, but codex is right that it is not sufficient.** Three additions:

1. **All three layers must be namespaced by an immutable `save_id`** — `ConfigFile`,
   `localStorage` and the server record alike. New Game mints a fresh random `save_id` and
   **selects it before fetching any counters**. Never zero an object that is still attached to
   the old key.
2. **There are two identifiers, not one.** `save_id` is the identity of a world and is
   immutable for its lifetime. `current_save_id` is a *pointer* saying which world Continue
   opens — and that pointer is where two-device disagreement would live. Since `player_id` is
   minted **per install / per browser profile**, devices do not share records today, so
   `current_save_id` can simply be **local** and there is no cross-device "current" to
   reconcile. If shared cross-device Continue ever becomes a requirement, a save id alone
   cannot choose the current world: either expose **save slots and let the user pick**, or
   synchronise a pointer with an authoritative server revision / CAS. A `(generation,
   device_id)` tuple converges without a server clock, but simultaneous New Games then pick a
   winner arbitrarily — that is convergence, not intent.
3. **Keying per world does not solve same-world state merges.** Position, active quest, Primm's
   capture state and unfinished room configuration are **not monotone maxima**. The per-world
   key prevents *cross-world resurrection*; a **world snapshot / revision policy** still has to
   decide which same-world state wins.

And a naming note worth keeping: if a command only re-rolls the field while keeping the
campaign, it is **New World / Reroll Field**, not New Game.

### The 7% only bites if coins buy something — OWNER DECISION NEEDED

Codex's sharpest point, and it is a design question rather than an engineering one:

> A 7% haircut scales cleanly, but it only creates tension if the remaining coin wallet has a
> use the player values. Because levels derive from **gross** lifetime earnings, the haircut
> does not delay levels or remove skills. **If coins buy nothing else, 7% is only a shrinking
> display number and will become emotionally empty.**

That is the direct consequence of "levels never fall" — which the owner wants — meeting "the
penalty is 7% of coins". The two are consistent, but together they can cancel each other's
teeth.

**So the loop needs a real coin sink**, even a modest one — something the wallet buys that the
player would rather not lose. Otherwise we should accept honestly that predators provide
*interruption* rather than *stakes*, and let the hunters carry the tension alone.

### The setback moment

Replace the game-over screen with a short, **non-modal setback summary** after the knockback —
`Lost 18 coins — levels and skills safe` — and let play resume automatically. The lives HUD
gives way to the wallet, with permanent level and skill progress kept **visually separate**,
so the player can see at a glance what a predator cannot take. Continue / New Game belong on
the title and pause menus; a capture should never open a full-screen decision panel again.

## Open
- Whether the tree needs a **tower branch** at all, or whether re-tuning the existing effects
  covers it.
- What the HUD shows now that distance is gone — coins and skill points are the obvious
  answer, and both already have widgets.
