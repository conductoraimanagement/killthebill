# Heat & Evasion System — Technical Reference

## Overview
The Heat system governs police and military responses to player crimes. It creates severe consequences for loud, violent actions.

## Crime Detection
Doing something "bad" (firing automatics, placing bombs, assaulting an Oligarch) generates a `CrimeEvent`. If a camera or loyalist NPC witnesses it, the `WorldDirector` spikes the player's **Local Heat Level**.

## Escalation Tiers
| Tier | Force | Behavior |
|---|---|---|
| 1 | Local Police | Beat cops dispatched to last known location. Investigate, attempt arrest. |
| 2 | SWAT/Enforcers | Armored corporate hit squads via dropships. Lethal force. Sector exits locked. |
| 3 | Military/Compliance AI | Martial law. Military mechs or Hunter AI deployed. Regional travel frozen. |

## Evasion Mechanics
- Break line of sight and hide in safe zones (smuggler tunnels, safehouses)
- Change outfits/identifiers to break visual tracking
- Wait out cooldown timer (drains slower when `global_security_presence` is high)
- Hack a regional server to manually wipe wanted status

## Systemic Integration
- Loud weapons (automatics, explosives) spike Heat immediately
- Silent weapons (crossbows, knives) may not trigger detection if no witnesses
- High `security_presence` means faster escalation and slower cooldown
- Assassinating an Oligarch always triggers Tier 3
