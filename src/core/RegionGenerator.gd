extends Node
class_name RegionGenerator

# =============================================================
# RegionGenerator: Procedural World Map Builder
# =============================================================
# At playthrough start, generates 6-10 unique regions with random
# names, properties, and visual biomes. No two playthroughs have
# No NPC is spawned or despawned mid-game.
# =============================================================

signal world_generated()

const MIN_REGIONS: int = 6
const MAX_REGIONS: int = 10

# The generated world map — lives for the entire playthrough
var regions: Array[Dictionary] = []
var starting_region: String = ""

# =============================================================
# REGION TYPES — Templates with property ranges
# =============================================================

enum RegionType {
	URBAN_SLUM,
	URBAN_ELITE,
	INDUSTRIAL,
	AGRICULTURAL,
	ISLAND_RETREAT,
	TRANSIT
}

# How many of each type to generate (min, max)
var type_distribution = {
	RegionType.URBAN_SLUM: Vector2i(2, 3),
	RegionType.URBAN_ELITE: Vector2i(1, 2),
	RegionType.INDUSTRIAL: Vector2i(1, 2),
	RegionType.AGRICULTURAL: Vector2i(1, 2),
	RegionType.ISLAND_RETREAT: Vector2i(0, 1),
	RegionType.TRANSIT: Vector2i(1, 2)
}

func _ready():
	pass

# =============================================================
# WORLD GENERATION — Called once at the start of a new playthrough
# =============================================================

func generate_world() -> void:
	regions.clear()
	
	if has_node("/root/LLMManager"):
		var llm = get_node("/root/LLMManager")
		if not llm.world_regions_generated.is_connected(_on_world_regions_generated):
			llm.world_regions_generated.connect(_on_world_regions_generated)
		
		# Build count distribution for LLM
		var distribution = {}
		for type in type_distribution.keys():
			var range_vec = type_distribution[type]
			distribution[_type_string(type)] = randi_range(range_vec.x, range_vec.y)
			
		print("RegionGenerator: Requesting procedural geography from LLM...")
		llm.request_world_regions_generation(distribution)
	else:
		push_error("LLMManager missing! Falling back to empty world.")

func _on_world_regions_generated(data: Array) -> void:
	print("RegionGenerator: Received %d regions from LLM." % data.size())
	
	for r_data in data:
		var type_str = r_data.get("type", "URBAN_SLUM")
		var type = _string_to_type(type_str)
		var region = _generate_region_shell(type, roster_index_helper(type))
		region["name"] = r_data.get("name", "Unknown Sector")
		region["short_description"] = r_data.get("short_description", "")
		regions.append(region)
	
	# Finalize world
	regions.shuffle()
	for region in regions:
		if region["type"] == "URBAN_SLUM":
			starting_region = region["name"]
			region["unlocked"] = true
			break
	# For this sprint, all regions are travel-accessible via the
	# TransitZone pillar. Future work can gate unlocks behind TRANSIT
	# checkpoint infiltration or story beats.
	for region in regions:
		region["unlocked"] = true

	world_generated.emit()
	print("RegionGenerator: World geography finalized.")

# Helper to keep IDs unique if needed
var _type_counts = {}
func roster_index_helper(type: RegionType) -> int:
	var c = _type_counts.get(type, 0)
	_type_counts[type] = c + 1
	return c

func _string_to_type(s: String) -> RegionType:
	match s:
		"URBAN_SLUM": return RegionType.URBAN_SLUM
		"URBAN_ELITE": return RegionType.URBAN_ELITE
		"INDUSTRIAL": return RegionType.INDUSTRIAL
		"AGRICULTURAL": return RegionType.AGRICULTURAL
		"ISLAND_RETREAT": return RegionType.ISLAND_RETREAT
		"TRANSIT": return RegionType.TRANSIT
	return RegionType.URBAN_SLUM

