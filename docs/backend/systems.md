# Backend Systems: WorldDirector & Economy

## The WorldDirector
The `WorldDirector` is the central brain of the game's systemic logic. It operates independently of the visual scene, meaning it can simulate the economy even for sectors the player is not currently in.

### Responsibilities
1. **Oligarch State Management:** Tracks the wealth, power level, and current paranoia state of the 4 key Oligarchs (Tech, Food, Security, Media).
2. **Global Economy Variables:**
   - `food_price`: Base cost of rations.
   - `tech_price`: Cost of hacking tools and augments.
   - `security_level`: Frequency of patrols and response time of Enforcers.
   - `public_tension`: Ranges from 0 (Docile) to 100 (Active Riot).
   - `senate_alignment`: Political control ranging from 0 (Fully Pro-Sinks/Reformist) to 100 (Fully Pro-Enclave/Corporate).
3. **The Event Bus:** Listens for signals emitted by the player or world events (e.g., `SignalBus.emit_signal("facility_sabotaged", "Food")`, or `exert_political_pressure`).

## LLM Integration Architecture
NPC dialogue is generated dynamically based on backend state. 

### Flow:
1. Player interacts with NPC.
2. `NPCController` gathers local data (SocialClass, CurrentMood, OpinionOfPlayer).
3. `NPCController` requests global context from `WorldDirector` (e.g., "Food is expensive, public tension is high").
4. Backend formats this data into a JSON payload.
5. Payload is sent to the LLM API (e.g., OpenAI, local LLM).
6. LLM returns a generated response string.
7. Response is passed to the UI dialogue system.
