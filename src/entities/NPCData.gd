extends Resource
class_name NPCData

# =============================================================
# NPCData: The Persistent Character Sheet
# =============================================================
# NPCs are NOT disposable. A fixed roster is created at game start
# and persists for the entire playthrough. Each NPC has:
#   - INTRINSIC TRAITS (Nature): Immutable personality. Set once at creation.
#   - DYNAMIC STATE (Nurture): Evolves continuously based on world events
#     filtered through the intrinsic traits.
# Two NPCs facing the same crisis will react differently based on
# their intrinsic makeup.
# =============================================================

@export var npc_name: String = "Unknown Citizen"
@export var npc_id: String = "" # Unique persistent identifier
@export_enum("Oligarch", "Enforcer", "Worker", "Destitute") var social_class: int = 2

# =============================================================
# INTRINSIC TRAITS (Nature) — SET ONCE, NEVER CHANGE
# =============================================================
# These define WHO the character fundamentally IS.
# They act as filters/multipliers on how world events affect dynamic state.

@export_group("Intrinsic Personality")
@export_range(0.0, 1.0) var resilience: float = 0.5
## How much they can endure before breaking. High = stoic, low = fragile.

@export_range(0.0, 1.0) var aggression: float = 0.3
## Tendency toward violence when pressured. High = radicalizes, low = withdraws.

@export_range(0.0, 1.0) var empathy: float = 0.5
## How much others' suffering affects them. High = altruistic, low = self-serving.

@export_range(0.0, 1.0) var idealism: float = 0.3
## Belief that things can change. High = revolutionary, low = cynical/resigned.

@export_range(0.0, 1.0) var greed: float = 0.2
## Willingness to exploit others for personal gain.

@export_range(0.0, 1.0) var conformity: float = 0.5
## How much they follow the crowd vs think independently.
## (Replaces the old social_cohesion — but this one is immutable nature)

# =============================================================
# QUIRKS — Random human details that make NPCs feel real
# =============================================================
# Assigned at roster generation. These are NOT mechanical variables,
# they are narrative flavoring injected into the LLM prompt so the
# AI voices each NPC as a distinct human being.

@export_group("Quirks")
@export var quirks: Array[String] = []
## Examples: "Stutters when nervous", "Always chewing something",
## "Quotes old pre-collapse poetry", "Has a limp from an Enforcer beating",
## "Talks to a dead sibling as if they're still alive"

# =============================================================
# DYNAMIC STATE (Nurture) — EVOLVES EVERY CYCLE
# =============================================================
# These change over time based on world events filtered through
# intrinsic traits. The SAME food crisis makes a high-aggression
# NPC radicalize and a high-conformity NPC submit.

@export_group("Dynamic State")
@export var current_mood: String = "Anxious"
@export var stress_level: float = 30.0 # 0-100: Accumulated psychological pressure
@export var hope: float = 50.0 # 0-100: Belief in a future. Drops = despair or rage
@export var radicalization: float = 0.0 # 0-100: How far they've gone toward extremism

# Player Relationship
@export var knowledge_of_player: float = 0.0 # 0.0 (Ignorant) to 1.0 (Hunting)
@export var opinion_of_player: float = 0.0 # -1.0 (Hates) to 1.0 (Loves)

# =============================================================
# RELATIONSHIP & AGENT SYSTEM
# =============================================================
# The player can form deep bonds with NPCs. Bonded NPCs become
# "agents" the player can assign objectives to. The NPC's intrinsic
# traits + relationship type determine HOW they execute (or refuse).

@export_group("Relationship")
@export_enum("None", "Acquaintance", "Friend", "Close Friend", "Romantic", "Loyal Operative") var relationship_type: int = 0

@export var trust: float = 0.0 # 0-100: Built through interactions, decays through betrayal
@export var bond_history: Array[String] = [] # "Shared rations", "Saved from Enforcers", "Betrayed their location"

