# Core Loop

> Observe → Plan → Act → Adapt. Repeat until the Enclave falls or you're dust.

---

## Second-by-second: what the player actually experiences

A full day is **10 real minutes**, split into three phases of ~3:20 each. A full playthrough is **13 months** (390 days = ~65 real hours at 1×, ~11h at 6× fast-forward, ~2.7h at 24× super-fast). Below is a concrete walkthrough of what you see and can do at each point of a typical first hour. Bolded timings are **real** time since pressing Play; bracketed times are the **in-game clock** shown in the HUD.

### 🎬 Boot — 0:00 [Month 1 / Day 1 / 06:00, Morning]

- Scene fades in. You're standing in a procedurally-generated region (let's say **Ash Row**, an `URBAN_SLUM` — yours will differ each playthrough unless you [loaded a config](../05-systems/save-and-share.md)).
- **GOAL-CHOICE MODAL** pops up immediately: *"// 13 MONTHS — One goal. Pick it, or let the year decide."* Five options — `DIRECT ACTION`, `POLITICAL REVOLUTION`, `POLITICAL REFORM`, `SYSTEMIC COLLAPSE`, or `LET THE YEAR DECIDE`. Stored in `PlayerManager.chosen_victory_path`. Pick one. World keeps generating in the background.
- Fog is brown and thick. Rust-orange stacks of shipping containers and brutalist concrete blocks rise around you. The sun sits low in the east.
- **HUD top-left (WORLD STATE):** `food_price 100`, `tech_price 500`, `security 50`, `tension 20`, `senate_alignment 50`, **`month 1 of 13`, `day 1`, `06:00`, `morning`**, progress bar `░░░░░░░░░░░░ 13 months left`, `credits -200` (Blue Collar starts behind on rent), `heat 0`, `hope ▓▓▓▓░░░░░░ 45`.
- **HUD top-right (NETFEED):** *"> broadcast channel open. awaiting signal..."*
- **HUD middle-right (SENATE DOCKET):** *"Senate idle. Chamber awaits first cycle."*
- Player capsule (rust-orange) visible at map center. Isometric camera locked on them. Behind the scenes, 4–6 oligarchs, 11 politicians, 40 NPCs, 0–1 active cameos, 2 enforcer patrols have been generated.
- **You're in the severance period.** Months 1–2, hope decay is paused. Rent still drains (30 cr/day baseline), but the psychological weight hasn't found you yet. 60 game days to orient.

### 🚶 Orient — 0:00 → 0:30 [06:00 → ~07:30]

- **Left-click the ground** → player walks there via navmesh.
- You see the two interactables:
  - A **glowing yellow crate** ~15m away — the Food Depot.
  - A **cyan monolith** on the opposite side — the Datashard Terminal.
- You can approach and read each:
  - Near the crate → prompt: *"[E] Sabotage Ash Row Food Depot"*
  - Near the terminal → *"[E] Leak scandal via black-market terminal"*
- Sun climbs visibly. Shadows shorten.

### 💥 First action (optional) — ~0:30 [~07:30]

You can act now or save it for later. Typical first moves:

**Option A — Sabotage the depot** (press E near the crate):
- Crate dims, material goes dark brown.
- Console: `Ripple: Food sector sabotaged. Prices spike, tension rises.`
- **HUD updates immediately:** `food_price +200 → 300`, `public_tension +15 → 35`, `security_presence +10 → 60`, `credits +~450` (random 300–600), `heat +3`.
- NetFeed ticker flashes: *"Overnight raid on Ash Row food depot — Enforcers sweep neighboring blocks."*
- Depot won't respond again this run — it's spent.

**Option B — Open the terminal** (press E near the monolith):
- Scene pauses. Terminal menu modal opens with four options: `LEAK SCANDAL TO NETFEED`, `SELL SCANDAL TO MEDIA`, `LOBBY A POLITICIAN`, `CANCEL`.
- Picking **LEAK** → oligarch list modal. Click an oligarch → their `public_image` tanks, `controversy_level` rises, NetFeed headline fires. Free, `heat 0`, pushes you toward the populist arc.
- Picking **SELL** → same list, but this time the **Media oligarch** (if alive) buys the dirt. You pocket ~1500 credits; the scandal is *suppressed* instead of public; `senate_alignment +5` (corporate drift); `heat +2`. The corrupt option.
- Picking **LOBBY** → Senate roster modal. But: no bill is in debate yet on Day 1, so the modal notes *"Bribes now will apply to the NEXT bill the Senate proposes."* You can pre-pay a flip.
- Pressing `Esc` closes the modal and resumes.

