extends Resource
class_name OligarchData

# =============================================================
# OligarchData: The Billionaire Character Sheet
# =============================================================
# Each Oligarch is a fully realized character with immutable
# personality traits, randomly assigned ambitions, quirks, and
# behavioral AI that drives their decisions each world cycle.
# Mirrors the NPC Nature/Nurture model but at the power level.
# =============================================================

# Identity
@export var oligarch_id: String = ""
@export var oligarch_name: String = ""
@export var title: String = "" # "CEO", "Chairman", "Director-General"
@export var sector_of_influence: String = "" # "Food", "Tech", "Security", "Media", "Pharma", "Energy"
@export var alive: bool = true

# =============================================================
# INTRINSIC TRAITS (Nature — Immutable, set at generation)
# =============================================================

@export_group("Intrinsic Traits")

@export var ruthlessness: float = 0.5
## 0.0 = Cautious, avoids collateral. 1.0 = Will burn cities to protect their empire.

@export var vanity: float = 0.5
## 0.0 = Doesn't care what people think. 1.0 = Obsessed with public image.

@export var paranoia_base: float = 0.5
## 0.0 = Recklessly confident. 1.0 = Sees threats everywhere.

@export var intelligence: float = 0.5
## 0.0 = Blundering, easy to outmaneuver. 1.0 = Brilliant strategist, adapts fast.

@export var greed: float = 0.5
## 0.0 = Content with current wealth. 1.0 = Insatiable, always expanding.

@export var ideology: float = 0.5
## 0.0 = Pure profit motive, no beliefs. 1.0 = True believer in their cause.

# =============================================================
# AMBITIONS — Randomly assigned goals that drive behavior
# =============================================================

@export_group("Ambitions")
@export var ambitions: Array[String] = []
## Each Oligarch gets 1-2 ambitions from the pool. These determine
## what they actively pursue each cycle.

@export var ambition_progress: Dictionary = {}
## Tracks progress toward each ambition. E.g., {"Monopolize food supply": 0.35}

# =============================================================
# QUIRKS — Human details for LLM dialogue
# =============================================================

@export_group("Quirks")
@export var quirks: Array[String] = []

# =============================================================
# DYNAMIC STATE (Evolves each cycle)
# =============================================================

@export_group("Dynamic State")
@export var wealth: int = 1000000
@export var paranoia: float = 10.0 # 0-100, amplified from paranoia_base by events
@export var public_image: float = 10.0 # -100 to 100
@export var controversy_level: float = 5.0 # 0-100
@export var recent_scandals: Array[String] = []
@export var security_spending: int = 0 # How much they pour into Enforcers
@export var political_influence: float = 50.0 # 0-100, ability to move senate

# Relationship with player
@export var awareness_of_player: float = 0.0 # 0-100: How much they know the player exists
@export var threat_assessment: float = 0.0 # 0-100: How dangerous they consider the player

# =============================================================
# BEHAVIORAL AI — Personality-driven decisions each cycle
# =============================================================

## Evaluate the world and take action based on personality + ambitions
func process_world_state(economy: Dictionary, all_oligarchs: Array) -> Array[Dictionary]:
	var actions_taken: Array[Dictionary] = []
	if not alive:
		return actions_taken
	
	var tension = economy.get("public_tension", 50)
	var food_price = economy.get("food_price", 100)
	var security = economy.get("security_presence", 50)
	
	# --- Paranoia evolution ---
	paranoia = paranoia_base * 30.0 # Base contribution
	if tension > 60:
		paranoia += (tension - 60) * ruthlessness
	if awareness_of_player > 30:
		paranoia += awareness_of_player * 0.5
	paranoia = clamp(paranoia, 0.0, 100.0)
	
	# --- Self-preservation (high paranoia) ---
	if paranoia > 60:
		var spend = int(wealth * 0.05 * ruthlessness)
		security_spending += spend
		wealth -= spend
		actions_taken.append({
			"type": "SECURITY_INCREASE",
			"description": "%s increases private security spending by %d credits." % [oligarch_name, spend],
			"impact": {"security_presence": int(spend / 10000)}
		})
	
	# --- Vanity response (low public image) ---
	if vanity > 0.5 and public_image < -20:
		var pr_cost = int(wealth * 0.03 * vanity)
		wealth -= pr_cost
		public_image += pr_cost / 5000.0
		public_image = clamp(public_image, -100.0, 100.0)
		actions_taken.append({
			"type": "PR_CAMPAIGN",
			"description": "%s launches a PR campaign to rehabilitate their image." % oligarch_name,
			"impact": {"public_image_change": pr_cost / 5000.0}
		})
	
	# --- Greed response (wealth accumulation) ---
	if greed > 0.6:
		var price_hike = int(greed * 10)
		actions_taken.append({
			"type": "PRICE_HIKE",
			"description": "%s raises prices in their %s sector." % [oligarch_name, sector_of_influence],
			"impact": {"price_increase": price_hike, "sector": sector_of_influence}
		})
	
	# --- Intelligence response (counter-player) ---
	if intelligence > 0.6 and awareness_of_player > 50:
		threat_assessment += intelligence * 10
		actions_taken.append({
			"type": "COUNTER_OPERATION",
			"description": "%s deploys investigators to track the resistance." % oligarch_name,
			"impact": {"player_heat_increase": int(intelligence * 15)}
		})
	
	# --- Ambition pursuit ---
	for ambition in ambitions:
		var action = _pursue_ambition(ambition, economy)
		if action.size() > 0:
			actions_taken.append(action)
	
	return actions_taken

