# KILL THE BILL — Design Documentation

A 3D isometric immersive sim about toppling an oligarchy.
Every playthrough is procedurally assembled: the world, the billionaires, the faces on the street, and — sometimes — the stranger at the bar who turns out to be more than a stranger.

This is the single source of truth for the game's design. Read in order for a full tour, or jump to what you need.

> **Browsable HTML version:** run `python3 -m http.server` inside `docs/` and open <http://localhost:8000>. The HTML reads these same `.md` files — they remain the source of truth.

---

## Read in order

### 1. [Vision](01-vision/)
What the game **is** before you ask how it's built.
- [Pitch](01-vision/pitch.md) — the one-paragraph version
- [Pillars](01-vision/pillars.md) — the five principles every system answers to
- [Tone](01-vision/tone.md) — setting, mood, art direction

### 2. [World](02-world/)
The simulation the player lives inside.
- [Regions](02-world/regions.md) — procedural map, 6–10 regions per run
- [Landscapes](02-world/landscapes.md) — biomes, landmarks, points of interest *(new)*
- [Economy](02-world/economy.md) — the four sectors and the variables that bind them
- [The Senate](02-world/senate.md) — LLM-generated bills, the third power lever *(new)*
- [NetFeed](02-world/netfeed.md) — the LLM-driven event stream that makes the world feel alive
- [Butterfly Effect](02-world/butterfly-effect.md) — how player actions ripple

### 3. [Characters](03-characters/)
The people — billionaires, politicians, citizens, and the occasional myth.
- [Oligarchs](03-characters/oligarchs.md) — 4–6 procedural billionaires with personalities and ambitions
- [Oligarch Web](03-characters/oligarch-web.md) — rivalries, alliances, organic scandals, adaptation *(new)*
- [Politicians](03-characters/politicians.md) — 11 procedural senators who vote, flip, and fall *(new)*
- [NPCs](03-characters/npcs.md) — 40 persistent citizens with Nature/Nurture evolution
- [Relationships](03-characters/relationships.md) — trust, bonds, agent recruitment
- [Cultural Cameos](03-characters/cultural-cameos.md) — pop-culture encounters that sometimes hijack a run *(new)*

### 4. [Player](04-player/)
The loop the human drives.
- [Core Loop](04-player/loop.md) — Observe → Plan → Act → Adapt
- [Progression, Credits & Heat](04-player/progression.md) — class seeds, income mechanisms, spending, heat system *(new, partial)*
- [Combat](04-player/combat.md) — weapons, noise, stealth
- [Heat & Evasion](04-player/heat.md) — police, SWAT, military, escape
- [Victory](04-player/victory.md) — three paths to collapse, all live at once

### 5. [Systems](05-systems/)
The tech underneath.
- [Save and Share](05-systems/save-and-share.md) — world configs: save the generated world, share it, reproduce it *(new, implemented)*
- [Architecture](05-systems/architecture.md) — singletons, data flow, dependency graph
- [LLM Stack](05-systems/llm.md) — six-provider fallback, request types
- [UI](05-systems/ui.md) — diegetic philosophy, terminals, NetFeed ticker
- [Visuals](05-systems/visuals.md) — camera, shaders, biome palettes

### 6. [Roadmap](06-roadmap/)
Where we are, where we're going.
- [Status](06-roadmap/status.md) — current phase, what's live, what's stubbed
- [Phases](06-roadmap/phases.md) — long-form roadmap

---

## Glossary

- **The Enclave** — corporate plazas where the top 0.1% live
- **The Sinks** — brutalist slums crushed by prices, patrols, and smog
- **Oligarch** — one of 4–6 procedural billionaires; the player's targets
- **NetFeed** — the world's media/comms layer; also the game's narrative engine
- **Butterfly Effect** — the ripple system that mutates economy and NPCs after every player action
- **Class Seed** — the trait bundle assigned to a new avatar after death
- **Cameo** — a pop-culture archetype that can appear in a run, sometimes briefly, sometimes world-alteringly
- **Bill** — an LLM-generated Senate proposal; passes or fails each world cycle and mutates the economy
- **World Config** — the captured procedural inputs of a playthrough (regions + oligarchs + politicians + NPCs). Save it, share it, replay the same world.
