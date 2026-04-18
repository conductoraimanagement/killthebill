# Combat Mechanics — Technical Reference

## Overview
Combat is systemic and isometric. Twin-stick or point-and-click targeting. Weapons interact deeply with the economy, stealth, and Heat systems.

## Weapon Categories
| Category | Examples | Noise | Systemic Impact |
|---|---|---|---|
| Precision/Stealth | Sniper rifles, crossbows | Crossbows: silent. Snipers: loud. | Silent kills prevent Heat spike. Clean assassinations possible. |
| Tactical/Sabotage | Proximity mines, remote explosives, EMP traps | Variable (some silent, explosions loud) | Destroying infrastructure triggers massive Butterfly Effects (price spikes, Zeitgeist shifts). |
| Assault/Suppression | Automatics, shotguns | Very loud | Immediate Heat flag. Non-combatant NPCs flee/cower. `security_presence` spikes. |

## Noise System
Every weapon has a `noise_level` (0.0 silent → 1.0 deafening). When fired:
- If `noise_level > 0.5`: All NPCs in radius become witnesses. Heat escalates.
- If `noise_level < 0.2`: Only NPCs with direct line-of-sight may notice.
- Silenced weapons reduce `noise_level` by 0.5.

## Ammo Economy
Ammo is a scarce resource tied to the Tech/Security economy:
- High `tech_price` = expensive ammo on the black market
- High `security_presence` = gun prices skyrocket (Enforcers confiscating supply)
- This naturally pushes players toward traps, crossbows, or social manipulation when the economy is tight

## Combat Raycasting
- Physics raycast from isometric camera to world for point-and-click targeting
- Weapon manager handles charge time, cone of fire, and damage calculation
- Cover system uses existing CSG geometry for line-of-sight blocking
