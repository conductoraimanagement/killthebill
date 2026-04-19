extends Node
class_name PopulationDirector

# =============================================================
# PopulationDirector: The Persistent NPC Roster Manager
# =============================================================
# At the START of each playthrough, this generates a fixed roster
# of NPCs with randomized intrinsic personality traits.
# These NPCs persist for the ENTIRE run and evolve based on
# world pressure filtered through their unique personalities.
# No NPC is spawned or despawned mid-game.
# =============================================================

signal population_generated()
signal npc_died(npc, cause: String)

const MAX_NPCS: int = 40 # Total persistent population cap

# The master roster — lives for the entire playthrough
var roster: Array[NPCData] = []

func _ready():
	pass

# =============================================================
# ROSTER GENERATION — Called once at the start of a new playthrough
# =============================================================

func generate_new_roster() -> void:
	roster.clear()
	
	if has_node("/root/LLMManager"):
		var llm = get_node("/root/LLMManager")
		if not llm.npc_roster_generated.is_connected(_on_npc_roster_generated):
			llm.npc_roster_generated.connect(_on_npc_roster_generated)
		
		# Generate in two batches of 20 to avoid token limits
		print("PopulationDirector: Requesting batch 1 of procedural NPCs...")
		llm.request_npc_roster_generation(MAX_NPCS / 2)
	else:
		push_error("LLMManager missing! Falling back to empty population.")

func _on_npc_roster_generated(data: Array) -> void:
	print("PopulationDirector: Received %d NPCs from LLM." % data.size())
	
	for n_data in data:
		var npc = NPCData.new()
		npc.npc_id = "npc_" + str(roster.size())
		npc.npc_name = n_data.get("first_name", "Unknown") + " " + n_data.get("last_name", "Citizen")
		npc.quirks = Array(n_data.get("quirks", []), TYPE_STRING, &"", null)
		
		# Assign social class with weighted distribution
		var class_roll = randf()
		if class_roll < 0.15:
			npc.social_class = 1 # Enforcer
		elif class_roll < 0.55:
			npc.social_class = 2 # Worker
		else:
			npc.social_class = 3 # Destitute
		
		# Intrinsic traits
		npc.resilience = randf()
		npc.aggression = randf()
		npc.empathy = randf()
		npc.idealism = randf()
		npc.greed = randf()
		npc.conformity = randf()
		
		# Starting state
		match npc.social_class:
			1:
				npc.personal_wealth = randi_range(150, 400)
				npc.immediate_need = "Security"
			2:
				npc.personal_wealth = randi_range(30, 120)
				npc.immediate_need = "Rations"
			3:
				npc.personal_wealth = randi_range(0, 30)
				npc.immediate_need = "Survival"

		# Seed NPC trust so some citizens are pre-disposed to post fixer jobs.
		# About 35% of NPCs start with trust ≥ 30 — the threshold for posting.
		# Workers and the Destitute trust the player easier than Enforcers.
		var trust_bias: float = 15.0 if npc.social_class == 1 else 30.0
		npc.trust = clamp(randf_range(0.0, 60.0) + trust_bias - 15.0, 0.0, 60.0)

		# Active phase: 70% both, 15% day-only, 15% night-only.
		# Enforcers skew night-biased (patrols); the Destitute skew day.
		var phase_roll: float = randf()
		match npc.social_class:
			1:  # Enforcer
				npc.active_phase = "night" if phase_roll < 0.35 else ("day" if phase_roll < 0.50 else "both")
			3:  # Destitute
				npc.active_phase = "day" if phase_roll < 0.30 else ("night" if phase_roll < 0.40 else "both")
			_:
				npc.active_phase = "both" if phase_roll < 0.70 else ("day" if phase_roll < 0.85 else "night")

		roster.append(npc)

	if roster.size() < MAX_NPCS:
		print("PopulationDirector: Requesting batch 2 of procedural NPCs...")
		get_node("/root/LLMManager").request_npc_roster_generation(MAX_NPCS - roster.size())
	else:
		print("PopulationDirector: Full population generated (%d persistent NPCs)." % roster.size())
		population_generated.emit()

# =============================================================
# WORLD CYCLE — Called by WorldDirector each tick to evolve ALL NPCs
# =============================================================

func evolve_all_npcs(eco: Dictionary) -> void:
	var tension = eco.get("public_tension", 50)
	var food_price = eco.get("food_price", 100)
	var security = eco.get("security_presence", 50)

	for npc in roster:
		if not npc.alive:
			continue
		npc.process_world_pressure(tension, food_price, security)


