# Regions

Implemented by: [src/core/RegionGenerator.gd](../../src/core/RegionGenerator.gd) · Singleton autoload.

The world is **procedurally assembled at playthrough start**. No two runs have the same map. 6–10 regions are generated, each with a random name, a type, a set of infrastructure targets, and a biome seed for the [landscape generator](landscapes.md).

---

## Region types

| Type | Count | Security mod | Tension mod | Population | Role |
|---|---|---|---|---|---|
| `URBAN_SLUM` | 2–3 | −30 … −10 | +10 … +30 | 0.7–1.0 | Recruitment, black market, agitation |
| `URBAN_ELITE` | 1–2 | +30 … +60 | −30 … −10 | 0.1–0.3 | Oligarch residences, political levers |
| `INDUSTRIAL` | 1–2 | −5 … +15 | 0 … +15 | 0.2–0.4 | Sabotage targets, factory floors |
| `AGRICULTURAL` | 1–2 | −10 … +5 | −5 … +10 | 0.1–0.25 | Food supply chain, starvation lever |
| `ISLAND_RETREAT` | 0–1 | +50 … +80 | −40 … −20 | 0.01–0.05 | Oligarch bunker, endgame infiltration |
| `TRANSIT` | 1–2 | +10 … +30 | +5 … +15 | 0.3–0.6 | Checkpoints, smuggling, border control |

Modifiers are **added to the global economy values** when the player is in-region. A slum in a crisis can push local tension to 90 while the Enclave next door stays at 0.

---

## Name generation

Names are LLM-generated per run, seeded by type. Fallback local pools (10 prefixes × 10 suffixes per type) exist in `RegionGenerator.gd` for offline play:

- **Slum**: "Rust · Ash · Gray" + "Hollow · Row · Depths" → *Ash Row*, *Gray Depths*
- **Elite**: "Crystal · Silver · Solar" + "Heights · Spire · Plaza" → *Silver Spire*
- **Industrial**: "Foundry · Slag · Iron" + "Basin · Works · Yard"
- **Agricultural**: "Substrate · Root · Loam" + "Fields · Beds · Vaults"
- **Island**: "Haven · Obsidian · Coral" + "Cay · Atoll · Isle" → *Obsidian Cay*
- **Transit**: "Checkpoint · Border · Passage" + "Nexus · Point · Lock"

---

## Region shell

Every region carries:

| Property | Type | Purpose |
|---|---|---|
| `id` | String | Unique handle |
| `name` | String | Display name |
| `type` | String | One of the six types above |
| `security_modifier` | int | Added to global `security_presence` locally |
| `tension_modifier` | int | Added to global `public_tension` locally |
| `population_density` | float | 0–1, drives NPC encounter frequency |
| `infrastructure_targets` | Array | 2–3 named sabotage targets (see [Butterfly Effect](butterfly-effect.md)) |
| `visual_biome` | String | Feeds the [landscape generator](landscapes.md) |
| `connected_oligarch` | String | Which Oligarch controls this region |
| `unlocked` | bool | Whether the player has access |

---

## Travel

- The player starts in a random `URBAN_SLUM` (picked by the generator).
- Other regions unlock through quests, NPC introductions, and infiltration of `TRANSIT` checkpoints.
- Travel fires `event_triggered("travel", region_name)` → handled by [WorldDirector](../05-systems/architecture.md).

---

## Oligarch territory

After regions are generated, `WorldDirector._assign_oligarch_territories()` matches each Oligarch to a region based on their sector:

- **Food** → `AGRICULTURAL`
- **Security** → `TRANSIT`
- **Tech / Pharma / Energy** → `INDUSTRIAL`
- **Media** → `URBAN_ELITE`

One billionaire per region where possible; unclaimed regions are neutral territory.

---

## Region dynamics

Each world cycle, `WorldDirector._update_region_dynamics()` re-derives modifiers from the global economy. Examples:

- Slum tension_modifier jumps to 30–50 when `food_price > 300`
- Elite security_modifier jumps to 50–70 when `senate_alignment < 30`

This is **intentionally sparse** today. Extension ideas in [Roadmap](../06-roadmap/phases.md).

---

## See also
- [Landscapes](landscapes.md) — biomes and landmarks per region
- [Economy](economy.md) — the global variables regions modify
- [Architecture](../05-systems/architecture.md) — how RegionGenerator slots into the singleton graph
