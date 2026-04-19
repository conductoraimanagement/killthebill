# Landscapes

> **Status:** Implemented. See [src/core/LandscapeGenerator.gd](../../src/core/LandscapeGenerator.gd).

A [region](regions.md) is the *logical* slice of the world — its type, its economy modifiers, its Oligarch. A **landscape** is the *physical* slice — the biome, the skyline, the street the player actually walks down.

Every region gets one landscape, generated at playthrough start, persistent for the run. Geometry is deterministic — the same region name + biome seed produces the same map on any machine, which is why [world configs](../05-systems/save-and-share.md) can be shared.

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
| `financial_center` / `clearing_house` | `URBAN_ELITE` | Sabotage → Finance shock (rent ×1.15 for 10 days, food+tech prices +30, tension +20) |
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

## Generation algorithm (current implementation)

`LandscapeGenerator.generate(region_data)` is called by Main once [WorldDirector](../../src/core/WorldDirector.gd) signals `playthrough_setup_complete`. The flow:

```
1. Look up REGION_CONFIGS[region.type]          # base config per region type
2. _apply_biome_variant(region.visual_biome)    # lightweight overrides
3. seed ← hash(region.name + region.visual_biome)
4. Build NavigationRegion3D + ground plane
5. Build per-biome environment (sun, fog, ambient light)
6. For each grid cell:
     skip if on a street row (every 4th x or z)
     roll against building_density
     if hit: spawn a two-box stacked building at cell center (jittered)
            height = randi(height_range) × 3m, colors from palette
7. Reserve two empty cells for food depot + datashard terminal
8. Choose a safe center-ish empty cell for player spawn
9. Scatter per-biome props (barrel fires, planters, smoke stacks, etc.)
10. Bake the navigation mesh
11. Emit landscape_ready(self) with player_spawn + landmark_spawns
```

Deterministic: the same region name + biome seed always produces the same layout. Shared [world configs](../05-systems/save-and-share.md) therefore reproduce identical geometry across machines, without having to transmit mesh data.

### Per-region-type base config (current)

| Region type | Map size | Cell | Density | Height range (stories) | Prop |
|---|---|---|---|---|---|
| `URBAN_SLUM` | 160 × 160 | 7.5m | 0.58 | 2–6 | `barrel_fire` |
| `URBAN_ELITE` | 150 × 150 | 10m | 0.28 | 7–14 | `planter` |
| `INDUSTRIAL` | 170 × 170 | 10m | 0.42 | 2–7 | `smoke_stack` |
| `AGRICULTURAL` | 180 × 180 | 9m | 0.22 | 1–3 | `grow_lamp` |
| `ISLAND_RETREAT` | 110 × 110 | 9m | 0.14 | 2–5 | `palm` |
| `TRANSIT` | 200 × 100 | 8m | 0.24 | 2–4 | `warning_beacon` |

### Biome variants

Each biome seed nudges the base config — density, heights, palette, fog, accent color — so the 36 biome variants read as distinct without needing 36 full configs. See `_apply_biome_variant()` for the full list. Examples:

- `container_favela` → density `0.66`, heights `2–5`
- `glass_spire` → heights `10–18`, density `0.22`
- `molten_core` → accent color blood-orange, fog orange-brown
- `arctic_retreat` → ground + fog both pale blue-white
- `open_steppe` → density `0.10`, prop count `40`

### Landmark & spawn resolution

`LandscapeGenerator` reserves grid cells for the datashard terminal, places a transit-zone pillar at the map edge, and spawns 1–2 sabotage targets whose kind is chosen by the region's type. It picks a safe spawn for the player near the center and emits `sabotage_target_spawned` per target so Main can wire interaction signals without needing a fixed list.

### Per-region landmark recipes

Each region type gets sector-appropriate sabotage targets so cameo objectives that name a sector (e.g. *"disrupt Security"*) can actually be satisfied by traveling to a matching region:

| Region type | Sabotage kinds | Sector(s) covered |
|---|---|---|
| `URBAN_SLUM` | food_depot | Food |
| `URBAN_ELITE` | financial_center + media_spire | Tech + Media |
| `INDUSTRIAL` | refinery + power_relay | Tech + Energy |
| `AGRICULTURAL` | hydro_vault + grain_silo | Food |
| `ISLAND_RETREAT` | private_dock | Security |
| `TRANSIT` | checkpoint_scanner | Security |

**Financial Center** (new) — tall cyan glass column, Tech-sector sabotage target. Unique to `URBAN_ELITE` — the Enclave's money lives in glass. Same ripple as any Tech-sector hit: `tech_price +150`, `+4 heat`, the Tech oligarch loses 50k wealth.

Visual profile per kind lives in `InteractableTarget.KIND_CONFIGS` — mesh shape (box / tall_box / cylinder), size, albedo + emission color, display prefix. One entity class, many kinds.

---

## What's still *not* in the implementation

- Full tile-set / modular geometry library (buildings are stacked box prims for now).
- Region-level landmark taxonomy beyond `food_depot` + `datashard_terminal` (the doc's landmark kinds table remains aspirational).
- Biome-specific detail props (only one prop kind per region type is scattered today).
- Weather + ambient audio layers.
- Transit edges linking regions — every playthrough is still one playable region.

---

## Cross-references
- [Regions](regions.md) — the logical layer landscapes sit on top of
- [Visuals](../05-systems/visuals.md) — palette and shader details
- [Cultural Cameos](../03-characters/cultural-cameos.md) — some cameos spawn `cultural_site` landmarks (Paper Street, for instance)
- [Butterfly Effect](butterfly-effect.md) — which landmarks fire which ripples when sabotaged
