# Economy

The global economy is a five-variable vector, owned by [WorldDirector](../05-systems/architecture.md). Every system in the game reads or writes it. Regions apply local modifiers on top ([regions.md](regions.md)).

---

## Global variables

| Variable | Range | Meaning | High state | Low state |
|---|---|---|---|---|
| `food_price` | 0–∞ (soft-capped UI ~500) | Cost of survival | Starvation, riots | Stable tables |
| `tech_price` | 0–∞ | Cost of ammo, drugs, mods | Scarcity, black market boom | Cheap gear |
| `security_presence` | 0–100 | Enforcer saturation | Martial law | Unpatrolled streets |
| `public_tension` | 0–100 | Mass-level anger | Rioting, revolution-ready | Docile, complacent |
| `senate_alignment` | 0–100 | Political pole — moved by bills passed in [the Senate](senate.md) | 100 = fully Pro-Enclave, 0 = fully Pro-Sinks | — |

These variables are the **nerves of the simulation**. They:
- flow into every NPC's `process_world_pressure()` each cycle
- flow into every Oligarch's `process_world_state()` each cycle
- drive region dynamics
- drive the NetFeed's event generation
- drive victory checks

---

## Sectors

Five core sectors, two optional. Oligarchs are distributed randomly across sectors — **a sector can have multiple oligarchs, or none at all**. You never know which billionaire owns what until the NetFeed tells you (see [oligarchs.md](../03-characters/oligarchs.md)).

| Sector | Tied to | Player leverage |
|---|---|---|
| **Food** | `food_price` | Sabotage agricultural infrastructure → price spike → tension rise |
| **Tech** | `tech_price` | Destroy refineries → price spike; disrupt uplinks → blackouts |
| **Security** | `security_presence` | Political pressure on Senate; assassinate security Oligarch |
| **Media** | `senate_alignment`, controversy suppression | Leak scandals; destroy media spires; persuade journalists |
| **Finance** | `food_price` + `tech_price` shock, rent drain | Hack or sabotage clearing houses → 10-day rent-multiplier shock + freeze consumer debt records; Finance sabotage loots 800–1,400 cr and costs +6 heat |
| **Pharma** *(optional)* | `tech_price` bleed | Similar leverage to Tech |
| **Energy** *(optional)* | `tech_price` bleed, `security_presence` bleed | Blackouts amplify tension |

**The Finance shock** — sabotaging a Finance landmark (clearing house or financial center) fires `apply_finance_shock()`: the player's daily rent cost is multiplied by 1.15 for 10 daily ticks, and food/tech prices both jump +30. Finance sabotage carries the highest tension wave (+20 vs +15 for other sectors) — credit markets going dark reaches further than a single grain silo does.

**Debt attribution** — if the Finance oligarch exists at run-start, the player's starting rent debt is attributed to them (`debt_held_by_oligarch_id`). Killing that oligarch or completing a debt-jubilee cameo arc (e.g. **Indexed Debt**) can wipe that debt.

---

## Derived sector dynamics

Per-region values are re-derived each cycle from globals:

- **Slums**: +20 tension baseline; jumps further when food is scarce
- **Enclave**: −20 tension baseline; jumps further when senate aligned with them
- **Industrial**: tension follows security — cheap labor is suppressed labor
- **Agricultural**: tension is low until food prices swing; then spikes fast
- **Transit**: security always elevated
- **Islands**: near-zero tension, high security always

See `WorldDirector._update_region_dynamics()`.

---

## The economy as a feedback loop

The economy is not a set of independent sliders. Actions cascade:

```
Sabotage Food Supply
  → food_price +200
  → public_tension +15
  → security_presence +10
  → Food Oligarch paranoia +20
  → Food Oligarch raises prices (greed response) next cycle
  → public_tension climbs further
  → a Worker NPC radicalizes
  → a Destitute NPC dies off-screen (NetFeed reports it)
  → Media Oligarch buys the story to suppress it
  → senate_alignment shifts Pro-Enclave
```

The cascade logic lives in the [Butterfly Effect matrix](butterfly-effect.md) and in each billionaire's `process_world_state()` ambition pursuit.

---

## Design notes

- **No direct player wallet here.** The player has credits (see [progression.md](../04-player/progression.md)), but the global economy is about the *world*. The player's pocket is a cost, not a victory condition.
- **No single variable collapses the game.** Victory requires a combination (see [victory.md](../04-player/victory.md)).
- **Black swans are rare but possible.** The NetFeed can cause sudden swings (a pandemic, an assassination nobody expected, a cameo-triggered event). The economy must survive discontinuities without becoming oscillating noise.

---

## Player economy — real-world-calibrated (1 credit ≈ 1 USD)

Every credit number in this game maps to a real dollar of a real 2025-ish US economy. *Not abstract game points.* This is deliberate: the player looking at `1,873 cr` should read it as the same weight as $1,873 feels in real life.

### Starting wallet

| Class | Start | Interpretation |
|---|---|---|
| White Collar | 50,000 cr | Severance + liquidated 401(k). A year of frayed cushion if you're careful. |
| Blue Collar | 29,000 cr | Union payout + cashed-out savings. Covers the year if nothing goes wrong. Something always goes wrong. |

### Fixed monthly burn

- **Rent**: rolled once at run-start in `[700, 2000] cr`. Broad range — a lucky Sinks studio vs. an unlucky one. Paid monthly via HUD prompt (`rent_due_prompt` on month rollover). Two months unpaid → eviction. See [victory.md](../04-player/victory.md) and [loop.md](../04-player/loop.md).
- **Daily food & utilities**: 25 cr + `(food_price − 100) / 3`. Homeless adds +8 cr/day (the exposure tax).

### Income sources

| Source | Range | Cadence | Risk |
|---|---|---|---|
| Gig shift (dishwasher, sweeper, delivery, waiter, day-labor, trash) | 30–84 cr + tips | Accrues; paid weekly | 40% silent denial, hope-cost humiliation |
| Resistance cell job | 500–2,500 cr | On completion | Sabotage/leak requirement, +heat |
| NPC fixer leak | 150–350 cr | On completion | Fixer trust |
| NPC fixer sabotage | 200–400 cr | On completion | +heat |
| Sabotage loot | 200 cr (Food) → 1,400 cr (Finance) | Immediate | +heat per sector |
| Pickpocket | 20–80 cr | Immediate | +1 heat on success / +3 on failure |

### Spend sinks

| Item | Cost |
|---|---|
| Forged IDs (−25 heat) | 500 cr |
| Burner datashard | 1,500 cr |
| Secure housing (if homeless) | one month's rent (700–2,000 cr) |
| Enforcer bribe | 200 cr + 200 cr per 20 heat (capped) |
| Politician bribe | ~2,000 cr base, scandal/corruption discount |

Cameo arcs **do not pay credits**. The cameo reward is a world-state shift (tension / senate / idealism) plus any narrative-specific payoff — e.g. the Indexed Debt jubilee wipes the player's rent arrears and clears Finance-oligarch debt attribution.
