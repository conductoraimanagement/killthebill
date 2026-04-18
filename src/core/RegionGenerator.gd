extends Node
class_name RegionGenerator

# =============================================================
# RegionGenerator: Procedural World Map Builder
# =============================================================
# At playthrough start, generates 6-10 unique regions with random
# names, properties, and visual biomes. No two playthroughs have
# the same world geography.
# =============================================================

const MIN_REGIONS: int = 6
const MAX_REGIONS: int = 10

# The generated world map — lives for the entire playthrough
var regions: Array[Dictionary] = []
var starting_region: String = ""

# =============================================================
# NAME POOLS — Shuffled at generation for uniqueness
# =============================================================

var prefixes_slum = ["Rust", "Ash", "Gray", "Smog", "Drip", "Scrap", "Gutter", "Soot", "Blight", "Mire"]
var suffixes_slum = ["Hollow", "Row", "Depths", "Block", "Flats", "Pit", "Warren", "Maze", "Sprawl", "Drift"]

var prefixes_elite = ["Crystal", "Silver", "Solar", "Ivory", "Platinum", "Azure", "Opal", "Gilt", "Zenith", "Apex"]
var suffixes_elite = ["Heights", "Spire", "Plaza", "Terrace", "Citadel", "Pinnacle", "Crown", "Summit", "Arch", "Tower"]

var prefixes_industrial = ["Foundry", "Slag", "Iron", "Steam", "Cinder", "Bore", "Anvil", "Rivet", "Piston", "Crucible"]
var suffixes_industrial = ["Basin", "Works", "Yard", "Maw", "Gulch", "Trench", "Core", "Hub", "Strip", "Forge"]

var prefixes_farm = ["Substrate", "Root", "Loam", "Spore", "Canopy", "Verdant", "Deep", "Seed", "Mulch", "Tillage"]
var suffixes_farm = ["Fields", "Beds", "Vaults", "Caverns", "Groves", "Terraces", "Pens", "Burrows", "Flats", "Gardens"]

var prefixes_island = ["Haven", "Obsidian", "Coral", "Phantom", "Tempest", "Jade", "Drift", "Crimson", "Fog", "Tidal"]
var suffixes_island = ["Cay", "Atoll", "Isle", "Reef", "Archipelago", "Reach", "Shoal", "Rock", "Key", "Strand"]

var prefixes_transit = ["Checkpoint", "Border", "Passage", "Corridor", "Junction", "Threshold", "Crossway", "Gate", "Bridge", "Traverse"]
var suffixes_transit = ["Nexus", "Point", "Lock", "Barricade", "Corridor", "Terminal", "Span", "Crossing", "Arch", "Hub"]

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
	
	# Shuffle all name pools
	prefixes_slum.shuffle(); suffixes_slum.shuffle()
	prefixes_elite.shuffle(); suffixes_elite.shuffle()
	prefixes_industrial.shuffle(); suffixes_industrial.shuffle()
	prefixes_farm.shuffle(); suffixes_farm.shuffle()
	prefixes_island.shuffle(); suffixes_island.shuffle()
	prefixes_transit.shuffle(); suffixes_transit.shuffle()
	
	# Track name indices to avoid repeats
	var name_indices = {}
	for type in RegionType.values():
		name_indices[type] = 0
	
	# Generate regions for each type
	for type in RegionType.values():
		var range_vec = type_distribution[type]
		var count = randi_range(range_vec.x, range_vec.y)
		for i in range(count):
			var region = _generate_region(type, name_indices[type])
			name_indices[type] += 1
			regions.append(region)
	
	# Ensure we have at least MIN_REGIONS
	while regions.size() < MIN_REGIONS:
		var extra = _generate_region(RegionType.URBAN_SLUM, name_indices[RegionType.URBAN_SLUM])
		name_indices[RegionType.URBAN_SLUM] += 1
		regions.append(extra)
	
	# Cap at MAX_REGIONS
	if regions.size() > MAX_REGIONS:
		regions.resize(MAX_REGIONS)
	
	# Shuffle the final order
	regions.shuffle()
	
	# First URBAN_SLUM is the starting region
	for region in regions:
		if region["type"] == "URBAN_SLUM":
			starting_region = region["name"]
			region["unlocked"] = true
			break
	
	# Unlock 1-2 additional starting regions
	var unlocked_count = 0
	for region in regions:
		if region["name"] != starting_region and unlocked_count < 2:
			if region["type"] in ["URBAN_SLUM", "INDUSTRIAL", "TRANSIT"]:
				region["unlocked"] = true
				unlocked_count += 1
	
	print("RegionGenerator: Created world with %d regions. Starting in: %s" % [regions.size(), starting_region])

func _generate_region(type: RegionType, index: int) -> Dictionary:
	var region = {
		"id": "region_%d_%d" % [type, index],
		"name": _generate_name(type, index),
		"type": _type_string(type),
		"unlocked": false,
		"security_modifier": 0,
		"tension_modifier": 0,
		"population_density": 0.5, # 0-1
		"infrastructure_targets": [],
		"visual_biome": "",
		"connected_oligarch": "" # Set later by WorldDirector
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

func _generate_name(type: RegionType, index: int) -> String:
	match type:
		RegionType.URBAN_SLUM:
			return prefixes_slum[index % prefixes_slum.size()] + " " + suffixes_slum[index % suffixes_slum.size()]
		RegionType.URBAN_ELITE:
			return prefixes_elite[index % prefixes_elite.size()] + " " + suffixes_elite[index % suffixes_elite.size()]
		RegionType.INDUSTRIAL:
			return prefixes_industrial[index % prefixes_industrial.size()] + " " + suffixes_industrial[index % suffixes_industrial.size()]
		RegionType.AGRICULTURAL:
			return prefixes_farm[index % prefixes_farm.size()] + " " + suffixes_farm[index % suffixes_farm.size()]
		RegionType.ISLAND_RETREAT:
			return prefixes_island[index % prefixes_island.size()] + " " + suffixes_island[index % suffixes_island.size()]
		RegionType.TRANSIT:
			return prefixes_transit[index % prefixes_transit.size()] + " " + suffixes_transit[index % suffixes_transit.size()]
	return "Unknown Region"

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
