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

---

## Romance — polyamorous, personality-consequenced

> **Status:** Implemented. Relationship tier 4 (Romantic) is now an active mechanic. Commit via HUD dialogue modal at trust ≥ 60.

The player can court and commit to any number of NPCs. Polyamory is legal; consequences are per-partner and driven entirely by each partner's personality.

### Committing

In the dialogue modal, a **COMMIT** button appears once the NPC's `trust ≥ 60`. Pressing it:
- Sets `NPCData.relationship_type = 4` (Romantic)
- Adds `npc_id` to `PlayerManager.romantic_partner_ids`
- Grants the player +10 hope immediately
- If other partners exist, the dialogue log warns: *"You carry N other names. Sooner or later, someone compares notes."*

Romantic partners get slight ×0.75 protection on accident + murder rolls — you look out for them.

### Infidelity discovery

`PopulationDirector.evaluate_infidelity_discoveries` runs daily when the player has ≥2 partners. For each partner not-yet-aware, roll a chance:

```
chance = 0.03 + 0.05 × partner.conformity
              + 0.02 × (other_partner_count - 1)
```

Conformist partners find out sooner. More partners = faster compounding reveal. Discovery sets `NPCData.infidelity_known = true`; each partner reacts once, set by **their** traits:

| Trait gate | Reaction | Effects |
|---|---|---|
| `empathy > 0.6` | Understands, stays together | Trust −5, -2 hope. "She understands. Her hand stays on yours a half-beat longer." |
| `aggression > 0.6` | Confronts, calls patrol | Trust −40, opinion −0.5, +20 heat, relationship ends, −10 hope |
| `conformity > 0.6` AND `empathy < 0.4` | Public denunciation (scandal) | Trust −30, relationship ends, −15 hope, NetFeed scandal |
| `greed > 0.6` | Hush-money demand (500 cr) | If paid: trust −10, -4 hope. If can't afford: full scandal treatment. |
| `idealism > 0.6` | Quiet idealistic breakup | Trust −25, relationship drops to Friend, −12 hope, THEIR hope drops too |
| (default) | Quiet fallout, they stop calling | Trust −20, relationship drops to Friend, −8 hope |

Each partner's reaction is a dedicated NetFeed line voiced to personality. Players see exactly how each betrayal shapes.

### Hope on partner death

Scales **inversely** with partner count — more partners = less per-death cost. Thematic: "obviously if player has more, it means the relationships are less critical to the player's hope."

| Partners | Hope hit on loss |
|---|---|
| 1 | −40 (catastrophic) |
| 2 | −20 |
| 3 | −13 |
| 4+ | −10 (floor) |

A monogamous player can spiral into DESPAIR from a single partner's death. A polyamorous player absorbs it.

### Tradeoffs, summary

| Polyamorous strategy | Cost |
|---|---|
| Less emotional risk per lover | More discovery surface — more partners, faster + more cascading reveals |
| Each reveal is permanent per partner | Each successful relationship can still end in trait-specific ways that hurt |
| Forgiving partners (high empathy) are safe | But they still take small costs on each reveal |

---

## See also
- [NPCs](npcs.md) — character sheets + NPC death + social graph
- [Heat & Evasion](../04-player/heat.md) — how operatives absorb heat
- [Cultural Cameos](cultural-cameos.md) — cameos can *occupy* the operative slot for the length of their arc
- [Progression](../04-player/progression.md) — hope-cost math interacting with romance