func _generate_region_shell(type: RegionType, index: int) -> Dictionary:
	var region = {
		"id": "region_%d_%d" % [type, index],
		"name": "Generating...",
		"type": _type_string(type),
		"unlocked": false,
		"security_modifier": 0,
		"tension_modifier": 0,
		"population_density": 0.5,
		"infrastructure_targets": [],
		"visual_biome": "",
		"connected_oligarch": ""
	}
	
	match type:
		RegionType.URBAN_SLUM:
			region["security_modifier"] = randi_range(-30, -10)
			region["tension_modifier"] = randi_range(10, 30)
			region["population_density"] = randf_range(0.7, 1.0)
			region["infrastructure_targets"] = _pick_targets(["Water Treatment", "Power Relay", "Comm Array", "Food Depot", "Clinic"], 2)
			region["visual_biome"] = ["brutalist_fog", "neon_rain", "concrete_decay", "toxic_sprawl"][randi() % 4]
		
		RegionType.URBAN_ELITE:
			region["security_modifier"] = randi_range(30, 60)
			region["tension_modifier"] = randi_range(-30, -10)
			region["population_density"] = randf_range(0.1, 0.3)
			region["infrastructure_targets"] = _pick_targets(["Financial Server", "Senate Hall", "Luxury Mall", "Private Hangar"], 2)
			region["visual_biome"] = ["glass_spire", "garden_terrace", "white_brutalism", "floating_plaza"][randi() % 4]
		
		RegionType.INDUSTRIAL:
			region["security_modifier"] = randi_range(-5, 15)
			region["tension_modifier"] = randi_range(0, 15)
			region["population_density"] = randf_range(0.2, 0.4)
			region["infrastructure_targets"] = _pick_targets(["Refinery", "Assembly Line", "Waste Processor", "Mining Shaft", "Rail Depot"], 3)
			region["visual_biome"] = ["smoke_stack", "rust_canyon", "molten_core", "warehouse_grid"][randi() % 4]
		
		RegionType.AGRICULTURAL:
			region["security_modifier"] = randi_range(-10, 5)
			region["tension_modifier"] = randi_range(-5, 10)
			region["population_density"] = randf_range(0.1, 0.25)
			region["infrastructure_targets"] = _pick_targets(["Hydroponic Vault", "Grain Silo", "Livestock Dome", "Seed Bank", "Irrigation Hub"], 3)
			region["visual_biome"] = ["underground_green", "terraced_cavern", "dome_farm", "strip_field"][randi() % 4]
		
		RegionType.ISLAND_RETREAT:
			region["security_modifier"] = randi_range(50, 80)
			region["tension_modifier"] = randi_range(-40, -20)
			region["population_density"] = randf_range(0.01, 0.05)
			region["infrastructure_targets"] = _pick_targets(["Private Dock", "Oligarch Villa", "Escape Vessel", "Comm Jammer"], 2)
			region["visual_biome"] = ["tropical_fortress", "volcanic_bunker", "arctic_retreat", "ocean_platform"][randi() % 4]
		
		RegionType.TRANSIT:
			region["security_modifier"] = randi_range(10, 30)
			region["tension_modifier"] = randi_range(5, 15)
			region["population_density"] = randf_range(0.3, 0.6)
			region["infrastructure_targets"] = _pick_targets(["Checkpoint Scanner", "Cargo Bay", "Smuggler Tunnel", "ID Forge"], 2)
			region["visual_biome"] = ["highway_corridor", "rail_junction", "border_wall", "underground_passage"][randi() % 4]
	
	return region

# Names are now generated by LLM

func _type_string(type: RegionType) -> String:
	match type:
		RegionType.URBAN_SLUM: return "URBAN_SLUM"
		RegionType.URBAN_ELITE: return "URBAN_ELITE"
		RegionType.INDUSTRIAL: return "INDUSTRIAL"
		RegionType.AGRICULTURAL: return "AGRICULTURAL"
		RegionType.ISLAND_RETREAT: return "ISLAND_RETREAT"
		RegionType.TRANSIT: return "TRANSIT"
	return "UNKNOWN"

func _pick_targets(pool: Array, count: int) -> Array:
	var shuffled = pool.duplicate()
	shuffled.shuffle()
	return shuffled.slice(0, min(count, shuffled.size()))

# =============================================================
# QUERIES
# =============================================================

func get_region_by_name(region_name: String) -> Dictionary:
	for region in regions:
		if region["name"] == region_name:
			return region
	return {}

func get_regions_by_type(type_string: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for region in regions:
		if region["type"] == type_string:
			result.append(region)
	return result

func get_unlocked_regions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for region in regions:
		if region["unlocked"]:
			result.append(region)
	return result

func get_world_summary() -> Dictionary:
	var summary = {}
	for region in regions:
		var t = region["type"]
		summary[t] = summary.get(t, 0) + 1
	return summary
