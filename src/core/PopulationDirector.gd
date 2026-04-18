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

const MAX_NPCS: int = 40 # Total persistent population cap

# The master roster — lives for the entire playthrough
var roster: Array[NPCData] = []

# Name pools for procedural generation
var first_names: Array[String] = [
	"Ada", "Boris", "Celeste", "Dmitri", "Elara", "Felix", "Greta", "Hassan",
	"Ingrid", "Joaquin", "Kira", "Lev", "Mira", "Nikolai", "Olga", "Pavel",
	"Quinn", "Rosa", "Sergei", "Tova", "Uri", "Vera", "Wren", "Xander",
	"Yara", "Zev", "Anika", "Bogdan", "Cass", "Daria", "Emil", "Freya",
	"Gideon", "Hana", "Ilya", "Juno", "Kai", "Lena", "Maxim", "Nadia"
]

var last_names: Array[String] = [
	"Volkov", "Chen", "Okafor", "Petrov", "Vasquez", "Nowak", "Dubois",
	"Tanaka", "Ivanova", "Morales", "Bakker", "Sato", "Kowalski", "Reyes",
	"Bergman", "Ortiz", "Lindgren", "Torres", "Kozlov", "Alvarez",
	"Strand", "Popov", "Larsen", "Cruz", "Nemeth", "Singh", "Voss",
	"Ishida", "Brandt", "Ochoa", "Szabo", "Andersen", "Rojas", "Kuhn",
	"Fuentes", "Holm", "Cabrera", "Richter", "Delgado", "Nygaard"
]

# Quirk pools — drawn randomly to make each NPC feel like a real person
var quirks_habits: Array[String] = [
	"Always chewing something", "Cracks knuckles when thinking",
	"Hums old pop songs under their breath", "Compulsively counts things",
	"Never makes eye contact", "Taps fingers on every surface",
	"Collects useless pre-collapse trinkets", "Obsessively cleans their hands",
	"Sketches in a battered notebook", "Always eating, even mid-conversation",
	"Paces when talking", "Fidgets with a broken lighter they never use"
]

var quirks_speech: Array[String] = [
	"Stutters when nervous", "Speaks in short, clipped sentences",
	"Laughs at inappropriate moments", "Whispers even when not hiding",
	"Uses outdated slang from before the collapse", "Ends sentences like questions",
	"Talks too fast when excited", "Long awkward pauses mid-sentence",
	"Refers to themselves in third person", "Has a thick regional accent",
	"Swears constantly", "Overly formal, almost robotic speech"
]

var quirks_physical: Array[String] = [
	"Has a limp from an Enforcer beating", "Missing two fingers on left hand",
	"Covered in faded tattoos of old corporate logos", "Prominent facial scar",
	"Coughs frequently from bad air exposure", "Unnervingly still, barely blinks",
	"Smells faintly of chemical solvents", "One eye is clouded over",
	"Hands shake slightly at all times", "Unusually tall, towers over others",
	"Small and wiry, moves like a rat", "Premature grey hair, looks decades older"
]

var quirks_fears: Array[String] = [
	"Terrified of enclosed spaces", "Flinches at loud noises",
	"Cannot sleep without a light source", "Paranoid about being followed",
	"Refuses to eat food they didn't prepare", "Panics near large crowds",
	"Deeply afraid of dogs or drones", "Won't go above the third floor",
	"Freezes completely when threatened", "Obsessively checks exits in every room"
]

var quirks_backstory: Array[String] = [
	"Lost a child to the water rationing", "Used to be a teacher before the collapse",
	"Former Enforcer who deserted", "Talks to a dead sibling as if they're still alive",
	"Was wealthy once, remembers luxury with bitterness",
	"Raised by the street, never knew parents", "Survived a sector purge alone",
	"Carries a photo of someone they won't talk about",
	"Was a musician, still hums melodies nobody recognizes",
	"Betrayed a friend to Enforcers, haunted by guilt",
	"Has a hidden stash of pre-collapse books", "Escaped from an Oligarch's private compound"
]

