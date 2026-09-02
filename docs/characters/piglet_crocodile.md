# Piglet Crocodile

## Overview
Piglet Crocodiles are hostile NPCs that roam the game world. They are fatal to the player upon collision.

## Physical Description

**Body Shape**: Small crocodile-like creature, compact and low to the ground (about 40-50 cm long, 20 cm tall). Body is elongated with a cylindrical torso and a long tail that tapers to a point.

**Head**: Large relative to body, with an elongated snout. Mouth visible with sharp teeth. Eyes are small, positioned on top of the head. The head has a reptilian, prehistoric look.

**Legs**: Four short, stubby legs positioned on the sides of the body. Each leg has small claws. The stance is wide and low, typical of reptiles.

**Tail**: Long and powerful, about 50-60% of total body length. Slightly curved, tapering from thick at the base to thin at the tip.

**Skin/Texture**: Scaly, rough appearance with bumpy texture. Dark green base color with lighter yellowish-green belly. Small ridges or spikes along the spine from head to tail.

**Colors**:
- **Body**: Dark green (#2d5016)
- **Belly**: Light yellowish-green (#8fb569)
- **Eyes**: Yellow with black slit pupils
- **Teeth**: White/ivory

## Behavior

Kept in step with `scripts/piglet_crocodile_ai.gd` (the `SPECIES` table) and
CLAUDE.md — those are the source of truth for numbers.

**Movement**: wanders with directional changes on a per-species rhythm, then
**chases** once the player is inside its detection radius. Chase speed (5.5 m/s)
is above walking speed, so walking gets you caught; every species' sustained
speed is capped below the slowest hero's run, so running always escapes.

**Collision**: contact is a **tax, not a death** — the player freezes for a
moment and loses a fraction of the run's coins (`coin_setback`), then gets up
where they fell. Only GD-SURVEY hunters and HQ guards take a hero.

**Bosses**: a boss crocodile holds a road station standing in a river, grows
with distance, is immune to the Stink Wave and to giant Teibi's crush, and
never leaves its territory.

## Spawning

Deterministic per chunk from the run seed; none inside the spawn-safe bubble
(`SPAWN_SAFE_RADIUS`, 25 m). Which species a chunk gets is decided by its
biome; the crocodile is the river and plains default. Distant crocodiles are
put to sleep by the LOD manager, never removed.

## Technical Specifications

**Node Type**: CharacterBody3D
**Collision Shape**: CapsuleShape3D (rotated horizontally for elongated body); the player passes through, damage is decided by the crocodile's own collision handling
**Movement**: Uses move_and_slide() for physics-based movement
**Scale**: Approximately 0.5x - 0.7x of player size

## Visual Vibe
Cute but dangerous. The "piglet" descriptor suggests they're small and perhaps slightly rotund, not lean and aggressive. Think "tiny danger noodle with legs" rather than "fearsome predator."

## Generator Tips
- Emphasize the compact, low-to-ground stance
- Make the body slightly chubby/rounded (piglet-like)
- Keep proportions cute but clearly reptilian
- Tail should be prominent and curved
- Dark green coloring makes them visible against terrain
