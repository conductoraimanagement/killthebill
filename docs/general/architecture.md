# KILL THE BILL: High-Level Architecture

## Overview
"KILL THE BILL" is a 3D isometric immersive sim. The core gameplay loop involves navigating a world rigidly divided by social class and manipulating a dynamic economy driven by a "Butterfly Effect" system. 

## High-Level Flow
1. **Initialization:** The game starts by assigning the player a Class Seed (White Collar or Blue Collar) via the `PlayerManager`. This determines starting inventory, faction relations, and the primary active crisis.
2. **The Living World:** The game world is managed by the `WorldDirector` singleton. This director oversees the economy, tracking prices of essential goods, the wealth of Oligarchs, and global tension levels.
3. **Player Interaction:** When the player acts (e.g., assassinating a target, hacking a terminal, stealing food), the event is reported to the `WorldDirector`. 
4. **The Butterfly Effect:** The `WorldDirector` calculates systemic ripples. For example, destroying a food shipment increases food prices. High food prices alter the `ImmediateNeed` and `CurrentMood` of NPCs.
5. **NPC Simulation:** NPCs do not have strictly scripted dialogue. Their behavior and dialogue are driven by an LLM backend that receives context injected from their `NPCController`.
6. **Sectors and Travel:** The world is divided into distinct thematic sectors (e.g., The Neon Docks, Subterranean Farms, Corporate Spire). The player travels between these hubs. Each sector has its own local dynamics (e.g., higher baseline security, specific visual landscapes) which interact with the global `WorldDirector` economy.

## Directory Structure
- `docs/`: Comprehensive documentation.
  - `general/`: High-level overview and design docs.
  - `backend/`: Systemic logic, economy, LLM integration details.
  - `frontend/`: Camera controllers, UI systems, shaders.
- `src/`: Reusable, modular Godot scripts and components.
  - `core/`: Singletons like `WorldDirector` and `PlayerManager`.
  - `entities/`: Base classes for Player and NPCs.
  - `systems/`: Specific gameplay systems (e.g., Hacking, Stealth).
- `scenes/`: Godot `.tscn` files.
- `assets/`: 3D models, textures, and sounds.
