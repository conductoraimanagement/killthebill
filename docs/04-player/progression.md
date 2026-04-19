# Progression, Credits, and Heat

> **Status:** Partial implementation. See [src/core/PlayerManager.gd](../../src/core/PlayerManager.gd).

The player's personal economy is where the design gets honest. You're a broke operative in a collapsing city. Every move costs. The only way to keep acting is to do things that compromise the cause a little — or make you more wanted.

Two resources, one law: **nothing is free.**

---

## The two resources

| Resource | Range | Where it lives | High state | Low state |
|---|---|---|---|---|
| `credits` | 0..∞ | [PlayerManager](../../src/core/PlayerManager.gd) | Can bribe senators, buy intel, afford forged IDs | Stuck. Can't act. |
| `heat` | 0..100 | [PlayerManager](../../src/core/PlayerManager.gd) | Enforcer sweeps, checkpoint flags, NPC intel drops degrade | Invisible. Can work unnoticed. |

Every income source **raises heat**. Every spending source is either legal (no heat) or illegal (credits + heat). The only thing you can freely do is walk around — and even that, once you're hot enough, draws attention.

---

## Class Seeds (starting conditions)

See [`PlayerManager.initialize_run(seed)`](../../src/core/PlayerManager.gd). Called at the start of every playthrough.

| Seed | credits | intel_level | social_capital | What it means |
|---|---|---|---|---|
| `WHITE_COLLAR` | 5000 | 100 | −50 | Comfortable start, good intel access, but the Sinks don't trust you. Compliance AI hunts you sooner. |
| `BLUE_COLLAR` | 100 | 10 | 80 | Broke but trusted. NPCs open up faster. No Enclave contacts. |

Class seeds are the game's replay flavor: the same world plays differently depending on how you started.

**Future seeds** (designed, not implemented):
- `SYNDICATE` — starts with debt to an Oligarch rival; forgiven after N sabotage jobs.
- `JOURNALIST` — starts with a press contact; trades credits for scandal verification.
- `VETERAN` — high skill / heat resistance, no social capital.

---

## Income mechanisms

Six sources. Each has a thematic tradeoff so the economic pressure *is* the moral pressure.

### 1. Loot from sabotage ✓ *(implemented)*
Sabotaging a facility drops credits in addition to the economy ripple. The payout scales with the sector being hit.

| Sector | Base payout | Heat | Why |
|---|---|---|---|
| Food | 300–600 | +3 | Warehouses, pallets of rations |
| Tech | 500–900 | +4 | Server racks worth black-market gold |
| Pharma | 600–1000 | +4 | Every capsule is cash |
| Energy | 400–700 | +3 | Copper, rare earths |
| Security | 200–400 | +5 | Gear + arrest risk |
| Media | 200–500 | +2 | PR assets, less tangible haul |

**Tradeoff**: every sabotage raises public tension, attracts Enforcers, and identifies you as a threat. The richer sectors carry the most heat.

### 2. Sell scandal to Media oligarch ✓ *(implemented)*
You've surfaced dirt on an oligarch. Two paths:

- **LEAK** (free, existing): NetFeed picks it up. Public sees it. `public_image` of target tanks, `public_tension` up, `senate_alignment` drifts slightly populist.
- **SELL** (money, new): the Media Oligarch buys the scoop to shelve it. You get paid; the scandal never surfaces. The target's `controversy_level` drops (suppressed), `senate_alignment` shifts corporate.

```
payout ≈ 500 + target.controversy_level × 30    # reward for having juicy dirt
         + 1000 if Media oligarch alive          # premium for the buyer being there
```

**Tradeoff**: the corrupt option. Money now, strengthened Enclave later. The game watches and remembers (future: player_idealism tracker tanks, cameo arcs gate off).

### 3. Rival oligarch contract ✓ *(implemented)*
Each news cycle, the game rolls ~65% odds of posting a contract from a living oligarch A targeting a rival oligarch B's sector (different sectors only). NetFeed headline: *"Bounty circulating in the black market — A wants B's infrastructure damaged."*

Any sabotage of B's sector within the TTL window (3 cycles) pays the full bounty (800–2500 credits). On completion:

- `PlayerManager.credits +bounty`
- `contractor.wealth -bounty` (they paid up)
- `contractor.paranoia -5` (they got what they wanted)
- Contract removed from `active_jobs`

If no one claims the contract in 3 cycles, it expires with a NetFeed note. A new contract replaces it on the next news cycle.

**Tradeoff**: you're becoming a tool of one oligarch against another. A's portfolio grows, their paranoia drops, the target weakens but the Enclave as a whole rebalances rather than shrinking.

### 4. Fixer jobs from NPCs ✓ *(implemented)*
NPCs with `trust >= 30` can post a fixer job via NetFeed: *"Fixer signal in the Sinks — Jon Holt wants the Food sector disrupted. They say it's personal."*

Two flavors roll from the available actions:
- **Disrupt sector**: sabotage a random sector. Pays 400–900.
- **Leak on oligarch**: leak scandal on a specified oligarch. Pays 300–700.

On completion:

- `PlayerManager.credits +bounty`
- `fixer_npc.trust +15` (bond_history records it)
- NetFeed: *"NPC quietly paid an unnamed operative. A debt acknowledged."*

