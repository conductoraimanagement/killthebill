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
		npc.process_world_pressure(tension, food_price, security)

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