## Whether this NPC is currently assigned as a player agent
@export var is_agent: bool = false
@export var current_objective: String = "" # e.g., "Distract guards at Depot 7", "Smuggle intel to sector B"
@export var objective_willingness: float = 0.0 # 0-1: How willing they are to do what's asked

## Returns true if the NPC can be recruited as an agent
func can_recruit() -> bool:
	# Must have at least Friend-level bond and sufficient trust
	return relationship_type >= 2 and trust >= 30.0

## Attempt to assign an objective. Returns success/failure reason.
func assign_objective(objective: String, risk_level: float) -> Dictionary:
	if not can_recruit():
		return {"success": false, "reason": "Not enough trust or bond to ask this."}
	
	# Willingness is a function of trust, relationship depth, and personality
	var base_willingness = trust / 100.0
	
	# Romantic partners and loyal operatives are more willing
	if relationship_type == 4: # Romantic
		base_willingness += 0.2
	elif relationship_type == 5: # Loyal Operative
		base_willingness += 0.3
	
	# Personality modifiers on willingness
	base_willingness += empathy * 0.1 # Empathetic NPCs want to help
	base_willingness -= greed * 0.1 # Greedy NPCs want payment
	base_willingness += idealism * 0.1 # Idealists believe in the cause
	
	# High risk reduces willingness (but brave/aggressive NPCs care less)
	var risk_penalty = risk_level * (1.0 - aggression * 0.5)
	base_willingness -= risk_penalty * 0.3
	
	objective_willingness = clamp(base_willingness, 0.0, 1.0)
	
	# Roll against willingness
	if randf() < objective_willingness:
		is_agent = true
		current_objective = objective
		bond_history.append("Accepted: " + objective)
		return {"success": true, "reason": "I'll do it.", "willingness": objective_willingness}
	else:
		# Refusal — personality determines the tone
		var refusal = "I can't do that."
		if aggression > 0.6:
			refusal = "Don't push me. I said no."
		elif empathy > 0.6:
			refusal = "I want to help, but this is too much."
		elif greed > 0.6:
			refusal = "What's in it for me?"
		bond_history.append("Refused: " + objective)
		trust -= 5.0 # Pushing too hard erodes trust slightly
		trust = max(0.0, trust)
		return {"success": false, "reason": refusal, "willingness": objective_willingness}

## Called when an objective is completed or failed
func resolve_objective(success: bool) -> void:
	if success:
		trust = min(100.0, trust + 15.0)
		bond_history.append("Completed: " + current_objective)
		memories.append("Successfully completed a mission for the player.")
	else:
		trust -= 20.0
		stress_level += 15.0
		bond_history.append("Failed: " + current_objective)
		memories.append("Failed a dangerous mission. The player put me at risk.")
		# Failed missions can damage the relationship
		if trust < 10.0 and relationship_type > 1:
			relationship_type -= 1 # Bond degrades
	
	is_agent = false
	current_objective = ""

# Economic Context
@export_group("Economic")
@export var personal_wealth: int = 50
@export var immediate_need: String = "Stability"

# Long-term Memory
@export var memories: Array[String] = []

# =============================================================
# DERIVED BEHAVIOR (Nature + Nurture = Behavior)
# =============================================================

## Returns how this specific NPC reacts to current stress.
## This is the core "personality filter" that makes each NPC unique.
func get_behavioral_profile() -> String:
	# High stress + high aggression + low conformity = Kaczynski type
	if stress_level > 70 and aggression > 0.7 and conformity < 0.3:
		return "Radical Agitator"
	
	# High stress + low resilience + high conformity = Broken/Submissive
	if stress_level > 60 and resilience < 0.3 and conformity > 0.6:
		return "Broken and Submissive"
	
	# High idealism + high empathy + moderate stress = Revolutionary Leader
	if idealism > 0.7 and empathy > 0.6 and stress_level > 40:
		return "Revolutionary Idealist"
	
	# High greed + low empathy = Opportunistic Exploiter (thrives in chaos)
	if greed > 0.7 and empathy < 0.3:
		return "Opportunistic Exploiter"
	
	# Low stress or high resilience = Still holding together
	if stress_level < 30 or resilience > 0.7:
		return "Cautiously Stable"
	
	# Default: anxious but functional
	return "Anxious Citizen"

