# UI Systems — Technical Reference

## Design Philosophy: Diegetic Everything
The UI should feel like it exists within the game world. Minimalist HUD. Terminal-style overlays. Information is accessed through in-world interfaces, not floating menus.

## NetFeed Ticker
- **Appearance:** Scrolling text bar at the top/bottom of the screen. CRT scanline shader applied.
- **Data Source:** `WorldDirector.netfeed_event_generated` signal → only `NEWS_TICKER` events appear.
- **Interaction:** Player can open a full NetFeed terminal to scroll through `netfeed_history`.

## Contextual Persuasion Terminal
Opened when the player interacts with an NPC. Hybrid approach:
1. **Contextual Buttons:** Fast LLM call generates 3-4 clickable action options based on the NPC's state, the world state, and the player's traits.
2. **Open Text Field:** `LineEdit` for custom player input. The LLM parses intent and runs invisible persuasion checks.
3. **Result Display:** Success/failure response displayed in terminal style. NPC mood/relationship updates shown.

## HUD Elements
- **Health:** No bar. Indicated by screen effects (chromatic aberration, vignette) and player posture.
- **Heat Level:** Subtle indicator (screen edge glow) that intensifies with Heat tier.
- **Credits:** Small counter in corner. Flashes when credits change.
- **Population Mood:** Optional overlay showing the Sector Zeitgeist as a color gradient.

## Terminal Interfaces
Hacking, reading lore, and accessing the NetFeed all use fullscreen terminal overlays:
- **Visual Style:** Retro-futuristic DOS interface with green/amber text on dark background.
- **CRT Effects:** Scanlines, slight curvature distortion, phosphor glow.
- **Input:** Command-line style input with autocomplete for known commands.