# Called by WorldDirector each day cycle. Random accident + murder
# rolls for every alive NPC, weighted by world state + character
# state. Romantic partners are slightly safer early, noticeably
# MORE at risk in the endgame — the collapse takes what you love.
func evaluate_deaths(economy: Dictionary, cycle: int) -> void:
	var tension: int = int(economy.get("public_tension", 50))
	var food_price: int = int(economy.get("food_price", 100))
	var security: int = int(economy.get("security_presence", 50))

	var pm := get_node_or_null("/root/PlayerManager")
	var player_heat: int = int(pm.heat) if pm else 0
	var wd := get_node_or_null("/root/WorldDirector")

	for npc in roster:
		if not npc.alive:
			continue

		# Base risks.
		var accident_chance: float = 0.002
		var murder_chance: float  = 0.002

		# Accident scaling
		if food_price > 250:
			accident_chance += 0.002     # food poisoning, starvation
		if npc.stress_level > 70.0:
			accident_chance += 0.002     # health collapse under pressure
		if int(npc.social_class) == 3 and food_price > 200:
			accident_chance += 0.002     # Destitute most vulnerable

		# Murder scaling
		if npc.radicalization > 70.0 and security > 60:
			murder_chance += 0.004        # silenced as agitator
		if npc.knowledge_of_player > 0.6 and player_heat > 70:
			murder_chance += 0.003        # they saw too much
		murder_chance += float(tension) / 100.0 * 0.002  # ambient violence

		# Romantic partners are slightly safer — you look out for them,
		# check in, know where they sleep. The world isn't actively
		# targeting them.
		var is_lover: bool = pm and pm.is_romantic_partner(npc.npc_id)
		if is_lover:
			accident_chance *= 0.75
			murder_chance *= 0.75

		# Roll
		var cause: String = ""
		if randf() < accident_chance:
			cause = "accident"
		elif randf() < murder_chance:
			cause = "murder"

		if cause != "":
			_kill_npc(npc, cause, cycle, wd, pm)


func _kill_npc(npc, cause: String, cycle: int, wd, pm) -> void:
	npc.alive = false
	npc.death_cause = cause
	npc.died_on_cycle = cycle

	# Hope hit scales with how much this person mattered. Romantic
	# partner's death hurts inversely proportional to partner count —
	# a monogamous player loses a lot more than a polyamorous one.
	# "Obviously if player has more, it means the relationships are
	# less critical to the player's hope."
	var hope_hit: float = -2.0
	var is_lover: bool = pm and pm.is_romantic_partner(npc.npc_id)
	var is_ally: bool = npc.trust >= 30.0
	if is_lover:
		var n_partners: int = pm.romantic_partner_ids.size() if pm else 1
		if n_partners <= 1:
			hope_hit = -40.0
		else:
			# Divide evenly, floor at -10 — even one of many still matters.
			hope_hit = max(-40.0 / float(n_partners), -10.0)
			if n_partners >= 4:
				hope_hit = max(hope_hit, -10.0)
	elif is_ally:
		hope_hit = -10.0
	if pm:
		pm.add_hope(hope_hit, "death of %s" % npc.npc_name)
		if is_lover:
			pm.remove_romantic_partner(npc.npc_id)

	# NetFeed headline.
	if wd:
		var headline: String = _headline_for_death(npc, cause, is_lover, is_ally)
		var event := {
			"type": "NEWS_TICKER",
			"headline": headline,
			"timestamp": Time.get_unix_time_from_system(),
		}
		wd.netfeed_history.append(event)
		wd.netfeed_event_generated.emit(event)

	npc_died.emit(npc, cause)
	print("NPC died: %s (%s)" % [npc.npc_name, cause])


func _headline_for_death(npc, cause: String, is_lover: bool, is_ally: bool) -> String:
	if is_lover:
		return "The name you whispered last week is in this morning's death notices. The system did not pause for %s." % npc.npc_name
	if is_ally:
		return "%s died overnight. They were one of yours. The rally lost its voice." % npc.npc_name
	if cause == "accident":
		var accident_kinds: Array[String] = [
			"A fire on the sixth floor took %s overnight. Two others displaced.",
			"%s collapsed at a checkpoint queue. By the time anyone noticed, they were already gone.",
			"Suspected food poisoning. %s was found in their one-room on Tuesday.",
			"%s didn't come home from the factory. No statement from the industrial office.",
		]
		return accident_kinds[randi() % accident_kinds.size()] % npc.npc_name
	# murder
	var murder_kinds: Array[String] = [
		"%s was found dead in a stairwell. Compliance AI flagged the incident as 'resolved'.",
		"A body in a Sinks alley, later identified as %s. No suspects named.",
		"%s did not show up to the bread line this morning. By evening the rumor was confirmed.",
		"A neighbor reported 'shouting, then quiet.' The next morning, %s was in the notices.",
	]
	return murder_kinds[randi() % murder_kinds.size()] % npc.npc_name

# =============================================================
# QUERIES — Let other systems ask about the population
# =============================================================

func get_npc_by_id(id: String) -> NPCData:
	for npc in roster:
		if npc.npc_id == id:
			return npc
	return null

func get_radicals() -> Array[NPCData]:
	var result: Array[NPCData] = []
	for npc in roster:
		if npc.get_behavioral_profile() == "Radical Agitator":
			result.append(npc)
	return result

func get_broken() -> Array[NPCData]:
	var result: Array[NPCData] = []
	for npc in roster:
		if npc.get_behavioral_profile() == "Broken and Submissive":
			result.append(npc)
	return result

func get_population_summary() -> Dictionary:
	var summary = {}
	for npc in roster:
		var profile = npc.get_behavioral_profile()
		summary[profile] = summary.get(profile, 0) + 1
	return summary