Starting trust: NPCs roll `randf_range(0, 60)` on generation (Enforcers are colder; Workers and Destitute trust the player sooner), so ~35% of the roster starts above the 30 threshold for posting jobs. As the player completes fixer jobs, that NPC's trust rises, possibly crossing the `can_recruit()` threshold for [relationships](../03-characters/relationships.md) agent-network mechanics.

**Tradeoff**: the small, human-scale economy. No senate_alignment shift, no paranoia amplification, no oligarch patronage debt. Just a citizen paying you for a favor. But the bounties are smaller, and you can only run one at a time per NPC.

### 5. Pickpocket / mug *(designed, not implemented)*
Ambient crowd-NPCs and Enforcer patrols in the streets. Interact → stealth roll.

| Target | Success payout | Fail consequence |
|---|---|---|
| Crowd NPC | 20–80 | +1 heat, NPC awareness leaks |
| Enforcer | 300–600 + gear | +5 heat, possible combat |

**Tradeoff**: reliable-ish chunks of income but heat compounds. Can't sustain on this alone.

### 6. Hack ATM / financial node *(designed, not implemented)*
`URBAN_ELITE` landscapes host `financial_server` landmarks. Hack to siphon credits; leaves a trail the Tech Oligarch notices.

**Tradeoff**: biggest one-shot payout (1000–3000) but dedicated counter-intel from the victim Oligarch. Paranoia ramps, investigators deploy.

---

## Spending mechanisms

### Implemented

**Bribe a politician on an active bill** — at the [Datashard Terminal](../../src/entities/DatashardTerminal.gd), menu → `LOBBY POLITICIAN`. Shows each senator with their predicted stance on the current bill and a cost:

```
cost = 2000 × (1 − scandal_level/100) × (1 − corruption)
clamped ≥ 100
```

A scandal-riddled, corrupt senator runs ~100 credits to flip. A clean, principled senator runs up to 2000. The bribe lasts one vote — `pending_bribe_direction` is cleared after SenateDirector resolves the bill. Raises heat by 2.

**Sabotage / leak-scandal** (existing) — no credit cost, but heat cost.

### Designed, not implemented

| Action | Cost range | What it unlocks |
|---|---|---|
| Buy intel from a fixer | 200–800 | Reveals `scandal_hooks` on pending bills, or a random oligarch's current ambition |
| Forged IDs | 500 | Drops heat by 25 |
| Safehouse bribe | 200/cycle | Passive heat decay while paid up |
| Black-market weapon | 800–2500 | Unlocks the combat lever (future) |
| Recruit cameo operative | 3000+ | When a cultural cameo arc resolves with recruitment |

---

## Heat system

`heat` is 0–100, capped. Raises on illegal acts:

| Event | Heat delta |
|---|---|
| Sabotage a facility | +2 to +5 (see sector table) |
| Sell scandal to Media | +2 (it's a *crime* to deal in stolen info) |
| Bribe a politician | +2 |
| Pickpocket / mug | +1 to +5 |
| Hack financial grid | +8 |
| Assassinate oligarch *(existing)* | Sets heat to max |
| Cycle tick *(passive)* | −1 (heat slowly cools) |

At high heat, the landscape gets hostile:
- `heat > 30`: Enforcer patrols spawn ambient in slum/transit landscapes *(future)*
- `heat > 60`: NPCs refuse to talk to you; fixer jobs dry up *(future)*
- `heat > 80`: compliance AI actively hunts; every interactable has a trap roll *(future)*
- `heat == 100`: martial hunt — single mistake ends the run *(future)*

Cooling mechanisms:
- Idle time (passive decay)
- Forged IDs (designed, not yet implemented)
- Safehouse bribe (designed)
- Travel to a low-security region *(requires multi-region travel, future)*

---

## UI

The HUD state panel (top-left) shows two extra rows at the bottom:

```
credits           1850    (color: cyan if ≥ 1000, fg if > 200, dim if ≤ 200)
heat                34    (color: hot red if > 60, warn yellow if > 30, fg otherwise)
```

Both update via signals (`credits_changed`, `heat_changed`) so the HUD never polls.

---

## What the player can't do (by design)

- **Farm endless credits without consequences.** Every income source raises heat or senate_alignment or erodes an NPC bond.
- **Buy victory.** Credits can't directly move global economy variables. They can only pay for *actions* that move them (bribes, sabotage gear).
- **Stockpile past what a run needs.** Roguelite run-end zeros credits; the `SYNDICATE` seed even starts them negative.

---

## Cross-references

- [PlayerManager](../../src/core/PlayerManager.gd) — source of truth for `credits` and `heat`
- [WorldDirector](../../src/core/WorldDirector.gd) — ripples now call `PlayerManager.add_credits`/`add_heat`
- [Politicians](../03-characters/politicians.md) — the `bribe` action is defined there and implemented via `get_bribe_cost()` + `pending_bribe_direction`
- [Oligarchs](../03-characters/oligarchs.md) — sell-scandal reads `controversy_level` and reacts on their side
- [The Senate](../02-world/senate.md) — bribes are resolved when `_tally_and_resolve` runs; pending bribes are cleared after the vote
- [Cultural Cameos](../03-characters/cultural-cameos.md) — several cameo archetypes gate on the player's cumulative choices in the economy layer (`chaos_prophet` likes money-hungry players, `kindly_stranger` likes fixer-job-only players)