**Option C — Do nothing.** You wander, read the HUD. The world moves on its own.

### 📡 3:20 [14:00, Afternoon] — First phase boundary

At exactly 200 real seconds, the phase changes Morning → Afternoon. Three things happen in the same frame:

1. **NetFeed refresh (the first daily broadcast).** Based on current world state, 1–3 headlines fire into the NetFeed ticker at the top-right. If you sabotaged earlier, coverage is there. If you didn't, generic ambient ("NetFeed quiet overnight.").
2. **Job board roll.** With ~65% probability a rival oligarch posts a contract; with ~45% probability a trusted fixer NPC posts a job. Each shows up as a NetFeed headline — *"Bounty circulating in the black market — X wants Y's infrastructure damaged"* or *"Fixer signal in the Sinks — Z wants the Food sector disrupted."*
3. **HUD clock updates** to `14:00 / afternoon`. Sun is at its peak; shadows are short.

Press **J** to open the JOB BOARD panel (right side, under the Senate docket) — each active job shows badge (red CONTRACT / cyan FIXER), bounty, cycles remaining, source, framing, target action.

### ☀️ Afternoon — 3:20 → 6:40 [14:00 → 22:00]

- You explore the map. A 150×150m slum has a lot to walk through. Click-to-move is the only traversal.
- You press **P** → SENATE ROSTER panel opens on the left. All 11 senators shown with name, faction (CORP_BLOC hot red, POPULIST accent, REFORM cyan, INDEP dim), `⚠` if scandal-riddled, a 10-tick approval bar, and *"chamber idle — no bill in docket"* since Day 1 hasn't completed yet.
- You press **Space** → `▶▶ 6×` badge appears in the HUD clock row. Time accelerates. The sun sweeps visibly; fog thickens as dusk approaches. Press Space again to return to 1×.
- You press **F5** → Save World modal. Pre-filled name ("Ash Row Standoff 20260419"). Save it; the JSON lands in `user://world_configs/`.

### 🌆 6:40 [22:00] — Second phase boundary (Afternoon → Night)

- **NetFeed refresh #2.** Second daily broadcast. State has shifted from your morning — maybe food is tighter, tension higher.
- **Visual shift begins.** Sun drops below the horizon over the next few seconds. Sky deepens from amber to indigo to near-black. Ambient light cools. Fog density increases by 40%. Barrel fires (orange glowing cylinders scattered around the slum) now visibly dominate the lighting.
- Job-board rolls favor **night-active NPCs** — a Destitute fence who only appears after dark, an Enforcer informant who's off-shift.

### 🌙 Night — 6:40 → 10:00 [22:00 → 06:00 next day]

- Landscape is cool-blue lit. Warm accents (rust-orange sun palette) gone; only emissive props (barrel fires, neon window tints, planters if elite region) remain bright.
- **NPC availability changes.** The fixer you were going to hit up may not be posting tonight. Day-only NPCs are "sleeping" (mechanically: not appearing in the fixer job candidate pool).
- Good phase for sell-scandal plays if that's your play — Media oligarchs do their real work at night thematically.

### 🌅 10:00 [06:00, Day 2, Morning] — First day rollover

This is the moment the world *actually ticks*. All in one frame:

1. **`WorldDirector.run_world_cycle()` fires.** Each living oligarch evaluates the world through their nature traits — paranoia updates, PR campaigns launch if `vanity > 0.5 and public_image < -20`, prices hike if `greed > 0.6`, ambitions pursue (security spending, lobbying, media control, etc.). Each action emits a NetFeed headline and mutates the economy.
2. **Senate ticks.** The first bill of the run resolves now (no, actually: it *proposes* now — Day 1 had no bill to resolve). Via `SenateDirector.begin_cycle()`, a sponsor is picked (weighted by faction pressure + world state) and the LLM (or offline fallback) generates a bill keyed to that sponsor's persona. You see the SENATE DOCKET panel update: *"IN DEBATE — sponsor: Helena Cain (Corporate Bloc Chair); The Public Safety and Sanitation Directive — Authorizes Enforcer units to clear non-compliant structures..."*
3. **NPCs evolve.** All 40 NPCs run `process_world_pressure(tension, food_price, security)`. Stress accumulates, hope decays for the aggressive/conformist, radicalization ticks up for the right archetypes. Those trust values drift.
4. **Heat decays −1.** Your heat reading ticks down.
5. **Expired jobs clear.** Any contract or fixer job posted on Day 1 that wasn't completed expires with a NetFeed note: *"Bounty on Tech sector withdrawn — contracting party has moved on."*
6. **Day counter bumps** to `2`. Clock resets to `06:00`. Phase reset to Morning. The sun returns.
7. **NetFeed refresh #3.** (The morning broadcast of Day 2.)

