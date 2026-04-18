# Relationships & Agents

> NPCs aren't quest-givers. They're people you build trust with — or burn through. When trust is high enough, they become operatives you can send on missions.

Implemented across: [NPCData.gd](../../src/entities/NPCData.gd) (per-NPC state) + helper functions called from dialogue / persuasion flows.

---

## Bond tiers

| Int | Name | Can recruit? | Willingness bonus |
|---|---|---|---|
| 0 | None | No | — |
| 1 | Acquaintance | No | — |
| 2 | Friend | Yes (trust ≥ 30) | +0.0 |
| 3 | Close Friend | Yes (trust ≥ 30) | +0.0 |
| 4 | Romantic | Yes | +0.2 |
| 5 | Loyal Operative | Yes | +0.3 |

Tiers change through accumulated bond-history events. A degradation (below trust 10 after a failed mission) drops a tier.

---

## Trust

**Builds through:**
- Sharing resources (+5 per meaningful share)
- Saving from Enforcers (+15)
- Successful missions (+15)
- Dialogue aligned with their trait profile (+1 to +3 per well-chosen line)

**Decays through:**
- Pushing a refused objective (−5)
- Failed missions (−20)
- Betrayal (−50)
- Hurting their `immediate_need` (context-driven, −5 to −30)

### `immediate_need`
A per-NPC field surfaced at generation: "Needs medicine for her son", "Hiding from an Enforcer manhunt", "Behind on rent to a slum-lord". When the player's actions impact this need, trust swings sharply. Players who *pay attention* gain trust fast.

---

## Agent recruitment

```gdscript
can_recruit(npc):
    return npc.relationship_type >= 2 and npc.trust >= 30.0
```

Recruited NPCs are **assigned** (not controlled). They take an objective and attempt it off-screen with a willingness roll.

---

## Objective willingness

```
base = trust / 100.0
     + relationship_bonus           # 0.0 / +0.2 / +0.3 by tier
     + empathy   * 0.1              # idealists care
     - greed     * 0.1              # greedy want a cut
     + idealism  * 0.1              # true believers say yes
     - risk_level * (1.0 - aggression * 0.5) * 0.3   # aggressive NPCs fear less

willingness = clamp(base, 0.0, 1.0)
success     = randf() < willingness
```

Failure does **not** mean the mission fails; it means the NPC refuses. They stay on roster. A refusal that's pushed harder costs trust.

---

## Refusal tones

LLM-generated, seeded by trait:
- High `aggression`: *"Don't push me. I said no."*
- High `empathy`: *"I want to help, but this is too much."*
- High `greed`: *"What's in it for me?"*
- High `conformity`: *"You're asking me to break the law. I can't."*
- High `idealism` but wrong ask: *"This is beneath what we're fighting for."*

---

## Objective resolution

| Outcome | Trust | Stress | Bond history |
|---|---|---|---|
| Success | +15 | — | "Ran courier job for [player]. Succeeded." |
| Failure | −20 | +15 | "Failed the [mission]. Burned contacts." |
| Betrayal | −50 | +30 | "Was betrayed by [player]." |

If trust drops below 10, bond tier drops by 1.

---

## The recruitment ladder

Loyal Operatives (tier 5) are rare and permanent — if they survive. A run with 2–3 Loyal Operatives feels entirely different from a solo run. Operatives can:

- Run parallel objectives while the player is elsewhere
- Carry intelligence between regions
- Take heat in the player's place (absorbing a Heat tier for one action)
- Die for the cause — permanent loss, but compounding mass effect on the roster (other NPCs radicalize faster on news of an operative's death)

---

## See also
- [NPCs](npcs.md) — the character sheet
- [Heat & Evasion](../04-player/heat.md) — how operatives absorb heat
- [Cultural Cameos](cultural-cameos.md) — cameos can *occupy* the operative slot for the length of their arc