## Called by WorldDirector each cycle to evolve this NPC.
## The SAME world event produces DIFFERENT results per NPC.
func process_world_pressure(tension: float, food_price: float, security: float) -> void:
	# --- Stress accumulation (filtered by resilience) ---
	var pressure = 0.0
	if food_price > 120:
		pressure += (food_price - 120) * 0.1
	if tension > 50:
		pressure += (tension - 50) * 0.05
	if security > 70:
		pressure += (security - 70) * 0.03 # Oppression adds stress
	
	# Resilient NPCs absorb more pressure before it becomes stress
	stress_level += pressure * (1.0 - resilience * 0.7)
	stress_level = clamp(stress_level, 0.0, 100.0)
	
	# --- Hope decay (filtered by idealism) ---
	if food_price > 150 and security > 60:
		# Idealists lose hope slower — they believe change is possible
		hope -= 2.0 * (1.0 - idealism * 0.6)
	elif tension < 30 and food_price < 100:
		# Good times restore hope, especially for idealists
		hope += 1.0 + idealism * 2.0
	hope = clamp(hope, 0.0, 100.0)
	
	# --- Radicalization (filtered by aggression vs conformity) ---
	if stress_level > 50 and hope < 30:
		# When stressed and hopeless, aggression drives toward extremism
		# Conformity acts as a brake — conformists don't radicalize easily
		var radical_push = aggression * 3.0 - conformity * 2.0
		radicalization += max(0.0, radical_push)
	elif hope > 60:
		# Hope slowly de-radicalizes
		radicalization -= 1.0
	radicalization = clamp(radicalization, 0.0, 100.0)
	
	# --- Update mood based on derived profile ---
	current_mood = get_behavioral_profile()

func get_llm_context_string() -> String:
	var context = "You are %s, a %s class citizen. " % [npc_name, _get_class_string()]
	context += "Your current behavioral profile is: %s. " % get_behavioral_profile()
	context += "Stress: %.0f/100. Hope: %.0f/100. Radicalization: %.0f/100. " % [stress_level, hope, radicalization]
	context += "Your immediate need is %s. " % immediate_need
	
	# Relationship context — critical for how the LLM voices this NPC toward the player
	var rel_names = ["a stranger", "an acquaintance", "a friend", "a close friend", "your romantic partner", "your loyal operative"]
	if relationship_type > 0:
		context += "The player is %s to you. Trust: %.0f/100. " % [rel_names[relationship_type], trust]
	if is_agent and current_objective != "":
		context += "You are currently on a mission for the player: '%s'. " % current_objective
	
	# Inject personality so the LLM knows HOW to voice this character
	context += "Personality: "
	if aggression > 0.6: context += "aggressive, "
	elif aggression < 0.3: context += "passive, "
	if empathy > 0.6: context += "empathetic, "
	elif empathy < 0.3: context += "cold, "
	if idealism > 0.6: context += "idealistic, "
	elif idealism < 0.3: context += "cynical, "
	if conformity > 0.6: context += "conformist, "
	elif conformity < 0.3: context += "independent, "
	if resilience > 0.6: context += "tough. "
	elif resilience < 0.3: context += "fragile. "
	else: context += "average resilience. "
	
	# Quirks — the human details that make dialogue feel alive
	if quirks.size() > 0:
		context += "Quirks you MUST embody: "
		context += ", ".join(quirks) + ". "

	if memories.size() > 0:
		context += "Significant memories:\n"
		for memory in memories:
			context += "- %s\n" % memory
			
	return context

func _get_class_string() -> String:
	match social_class:
		0: return "Oligarch"
		1: return "Enforcer"
		2: return "Worker"
		3: return "Destitute"
	return "Unknown"