### 🎯 Day 2 cycle — 10:00 → 20:00 real [Day 2, all three phases]

Now you have a concrete political objective: influence or sabotage today's bill before it resolves.

- **Morning (06:00–14:00)** — walk to the terminal, open LOBBY. Senate roster now shows each senator's **predicted stance** on the bill (→ YES, → NO, → ABSTAIN). Browse. A Corrupt + Scandalous senator might cost only 120 credits; a Conscience type runs 1700+. Bribe a fringe vote.
- **Afternoon (14:00–22:00)** — sabotage a food depot (wait, this one's spent — but any future depot you add would re-trigger). Or hit the terminal to SELL a dossier on an oligarch whose scandal you've been sitting on. NetFeed covers each of these.
- **Night (22:00–06:00)** — pressure's rising, dusk. Maybe a fixer job posts that you can fulfill by repeating an action. Press **J** to see it.
- **Day 3 rollover [06:00]** — bill resolves. SENATE DOCKET flashes `PASS 7–3–1 / margin +4` or `FAIL 4–6–1 / margin -2`. Economy snaps to the proposed_effects. NetFeed covers the result. New bill proposes immediately.

### 🔁 Day 3–60 (months 1–2, Settling band) — The rhythm sets in

- Every 10 real minutes = 1 in-game day = 1 full simulation tick + 1 Senate bill resolution + rent drain + NPC death rolls + social graph tick.
- Every ~3:20 = 1 NetFeed refresh + possible new job posting + cameo trigger evaluation.
- **During severance** (months 1–2), hope doesn't decay. You can roam, talk to all 40 NPCs, build bonds, commit to a lover, investigate oligarch patterns — without the despair clock running.
- Rent still hits daily. Blue Collar at -200 cr goes homeless around day 3 unless they act. Eviction is a state, not a run-ender — but it adds heat/food cost.
- Oligarchs act, Senate tables a bill each day, NPCs drift, NPCs interact with each other, occasional NPC dies, job board posts contracts from resistance cells + fixer NPCs, cameo-whispers fire.
- A [cultural cameo](../03-characters/cultural-cameos.md) may trigger if your playstyle matches its gate. The Soap Man doesn't come for the careful; the Kindly Stranger doesn't come for the ruthless.

### 📰 Month 3 dawn [day 61] — Severance ends

NetFeed fires a one-shot headline: *"Your severance ran out this morning. The weight finds you now. Hope starts to drift."* From here, baseline hope decay is −1/day, more if broke / homeless / hot. The grace period is over. Every day of inaction now costs.

### 💀 Month 6–13 — Escalation to victory (or timeout)

Six victory/defeat paths live concurrently. Only the **chosen** one (from the goal-choice modal) triggers a win; others fire a NetFeed note and the run continues.

**Victory paths:**
1. **DIRECT ACTION** — all oligarchs eliminated.
2. **POLITICAL REVOLUTION** — `public_tension == 100`.
3. **POLITICAL REFORM** — `senate_alignment == 0`.
4. **SYSTEMIC COLLAPSE** — combined oligarch wealth < 100k credits.

**Defeat paths:**
5. **ARRESTED** — `heat == 100`.
6. **SURRENDERED** — SUBMIT on an Enforcer encounter.
7. **DESPAIR_WITHDRAWAL** — `hope == 0`.
8. **TIMEOUT_ABSORBED** — month 14 reached, no victory path fired.

**Month 13 softens thresholds by 10** (tension wins at 90 instead of 100, senate wins at 10, wealth wins at 150k). The world bends toward resolution — if you're close, the final month gives you the break.

When end-of-run fires, **everything pauses**. The modal shows kind, title, flavor, and five buttons: **SAVE WORLD**, **LOAD WORLD…**, **VIEW CHRONICLE**, **RESTART**, **CONTINUE (sandbox)**. Clicking VIEW CHRONICLE opens a scrollable log — 13 monthly recaps laid out as narrative text. Exportable to clipboard via COPY TO CLIPBOARD. Your run becomes a shareable story.

A typical first playthrough resolves in months 6–12 — 60–120 minutes at 6× fast-forward, 2.5–5 hours at 1×. Super-fast (Shift+Space, 24×) compresses quiet stretches to ~25s per day.

---

## The loop (abstract)

### 1. Observe
- **Read the NetFeed.** See what the world noticed.
- **Check the Oligarch summaries.** Who's paranoid, who's bleeding, who's ascending.
- **Talk to NPCs** *(future — currently surfaced via fixer jobs and the roster)*.
- **Check the Senate docket** (right-side panel). Who's sponsoring what, what it does.
- **Check the Job Board** (press J). Who's paying you for what.

### 2. Plan
- Identify targets, vulnerabilities, allies.
- Choose an approach: **stealth, persuasion, sabotage, violence**. Mix.
- If the map is ripe, a [cameo](../03-characters/cultural-cameos.md) may be offering something unusual. Decide whether to engage.

### 3. Act
- Execute. Every action fires the [Butterfly Effect](../02-world/butterfly-effect.md).
- Loud actions spike [Heat](progression.md#heat-system). Silent actions don't — but the world may still move in response ([silent ripples](../02-world/netfeed.md)).

### 4. Adapt
- The world has changed. New opportunities. New threats.
- Allies may have radicalized, broken, died, or been arrested.
- Oligarchs may have shifted ambition or funded a militia.
- A cameo may have escalated mid-arc.

Back to Observe.

---

## Key reference

| Key | Action |
|---|---|
| **Left-click** | Click-to-move to ground position |
| **E** | Interact (near depot / terminal / crowd NPC / transit pillar) |
| **Space** | Toggle fast-forward (6×) |
| **Shift+Space** | Toggle super fast-forward (24×) — for long runs |
| **P** | Toggle Senate roster panel |
| **J** | Toggle Job Board panel (jobs + active cameo arcs) |
| **F5** | Open Save World modal |
| **F9** | Open Load World modal |
| **Esc** | Close current modal (some modals absorb — cameos, encounters, goal-choice) |

---

## A run-length perspective

A playthrough runs **13 months / 390 days**. At 6× fast-forward that's ~11 real hours; at 24× super-fast ~2.7 real hours. Most runs resolve before month 13 or never — the year's end defeats anyone still fumbling.

| Month band | Feel |
|---|---|
| 1–2 **Settling** | Severance period. Hope decay paused. Orient, talk, build bonds, pick a path. |
| 3–5 **Pressure** | Hope decay kicks in. Cameos at baseline. Commit to action or start losing. |
| 6–9 **Escalation** | +1 tension/day passive drift. Cameo probability ×1.25. Patrols thicker. |
| 10–12 **Climactic** | Heat cools half-speed. +2 tension/day. Cameo probability ×1.4. The Enclave's reaction hardens. |
| 13 **Year's End** | Victory thresholds soften by 10 — the world bends toward resolution. Cameo ×1.6. +3 tension/day. |
| Month 14 | **TIMEOUT_ABSORBED.** You did not act decisively. The year absorbed you. |

---

## Idle is not stopped

If the player "does nothing" for a day:
- Oligarchs still act on cycle rollover
- The NetFeed still generates 3× per day
- NPC radicalization still moves
- Cameos still roll their triggers
- The economy still drifts
- Jobs expire; new ones post

There is no safe middle. The game penalizes caution as much as recklessness, just differently. This is on purpose — see [pillar 5](../01-vision/pillars.md#5-the-world-does-not-wait).

---

## See also

- [Time, Day/Night, and Fast-Forward](../05-systems/time-and-day-night.md) — the temporal system this walkthrough moves through
- [Progression, Credits & Heat](progression.md) — the economy driving every action cost
- [The Senate](../02-world/senate.md) — the once-per-day bill rhythm
- [Victory](victory.md) — what "winning" means (and costs)
