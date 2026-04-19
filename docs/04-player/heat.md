# Heat & Enforcement

> **Status:** Partial implementation. See [src/core/PlayerManager.gd](../../src/core/PlayerManager.gd) and [src/entities/EnforcerPatrol.gd](../../src/entities/EnforcerPatrol.gd).

The world is watching. Heat is how loudly.

Every illegal move stacks signal the Compliance AI picks up. Past the thresholds, the world stops just warning you and starts sending people.

---

## The two layers

The enforcement system is two distinct things working together:

1. **Heat** — a numeric 0–100 resource on the player (see [PlayerManager.heat](../../src/core/PlayerManager.gd)). Changes via `add_heat()` / `cool_heat()` with signals.
2. **Enforcer patrols** — physical entities in the landscape that roam, detect, and can halt the player. Scaled by `security_presence` + heat + day/night.

Heat is the *abstract* signal; patrols are the *embodied* response. You can raise heat doing something out of sight of a patrol — but the patrols you meet later will have *read your file*.

---

## Sources of heat

Comprehensive list in [progression.md](progression.md#heat-system). Representative sample:

| Action | Heat |
|---|---|
| Sabotage Food / Energy depot | +3 |
| Sabotage Tech / Pharma facility | +4 |
| Sabotage Security asset | +5 |
| Sell scandal to Media | +2 |
| Bribe a politician | +2 |
| Hack the Grid | +8 |
| Assassinate an oligarch | max |
| Flee a patrol (fail) | +25 |
| Passive idle (per day) | −1 |
| Forged IDs purchase | −25 |
| Bribe an Enforcer patrol | −20 |
| Flee a patrol (success) | −10 |

---

## Threshold effects (implemented)

| Threshold | Effect | Where |
|---|---|---|
| `heat ≥ 30` | NetFeed note: *"Enforcer patrols thicken near the Sinks."* Patrols *may* fire proximity encounters from this level up. | [PlayerManager.add_heat](../../src/core/PlayerManager.gd) / [EnforcerPatrol.HEAT_DETECTION_THRESHOLD](../../src/entities/EnforcerPatrol.gd) |
| `heat ≥ 60` | Sabotage loot **halved** (you have no time to pick it clean). NetFeed: *"Compliance AI flags a person of interest."* | [WorldDirector._ripple_sabotage](../../src/core/WorldDirector.gd) |
| `heat ≥ 80` | Bribe costs (politicians *and* Enforcers) **doubled** surcharge. Enforcers **refuse** bribes outright. NetFeed: *"Arrest warrants issued; checkpoints running live facial scans."* | [WorldDirector.effective_bribe_cost](../../src/core/WorldDirector.gd) / [HUD encounter modal](../../src/scenes/HUD.gd) |
| `heat == 100` | **Run ends.** `PlayerManager.defeat_triggered("ARRESTED", ...)` fires. End-of-run modal with `// DEFEAT //` banner. | [PlayerManager.add_heat](../../src/core/PlayerManager.gd) |

---

## Enforcer patrols

[EnforcerPatrol.gd](../../src/entities/EnforcerPatrol.gd) — ambient, visible, embodied enforcement.

### Appearance

- Dark navy capsule with black helmet and an **amber emissive shoulder strap** that reads at distance. The strap is the badge: you learn the silhouette in seconds.
- A short forward-facing amber rod suggests a scanning beam.
- Paint matches the biome palette's accent color for consistency.

### Spawning

`LandscapeGenerator._spawn_enforcer_patrols()` runs at landscape build time and on every `TimeSystem.phase_changed` (despawning the previous batch first). **Also mid-phase** whenever the player's heat crosses 30 / 60 / 80 upward — the street reshapes faster than it used to.

```
base_count = 2
+ max(0, (security_presence - 50) / 15)    # +0..+3 from Enforcer saturation
+ max(0, (heat - 30) / 20)                 # +0..+3 from your own heat
× 1.8 if is_night                          # night doubles patrol density
× TimeSystem.patrol_count_multiplier()     # 0.9→1.5 by pacing band (year-arc)
clamp 0..8 (cap 12 during active alert)
```

- A calm slum in the morning, month 2 (Settling ×0.9): ~2 patrols.
- Same slum at night, security=70, month 7 (Escalation ×1.15): `2 + 1 = 3`, ×1.8 = 5, ×1.15 = ~**6** patrols.
- Endgame month 13 (Year's End ×1.5), night, heat 90, security 80: `2 + 2 + 3 = 7`, ×1.8 = 13, ×1.5 = 20 → **capped at 8** (or 12 during active alert).

Patrols walk between two random street cells (street-aligned grid rows/columns), looping indefinitely. Each has a 6-meter detection radius. When the player enters that radius *and* `heat ≥ 30`, the patrol fires its `encountered_player` signal and the HUD pauses for an encounter modal.

### Alert memory + reinforcements

The landscape holds `_last_known_player_position`, set on any fired encounter. For 2 phase boundaries after the event, new patrols spawn biased toward that point (within 30m). Existing patrols have their A↔B waypoints lerp toward it and a **red strobe** lights on their shoulder strap — you can see alerted patrols converging at distance.

**On a failed flee** from the encounter modal, `LandscapeGenerator.raise_alert(player_pos, spawn_reinforcements=true)` fires. Three reinforcement patrols spawn within ~15m of the player's position (cap relaxed to 12 in this emergency). Alerted patrols move 1.4× faster. Over ~3 real minutes of play the alert decays; the world forgets where you were.

### Day/night bias

See [time-and-day-night.md](../05-systems/time-and-day-night.md). Enforcer NPCs skew night-biased in the population (35% night-only vs 15% day-only), and patrol density multiplies ×1.8 at night. Night is when the checkpoints bite.

---

## Encounter modal

When a patrol fires, the game pauses and the HUD modal shows:

```
// ENFORCER CHECKPOINT //

    Halt.

An Enforcer flags you down. Your heat reads 54/100.
Their squad is listening in.

[ BRIBE — 540 cr (waved through) ]
[ FLEE  — 58% escape (stealth-weighted) ]
[ SUBMIT — run ends, arrest flavor ]
```

There is **no Escape** out. You pick one.

### BRIBE

- Cost = `max(200, heat × 200 / 20)` — so 200 cr at heat 20, 540 cr at heat 54, 1000 cr at heat 100.
- **Gated: not accepted above `heat > 80`.** At high heat you're too hot to corrupt — they've been told to bring you in.
- Button shows *"they won't take it tonight"* when gated, *"you can't afford"* when broke.
- On success: spend credits, `−20 heat`, patrol despawns, NetFeed: *"An Enforcer patrol was 'resolved' at a checkpoint near the Sinks. No incident report filed."*

### FLEE

- Escape chance = `clamp(0.30 + stealth_preference × 0.55, 0.10, 0.90)`.
  - Raw 30% for a loud player; up to 85% for a pure stealth build.
- On success: `−10 heat` (clean break), patrol despawns, NetFeed: *"A fugitive slipped an Enforcer patrol cordon near the checkpoint."*
- On failure: `+25 heat` (ID'd hard), patrol despawns, NetFeed: *"Enforcer body-cam captures a person-of-interest attempting evasion. ID confirmed."* This can cascade into the `heat == 100` defeat if you were already hot.

### SUBMIT

- Calls `PlayerManager.fire_defeat("SURRENDERED", "SURRENDERED", ...)`.
- End-of-run modal appears with the defeat banner.
- Flavor: *"You walked up with hands visible. The shackles came out. The Enclave breathes easier tonight."*

---

## Cooling mechanisms

| Mechanism | Effect | Cost | Availability |
|---|---|---|---|
| Passive daily decay | −1 per world cycle | free | automatic |
| Forged IDs (Shop) | −25 instantly | 500 cr | any time at Datashard Terminal |
| Bribe an Enforcer | −20 | heat-scaled credits | when a patrol halts you, heat ≤ 80 |
| Flee (success) | −10 | stealth roll | when a patrol halts you |
| Safehouse bribe *(designed)* | passive decay while paid | 200/cycle | future |
| Travel to low-security region *(designed)* | −passive | free | requires multi-region travel, future |

---

## Future work (designed, not implemented)

- **Compliance AI hunter arc.** Past `heat ≥ 80`, an NPC-level adversary starts stalking — silent until a tier-changing event, then active pursuit.
- **NPC freeze-out at high heat.** Past `heat ≥ 60`, fixer jobs dry up; NPCs refuse dialogue; trust gains stop.
- **Checkpoint landmarks in TRANSIT regions.** Per-region chokepoints you can't walk around — you have to bribe, disguise, or sabotage.
- **SWAT / military tiers.** Beyond Enforcers (the basic tier), paramilitary units at `heat > 70` and military units at `heat > 90`. Higher detection range, lower bribe acceptance, harder flee.
- **Heat-weighted random encounters between patrols.** Even in a quiet region, high heat means the game rolls for ambushes.
- **Per-region-type patrol palettes.** `URBAN_ELITE` patrols are corporate-security in pressed uniforms, not the Enforcer grey.

---

## Cross-references

- [Progression, Credits & Heat](progression.md) — full heat-source table and threshold summary
- [Time, Day/Night, and Fast-Forward](../05-systems/time-and-day-night.md) — phase-driven patrol respawn
- [Landscape Generator](../02-world/landscapes.md) — where the patrols are spawned
- [Cultural Cameos](../03-characters/cultural-cameos.md) — `rogue_ai` archetype is the Compliance AI that high heat unlocks
