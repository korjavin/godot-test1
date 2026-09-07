# MP per-peer audit (bead godot-test1-vej, "nor for other things")

The owner's report was weather, but the sentence was "shouldnt be nor for
rains nor for other things". This note lists what else in the world is
per-peer runtime state that affects GAMEPLAY (not cosmetics), surveyed from
code comments and group/MP seams on 2026-09-07. NOT fixed here — follow-up
beads only. Cosmetics (clear clouds, birds, crowd transforms) are out of
scope by definition and stay per-peer.

Shared already (no action): run_seed world, coins (deterministic + claim
arbitration), crocodiles and bosses (master-simulated, never network-spawned),
herds (`herd` verb, bead 6xc), storms (`wx` verb, this bead), captives (`cap`
+ `room` repair), landmark claims (`lmk`), HQ lure plates (`pad`), hunters
(`hunt_director` drives non-masters through `set_remote_state()` off
`peer_positions()`), tower gates/guards initial layout (byte-identical against
master, stated in `tower_gates.gd` / `tower_guards.gd` headers), pause (P as a
presence bit), shared bank/distance (absolute broadcasts).

## 1. Budapest traffic cars — diverge, minor gameplay (candidate follow-up)

`traffic_manager.gd` spawns its bubble around the LOCAL player and recycles
out of sight; cars yield to the local player and a hero "bumps a bumper and
slides along it". Two peers in the same street meet different cars in
different places. Effect is contact-only (no damage found in the header), but
it is a physics response, not a picture. Either seed the bubble or accept it
in writing.

## 2. Tower guard fights — diverge, real gameplay (candidate follow-up)

`tower_guards.gd` carries no `mp` / master / remote / sync seam at all (one
tangential LOD line). Deterministic initial layout is shared, but a fight —
which peer aggroed which guard, guard HP, who landed the hit — resolves per
peer against group `"player"`, i.e. the LOCAL player. Two peers can fight (and
plausibly kill) "the same" guard independently. Needs a decision: master
authority like crocodiles, or per-peer instances by design.

## 3. Boss projectiles — per-peer BY DESIGN (confirm intent, no bead)

`boss_projectile.gd` states it outright: no relay verbs, no sync; lethality
resolves against group `"player"` (the local player only), "so a projectile
threatens exactly the machine that simulated it", and a remote-driven boss
runs its collisions on the quarry's machine. Each screen's threats are real on
that screen and absent on the others. If that sentence is still the intent,
this item is done — it is listed here only so the intent is on record next to
items 1–2.

## Explicitly not listed

Fauna/weather event timers (a non-master's never fires, so divergence is
impossible), clear clouds and birds (no gameplay read), crowd citizens
(transforms on a layer only the player masks — camera dressing),
coin/streak HUD, audio fades. Best-run persistence is monotone per peer and
merges by max/union, so late packets cannot lower a record.