func _ready():
	pass

# =============================================================
# ROSTER GENERATION — Called once at the start of a new playthrough
# =============================================================

func generate_new_roster() -> void:
	roster.clear()
	
	# Shuffle name pools so each run feels different
	first_names.shuffle()
	last_names.shuffle()
	
	# Build a combined quirk pool and shuffle it
	var all_quirks: Array[String] = []
	all_quirks.append_array(quirks_habits)
	all_quirks.append_array(quirks_speech)
	all_quirks.append_array(quirks_physical)
	all_quirks.append_array(quirks_fears)
	all_quirks.append_array(quirks_backstory)
	all_quirks.shuffle()
	
	var quirk_index = 0
	
	for i in range(MAX_NPCS):
		var npc = NPCData.new()
		npc.npc_id = "npc_" + str(i)
		npc.npc_name = first_names[i % first_names.size()] + " " + last_names[i % last_names.size()]
		
		# Assign social class with weighted distribution
		# Most citizens are Workers or Destitute in this world
		var class_roll = randf()
		if class_roll < 0.05:
			npc.social_class = 0 # Oligarch (rare)
		elif class_roll < 0.15:
			npc.social_class = 1 # Enforcer
		elif class_roll < 0.55:
			npc.social_class = 2 # Worker
		else:
			npc.social_class = 3 # Destitute
		
		# Randomize intrinsic traits — these define who they ARE
		# Using full 0.0-1.0 range to get genuine diversity
		npc.resilience = randf()
		npc.aggression = randf()
		npc.empathy = randf()
		npc.idealism = randf()
		npc.greed = randf()
		npc.conformity = randf()
		
		# Slight class-based biases (nature vs nurture of upbringing)
		match npc.social_class:
			0: # Oligarchs tend toward greed and low empathy
				npc.greed = clamp(npc.greed + 0.2, 0.0, 1.0)
				npc.empathy = clamp(npc.empathy - 0.2, 0.0, 1.0)
			1: # Enforcers tend toward conformity and aggression
				npc.conformity = clamp(npc.conformity + 0.2, 0.0, 1.0)
				npc.aggression = clamp(npc.aggression + 0.1, 0.0, 1.0)
			3: # Destitute tend toward higher resilience (survivors)
				npc.resilience = clamp(npc.resilience + 0.1, 0.0, 1.0)
		
		# Assign 1-3 random quirks from the shuffled pool
		var num_quirks = randi_range(1, 3)
		for q in range(num_quirks):
			if quirk_index < all_quirks.size():
				npc.quirks.append(all_quirks[quirk_index])
				quirk_index += 1
			else:
				# Pool exhausted, reshuffle and reset
				all_quirks.shuffle()
				quirk_index = 0
				npc.quirks.append(all_quirks[quirk_index])
				quirk_index += 1
		
		# Set starting dynamic state based on class
		match npc.social_class:
			0:
				npc.personal_wealth = randi_range(800, 1500)
				npc.stress_level = randf_range(5.0, 20.0)
				npc.hope = randf_range(60.0, 90.0)
				npc.immediate_need = "Maintaining power"
			1:
				npc.personal_wealth = randi_range(150, 400)
				npc.stress_level = randf_range(20.0, 40.0)
				npc.hope = randf_range(40.0, 60.0)
				npc.immediate_need = "Job security"
			2:
				npc.personal_wealth = randi_range(30, 120)
				npc.stress_level = randf_range(30.0, 50.0)
				npc.hope = randf_range(30.0, 55.0)
				npc.immediate_need = "Affordable food"
			3:
				npc.personal_wealth = randi_range(0, 30)
				npc.stress_level = randf_range(40.0, 70.0)
				npc.hope = randf_range(10.0, 40.0)
				npc.immediate_need = "Survival"
		
		roster.append(npc)
	
	print("PopulationDirector: Generated roster of ", roster.size(), " persistent NPCs.")

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
