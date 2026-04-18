# Relationships & Agent System — Technical Reference

## Bond Tiers
| Tier | Name | Int | Can Recruit? | Willingness Bonus |
|---|---|---|---|---|
| 0 | None | 0 | No | — |
| 1 | Acquaintance | 1 | No | — |
| 2 | Friend | 2 | Yes (trust ≥ 30) | +0.0 |
| 3 | Close Friend | 3 | Yes (trust ≥ 30) | +0.0 |
| 4 | Romantic | 4 | Yes | +0.2 |
| 5 | Loyal Operative | 5 | Yes | +0.3 |

## Trust Mechanics
- **Builds through:** Sharing resources, saving from Enforcers, successful missions (+15), aligned dialogue choices
- **Decays through:** Pushing refused objectives (-5), failed missions (-20), betrayal, hurting their immediate_need

## Agent Recruitment (`can_recruit()`)
Requirements: `relationship_type >= 2` AND `trust >= 30.0`

## Objective Willingness Formula
```
base = trust / 100.0
  + relationship_bonus
  + empathy * 0.1
  - greed * 0.1
  + idealism * 0.1
  - risk_level * (1.0 - aggression * 0.5) * 0.3

willingness = clamp(base, 0.0, 1.0)
success = randf() < willingness
```

## Refusal Tones (personality-driven)
- High aggression: "Don't push me. I said no."
- High empathy: "I want to help, but this is too much."
- High greed: "What's in it for me?"

## Objective Resolution
- **Success:** trust +15, memory added, bond history logged
- **Failure:** trust -20, stress +15, memory added. If trust <10: relationship degrades one tier.
