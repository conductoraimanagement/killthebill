# Landscapes

> **Status:** Design spec + stub. See [src/core/LandscapeGenerator.gd](../../src/core/LandscapeGenerator.gd). 3D geometry generation is a later phase; this doc defines the data layer that will drive it.

A [region](regions.md) is the *logical* slice of the world — its type, its economy modifiers, its Oligarch. A **landscape** is the *physical* slice — the biome, the skyline, the street the player actually walks down.

Every region gets one landscape, generated at playthrough start, persistent for the run.

---

## Goals

1. **No two slums look alike.** A slum in one run is brutalist concrete under neon rain; the next run it's a vertical favela of stacked shipping containers with barrel fires.
2. **Silhouettes telegraph systems.** A `URBAN_ELITE` region with a `financial_spire` landmark reads as *hack here for Oligarch wealth*; the player learns the shorthand fast.
3. **Geography should feed gameplay.** Landmarks are not decoration — each one is a destination the player can break into, sabotage, or hide inside.

---

## Biome seed

Each region type has a pool of biome seeds. `RegionGenerator` already picks one today (see `visual_biome` in [regions.md](regions.md#region-shell)). `LandscapeGenerator` reads that seed and inflates it into a full landscape descriptor.

| Region type | Biome seeds (examples) |
|---|---|
| `URBAN_SLUM` | `brutalist_fog`, `neon_rain`, `concrete_decay`, `toxic_sprawl`, `container_favela`, `tunnel_warren` |
| `URBAN_ELITE` | `glass_spire`, `garden_terrace`, `white_brutalism`, `floating_plaza`, `atrium_park`, `marble_boulevard` |
| `INDUSTRIAL` | `smoke_stack`, `rust_canyon`, `molten_core`, `warehouse_grid`, `refinery_maze`, `drone_foundry` |
| `AGRICULTURAL` | `underground_green`, `terraced_cavern`, `dome_farm`, `strip_field`, `hydro_vault`, `open_steppe` |
| `ISLAND_RETREAT` | `tropical_fortress`, `volcanic_bunker`, `arctic_retreat`, `ocean_platform`, `atoll_compound`, `coral_villa` |
| `TRANSIT` | `highway_corridor`, `rail_junction`, `border_wall`, `underground_passage`, `port_chokepoint`, `airbridge` |

Add seeds freely. Each seed needs:
- a **palette** ([visuals.md](../05-systems/visuals.md))
- a **skyline silhouette** preset
- a **tile-set** (low-poly modular blocks) for geometry
- a **density rule** (how tightly to pack)

---

## Landscape descriptor

```gdscript
{
    "biome_seed": "container_favela",
    "palette": ["rust_orange", "wet_concrete", "neon_pink"],
    "skyline": "dense_vertical",
    "density": 0.85,                       # 0=sparse, 1=cramped
    "verticality": 0.7,                    # 0=flat, 1=stacked high
    "weather": "neon_rain",
    "ambient": "distant_sirens",
    "landmarks": [
        { "kind": "black_market", "name": "The Gutter", "danger": 0.3, "utility": "buy_weapons" },
        { "kind": "safehouse", "name": "Old Brine's Garage", "danger": 0.0, "utility": "fast_travel_home" },
        { "kind": "oligarch_outpost", "name": "Compliance Post 14", "danger": 0.8, "utility": "infiltrate" },
        { "kind": "radio_tower", "name": "Pirate 88.8", "danger": 0.2, "utility": "broadcast_propaganda" }
    ]
}
```

---

## Landmarks

Landmarks are the **interactive content** of a landscape. Each region gets 3–5 landmarks, drawn from type-appropriate pools, with randomized names.

### Landmark kinds

| Kind | Where it spawns | Utility |
|---|---|---|
| `safehouse` | Every region | Fast travel, rest, stash; drains Heat slowly |
| `black_market` | Mostly `URBAN_SLUM`, some `TRANSIT` | Buy weapons, ammo, forged IDs |
| `clinic` | `URBAN_SLUM`, `AGRICULTURAL` | Heal, remove tracking chips |
| `oligarch_outpost` | Any non-slum | Low-tier infiltration, intel drop, sabotage |
| `oligarch_villa` | `URBAN_ELITE`, `ISLAND_RETREAT` | Endgame infiltration, assassination target |
| `financial_server` | `URBAN_ELITE` | Hack target → `hack_grid` butterfly |
| `food_depot` / `grain_silo` / `hydro_vault` | `AGRICULTURAL`, `URBAN_SLUM` | Sabotage → food price spike |
| `refinery` / `foundry` / `power_relay` | `INDUSTRIAL` | Sabotage → tech/energy price spike |
| `checkpoint_scanner` / `smuggler_tunnel` | `TRANSIT` | Gate control, contraband passage |
| `radio_tower` / `media_spire` | `URBAN_ELITE`, `INDUSTRIAL` | Broadcast propaganda → tension shift |
| `comm_jammer` | `ISLAND_RETREAT` | Disable NetFeed locally; required for island infiltration |
| `private_dock` / `escape_vessel` | `ISLAND_RETREAT` | Block Oligarch "Escape" ambition |
| `senate_hall` | `URBAN_ELITE` (rare) | Political pressure amplifier |
| `cultural_site` | Any | Optional; hooks for [cameo encounters](../03-characters/cultural-cameos.md) |

### Naming

Landmark names are LLM-seeded with flavor: *"The Gutter"*, *"Old Brine's Garage"*, *"Compliance Post 14"*, *"Pirate 88.8"*. Fallback: `"{Adjective} {Noun}"` pools per kind.

---

## Generation algorithm

```
for each region in regions:
    pick biome_seed from RegionGenerator
    lookup palette, skyline, tileset, density from biome library
    weather ← random(weather_pool[region.type])
    verticality ← type-appropriate range
    landmark_count ← clamp(3 + randi(3), 3, 5)
    for i in landmark_count:
        kind ← weighted_pick(landmark_pools[region.type])
        name ← LLM or fallback pool for kind
        danger ← derived from region.security_modifier + kind baseline
        utility ← kind-defined
    attach descriptor to region
```

Geometry generation (later phase): each tile-set renders the descriptor into 3D CSG geometry at the region's coordinates. Until then, the descriptor drives 2D map UI and event text.

---

## Cross-references
- [Regions](regions.md) — the logical layer landscapes sit on top of
- [Visuals](../05-systems/visuals.md) — palette and shader details
- [Cultural Cameos](../03-characters/cultural-cameos.md) — some cameos spawn `cultural_site` landmarks (Paper Street, for instance)
- [Butterfly Effect](butterfly-effect.md) — which landmarks fire which ripples when sabotaged