## Process a single ambition
func _pursue_ambition(ambition: String, economy: Dictionary) -> Dictionary:
	var progress = ambition_progress.get(ambition, 0.0)
	
	match ambition:
		"Monopolize supply":
			if greed > 0.5 and wealth > 500000:
				wealth -= 100000
				ambition_progress[ambition] = progress + 0.1
				return {
					"type": "AMBITION_ACTION",
					"description": "%s acquires another competitor in the %s sector." % [oligarch_name, sector_of_influence],
					"impact": {"sector_monopoly": sector_of_influence, "price_increase": 15}
				}
		"Achieve political immortality":
			if ideology > 0.4:
				var lobby_cost = int(wealth * 0.02)
				wealth -= lobby_cost
				ambition_progress[ambition] = progress + 0.05
				return {
					"type": "AMBITION_ACTION",
					"description": "%s lobbies the Senate for permanent corporate protections." % oligarch_name,
					"impact": {"senate_alignment_shift": 5}
				}
		"Build a legacy":
			if vanity > 0.5 and wealth > 300000:
				wealth -= 200000
				public_image += 15
				ambition_progress[ambition] = progress + 0.1
				return {
					"type": "AMBITION_ACTION",
					"description": "%s funds a public hospital in The Sinks. Critics call it a vanity project." % oligarch_name,
					"impact": {"public_image_change": 15, "tension_decrease": 5}
				}
		"Escape":
			if paranoia > 70:
				wealth -= 300000
				ambition_progress[ambition] = progress + 0.15
				return {
					"type": "AMBITION_ACTION",
					"description": "%s secretly diverts funds to an offshore escape vessel." % oligarch_name,
					"impact": {"wealth_drain": 300000}
				}
		"Crush the resistance":
			if ruthlessness > 0.6 and awareness_of_player > 30:
				wealth -= 150000
				ambition_progress[ambition] = progress + 0.1
				return {
					"type": "AMBITION_ACTION",
					"description": "%s funds a private militia to sweep The Sinks." % oligarch_name,
					"impact": {"security_presence": 20, "tension_increase": 15}
				}
		"Control the narrative":
			if intelligence > 0.5:
				wealth -= 100000
				ambition_progress[ambition] = progress + 0.08
				return {
					"type": "AMBITION_ACTION",
					"description": "%s buys another media outlet. Independent journalism shrinks." % oligarch_name,
					"impact": {"controversy_suppression": 20}
				}
		"Transcend humanity":
			if ideology > 0.6 and wealth > 500000:
				wealth -= 400000
				ambition_progress[ambition] = progress + 0.12
				return {
					"type": "AMBITION_ACTION",
					"description": "%s announces a new human augmentation program. Costs skyrocket." % oligarch_name,
					"impact": {"tech_price_increase": 50}
				}
		"Purge The Sinks":
			if ruthlessness > 0.8:
				ambition_progress[ambition] = progress + 0.05
				return {
					"type": "AMBITION_ACTION",
					"description": "%s advocates for 'urban renewal' — mass displacement of Sinks residents." % oligarch_name,
					"impact": {"tension_increase": 30, "public_image_change": -20}
				}
	
	return {}

# =============================================================
# BEHAVIORAL PROFILE
# =============================================================

func get_behavioral_profile() -> String:
	if paranoia > 70 and ruthlessness > 0.7:
		return "Cornered Tyrant"
	if paranoia > 70 and ruthlessness < 0.3:
		return "Panicking Coward"
	if vanity > 0.7 and public_image > 30:
		return "Beloved Philanthropist"
	if vanity > 0.7 and public_image < -30:
		return "Desperate Narcissist"
	if greed > 0.7 and wealth > 2000000:
		return "Untouchable Mogul"
	if ideology > 0.7:
		return "True Believer"
	if intelligence > 0.7 and awareness_of_player > 50:
		return "Calculating Hunter"
	return "Corporate Shark"

# =============================================================
# LLM CONTEXT
# =============================================================

func get_llm_context_string() -> String:
	var context = "You are %s, %s of the %s sector. " % [oligarch_name, title, sector_of_influence]
	context += "Behavioral profile: %s. " % get_behavioral_profile()
	context += "Wealth: %d credits. Paranoia: %.0f/100. Public Image: %.0f/100. " % [wealth, paranoia, public_image]
	
	if ambitions.size() > 0:
		context += "Your ambitions: %s. " % ", ".join(ambitions)
	
	# Personality
	context += "Personality: "
	if ruthlessness > 0.6: context += "ruthless, "
	elif ruthlessness < 0.3: context += "cautious, "
	if vanity > 0.6: context += "vain, "
	elif vanity < 0.3: context += "indifferent to image, "
	if intelligence > 0.6: context += "brilliant, "
	elif intelligence < 0.3: context += "dim-witted, "
	if greed > 0.6: context += "insatiable, "
	elif greed < 0.3: context += "content, "
	if ideology > 0.6: context += "a true believer. "
	elif ideology < 0.3: context += "purely profit-driven. "
	else: context += "pragmatic. "
	
	if quirks.size() > 0:
		context += "Quirks you MUST embody: " + ", ".join(quirks) + ". "
	
	if recent_scandals.size() > 0:
		context += "Recent scandals: "
		for scandal in recent_scandals:
			context += "- %s " % scandal
	
	return context
