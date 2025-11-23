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

**Movement**:
- Wanders randomly around the terrain
- Slow to medium speed (2-3 m/s)
- Pauses occasionally as if sniffing or looking around
- Does NOT actively chase the player (passive threat)

**AI Pattern**:
- Random walk with directional changes every 3-5 seconds
- Rotates body to face movement direction
- Stays on terrain, doesn't jump or climb

**Collision**:
- **FATAL**: When the player collides with a Piglet Crocodile, the game should reset the player's position or show a game over state
- Collision box is slightly larger than visual model for easier detection

## Spawning

**Spawn Locations**:
- Random positions around the terrain
- Minimum 10 meters away from player spawn point
- 3-5 crocodiles active at a time

**Spawn Pattern**:
- Spawn when terrain chunks are created
- Despawn when chunks are removed (optimization)

## Technical Specifications

**Node Type**: CharacterBody3D
**Collision Shape**: CapsuleShape3D (rotated horizontally for elongated body)
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
