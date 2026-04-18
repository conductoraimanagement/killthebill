# Save and Share: World Configs

> **Status:** Implemented. See [src/core/WorldConfigManager.gd](../../src/core/WorldConfigManager.gd).

A **world config** is the procedural *input* to a playthrough — every region, every oligarch, every politician, every citizen, captured at the moment the generator finishes. Save a config, reload the same world later; send it to a friend, they play the same world.

A world config is **not a save-game**. It does not capture what the player has done — no scandals leaked, no bills passed, no oligarchs killed, no cycle count. Load a config and you start the playthrough fresh, with the same roster.

Everything is text (JSON), everything is local (`user://world_configs/`), everything is shareable.

---

## Why this instead of a save-game?

1. **Shareability over continuity.** The interesting thing about a procedurally-generated world is who's in it. Playing a friend's roster — the same 11 senators, the same 4 oligarchs with their quirks, the same Ash Row with the same sabotage targets — is a different experience from loading your own save.
2. **Roguelite-friendly.** The core loop is "each run is new." Saves that freeze progress would undercut that. Configs let players bookmark *worlds they liked*, not *runs they were winning*.
3. **Cheap to ship.** No scene-state serialization, no player-position save, no mid-mission interruption logic. Just the generator output.

---

## What's captured

| Section | Fields |
|---|---|
| **Metadata** | `format_version`, `name`, `description`, `created_at` |
| **Regions** | Full region shells: `id`, `name`, `type`, `security_modifier`, `tension_modifier`, `population_density`, `infrastructure_targets`, `visual_biome`, `connected_oligarch`, `unlocked`, `short_description`. 6–10 per config. |
| **Oligarchs** | Identity + all Nature traits + ambitions + quirks + starting dynamic state (wealth, paranoia, public_image, controversy, political_influence, awareness_of_player). 4–6 per config. |
| **Politicians** | Identity + faction + cause + seat district + all 6 Nature traits + starting public_approval + re_election_proximity + quirks. 11 per config. |
| **NPCs** | Identity + social class + all Nature traits + quirks + starting dynamic state (stress, hope, radicalization, mood, economic need). 40 per config. |
| **Starting region** | The name of the region the player drops into. |

## What's **not** captured

- Current cycle count, scandal ledger, bill history, NetFeed log
- Player credits, position, actions taken
- Active cultural cameos, mid-arc state
- Oligarch_patronage debts politicians have accumulated

If you want to capture those, that's a save-game, not a world config. Scoped out of v1.

---

## File format

One JSON file per config at `user://world_configs/<slug>.json`. The slug is derived from the display name (lowercase, alphanumeric, underscores). Shape:

```json
{
    "format_version": 1,
    "name": "Ash Row Crisis",
    "description": "High tension, populist-skewed chamber, Media oligarch on the ropes",
    "created_at": "2026-04-18T19:45:12",
    "starting_region_name": "Ash Row",
    "regions":     [ { /* RegionGenerator shell */ } ],
    "oligarchs":   [ { /* OligarchData flattened */ } ],
    "politicians": [ { /* PoliticianData flattened */ } ],
    "npcs":        [ { /* NPCData flattened */ } ]
}
```

`format_version` lets future breaking changes migrate old files; load fails fast if the version doesn't match.

---

## Triggers

### In-game

| Input | Effect |
|---|---|
| `F5` | Open save modal — name input pre-filled with `suggest_name()`, optional description |
| `F9` | Open load modal — scrollable list of saved configs + paste-to-import box |

### Victory modal

When [`WorldDirector.victory_achieved`](../../src/core/WorldDirector.gd) fires, the victory modal shows four buttons: `SAVE WORLD`, `LOAD WORLD…`, `RESTART` (scene reload, fresh roll), `CONTINUE` (sandbox play-on). Saving from here is the natural moment — *"that was a good world, keep it."*

---

## Sharing

Three paths, ordered by current ease:

1. **File on disk (ship today).** `user://` resolves to:
   - macOS: `~/Library/Application Support/Godot/app_userdata/KILL THE BILL/world_configs/`
   - Linux: `~/.local/share/godot/app_userdata/KILL THE BILL/world_configs/`
   - Windows: `%APPDATA%\Godot\app_userdata\KILL THE BILL\world_configs\`

   Send the `.json` file; recipient drops it into their own `world_configs/` folder; appears in their load modal.
2. **Copy to clipboard (ship today).** In the load modal, each saved row has a `COPY` button — dumps the full JSON to the clipboard. Paste it into a message, gist, forum post.
3. **Paste to import (ship today).** The load modal's paste box accepts raw JSON → `LOAD` → scene reload with that config applied. No filesystem touch required.

Later sprints can add: Steam Workshop / cloud saves, seed-based sharing (regenerate from a seed rather than transmitting full JSON), curated "community worlds" gallery.

---

## Load mechanics

```
user picks config in HUD load modal
  → WorldConfigManager.load_from_file(path)       # or load_from_string()
  → apply_and_restart(config)                      # sets pending_config
  → get_tree().reload_current_scene()              # fresh Main._ready()
  → Main reads pending_config, passes to
    WorldDirector.initialize_playthrough(config)
  → _apply_preloaded_config() injects roster
    directly into RegionGenerator / oligarchs /
    politicians / PopulationDirector, skipping
    LLM calls entirely
  → playthrough_setup_complete fires
  → LandscapeGenerator re-renders the 3D world
    from the same region data + biome seed (deterministic)
  → player sees the identical map, rosters, factions
```

LLM calls are fully bypassed on load — the LLM's creative output was already baked into the saved JSON, so two players with the same config see the same names, quirks, and ambitions whether or not they have API keys.

---

## Versioning & durability

- `format_version` bumps when the schema breaks in a way old loaders can't handle. On mismatch, load fails with a clear error.
- Adding new optional fields does **not** bump the version; rehydrators default-fill missing keys (`o_dict.get("corruption", 0.5)`).
- Removing fields is a breaking change → version bump + migration.
- The save files are checked in by the user, not by the repo — they live in `user://`, never touch git.

---

## Cross-references

- [Regions](../02-world/regions.md) — the region shells that fill `regions` in a config
- [Oligarchs](../03-characters/oligarchs.md) — the fields serialized per oligarch
- [Politicians](../03-characters/politicians.md) — the fields serialized per politician
- [Landscapes](../02-world/landscapes.md) — deterministic 3D regeneration from config data
- [The Senate](../02-world/senate.md) — post-load the Senate runs fresh; bills are not serialized
