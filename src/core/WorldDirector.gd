extends Node

# The core brain of the "Butterfly Effect" system.
# This singleton manages the global economy, procedural Oligarchs,
# generated regions, and event ripples.

# ---------------------------------------------------------
# SIGNALS
# ---------------------------------------------------------
signal event_triggered(action_id: String, target: String)
signal world_state_changed()
signal netfeed_event_generated(event_data: Dictionary)
signal oligarch_action_taken(action: Dictionary)
signal playthrough_setup_complete() # Fired when regions, oligarchs, and NPCs are ready
signal victory_achieved(kind: String, title: String, flavor: String)

# Flips true the first time a victory condition hits; prevents repeat fires
# until the scene is reloaded / playthrough reinitialized.
var _victory_locked: bool = false

# ---------------------------------------------------------
# NETFEED (The Internet/Communication Array)
# ---------------------------------------------------------
var netfeed_history = [] # Stores { "type": String, "headline": String, "timestamp": int }

# ---------------------------------------------------------
# GLOBAL ECONOMY STATE
# ---------------------------------------------------------
var global_economy = {
	"food_price": 100,
	"tech_price": 500,
	"security_presence": 50, # 0 (None) to 100 (Martial Law)
	"public_tension": 20, # 0 (Docile) to 100 (Rioting)
	"senate_alignment": 50 # 0 (Fully Pro-Sinks) to 100 (Fully Pro-Enclave)
}

# ---------------------------------------------------------
# PROCEDURAL OLIGARCHS — Generated at playthrough start
# ---------------------------------------------------------
var oligarchs: Array[OligarchData] = []

# ---------------------------------------------------------
# PROCEDURAL POLITICIANS — 11 senators, generated at start
# ---------------------------------------------------------
var politicians: Array[PoliticianData] = []

# ---------------------------------------------------------
# PROCEDURAL REGIONS — Generated at playthrough start
# ---------------------------------------------------------
var current_region: String = ""

# ---------------------------------------------------------
# World cycle counter — bumped each run_world_cycle()
# ---------------------------------------------------------
var cycle: int = 0

func _ready():
	print("WorldDirector initialized. Economy online.")

# =============================================================
# PLAYTHROUGH INITIALIZATION
# =============================================================

func initialize_playthrough(preloaded_config: Dictionary = {}) -> void:
	# Reset all playthrough state so this is idempotent across restarts.
	global_economy = {
		"food_price": 100,
		"tech_price": 500,
		"security_presence": 50,
		"public_tension": 20,
		"senate_alignment": 50,
	}
	oligarchs.clear()
	politicians.clear()
	netfeed_history.clear()
	cycle = 0
	_victory_locked = false
	# Don't wipe current_region — Main.gd sets it before calling us.

	if has_node("/root/SenateDirector"):
		var senate = get_node("/root/SenateDirector")
		senate.active_bill = {}
		senate.bill_history.clear()
		senate.politicians = []

	# If the user loaded a saved world config, inject it directly and skip
	# LLM generation entirely. Otherwise fall through to the async generator
	# chain that hits LLMManager (with offline fallback).
	if not preloaded_config.is_empty():
		_apply_preloaded_config(preloaded_config)
		return

	# 1. World Geography (Asynchronous)
	if has_node("/root/RegionGenerator"):
		var region_gen = get_node("/root/RegionGenerator")
		if not region_gen.world_generated.is_connected(_on_world_generated):
			region_gen.world_generated.connect(_on_world_generated)
		region_gen.generate_world()
	else:
		_on_world_generated()

func _on_world_generated() -> void:
	if has_node("/root/RegionGenerator"):
		current_region = get_node("/root/RegionGenerator").starting_region
	
	# 2. Oligarchs (Asynchronous)
	_generate_oligarchs_async()

func _generate_oligarchs_async() -> void:
	if has_node("/root/LLMManager"):
		var llm = get_node("/root/LLMManager")
		if not llm.oligarchs_generated.is_connected(_on_oligarchs_generated):
			llm.oligarchs_generated.connect(_on_oligarchs_generated)
		
		var count = randi_range(4, 6)
		print("WorldDirector: Requesting %d procedural oligarchs from LLM..." % count)
		llm.request_oligarch_generation(count)
	else:
		push_error("LLMManager missing! Cannot generate procedural world.")

func _on_oligarchs_generated(data: Array) -> void:
	oligarchs.clear()
	print("WorldDirector: Received %d oligarchs from LLM. Finalizing setup..." % data.size())
	
	for o_data in data:
		var o = OligarchData.new()
		o.oligarch_id = "oligarch_%s" % str(oligarchs.size())
		o.oligarch_name = o_data.get("first_name", "Unknown") + " " + o_data.get("last_name", "Oligarch")
		o.title = o_data.get("title", "Executive")
		o.sector_of_influence = o_data.get("sector", "Various")
		o.ambitions = Array(o_data.get("ambitions", []), TYPE_STRING, &"", null)
		o.quirks = Array(o_data.get("quirks", []), TYPE_STRING, &"", null)
		
		# Randomize intrinsic traits
		o.ruthlessness = randf()
		o.vanity = randf()
		o.paranoia_base = randf()
		o.intelligence = randf()
		o.greed = randf()
		o.ideology = randf()
		
		# Starting state
		o.wealth = randi_range(500000, 3000000)
		o.paranoia = o.paranoia_base * 30.0
		o.public_image = randf_range(-20.0, 50.0)
		
		# Initialize ambitions progress
		for ambition in o.ambitions:
			o.ambition_progress[ambition] = 0.0
			
		oligarchs.append(o)
		print("  - %s (%s of %s)" % [o.oligarch_name, o.title, o.sector_of_influence])

	# 3. Assign territories
	if has_node("/root/RegionGenerator"):
		_assign_oligarch_territories(get_node("/root/RegionGenerator"))
	
	# 4. NPC roster (Asynchronous)
	if has_node("/root/PopulationDirector"):
		var pop_dir = get_node("/root/PopulationDirector")
		if not pop_dir.population_generated.is_connected(_on_population_generated):
			pop_dir.population_generated.connect(_on_population_generated)
		pop_dir.generate_new_roster()
	else:
		_finish_setup()

func _on_population_generated() -> void:
	# 5. Politicians (Asynchronous)
	_generate_politicians_async()

func _generate_politicians_async() -> void:
	if has_node("/root/LLMManager"):
		var llm = get_node("/root/LLMManager")
		if not llm.politicians_generated.is_connected(_on_politicians_generated):
			llm.politicians_generated.connect(_on_politicians_generated)
		print("WorldDirector: Requesting 11 procedural politicians from LLM...")
		llm.request_politician_generation(11)
	else:
		_on_politicians_generated([])

func _on_politicians_generated(data: Array) -> void:
	politicians.clear()
	print("WorldDirector: Received %d politicians from LLM. Finalizing Senate..." % data.size())

	for i in range(data.size()):
		var p_data = data[i]
		var p := PoliticianData.new()
		p.politician_id = "politician_%d" % i
		p.politician_name = "%s %s" % [p_data.get("first_name", "Unknown"), p_data.get("last_name", "Senator")]
		p.title = p_data.get("title", "Senator")
		p.faction = p_data.get("faction", "INDEPENDENT")
		p.cause = p_data.get("cause", "")
		p.seat_district = p_data.get("seat_district", "At-Large")
		p.quirks = Array(p_data.get("quirks", []), TYPE_STRING, &"", null)

		# Randomize intrinsic traits
		p.integrity = randf()
		p.corruption = randf()
		p.populism = randf()
		p.ambition = randf()
		p.conviction = randf()
		p.charisma = randf()

		# Starting dynamic state
		p.public_approval = randf_range(-20.0, 40.0)
		p.re_election_proximity = randi_range(6, 36)
		p.position_consistency = 0.5

		politicians.append(p)
		print("  - %s (%s, %s)" % [p.politician_name, p.title, p.faction])

	# Register with the SenateDirector singleton if present.
	if has_node("/root/SenateDirector"):
		get_node("/root/SenateDirector").register_politicians(politicians)

	_finish_setup()

func _finish_setup() -> void:
	playthrough_setup_complete.emit()
	print("WorldDirector: Playthrough setup complete.")


# =============================================================
# PRELOADED CONFIG PATH — used when a saved world is loaded
# =============================================================

func _apply_preloaded_config(config: Dictionary) -> void:
	var cfg_mgr = get_node_or_null("/root/WorldConfigManager")
	if cfg_mgr == null:
		push_error("WorldConfigManager missing; cannot apply preloaded config.")
		_finish_setup()
		return

	# Regions — drop them straight into RegionGenerator.
	if has_node("/root/RegionGenerator"):
		var region_gen = get_node("/root/RegionGenerator")
		region_gen.regions.clear()
		for r_dict in config.get("regions", []):
			region_gen.regions.append(r_dict.duplicate(true))
		region_gen.starting_region = str(config.get("starting_region_name", ""))
		if region_gen.starting_region == "" and region_gen.regions.size() > 0:
			# Fallback: first slum unlocks as start.
			for r in region_gen.regions:
				if r.get("type", "") == "URBAN_SLUM":
					region_gen.starting_region = r["name"]
					r["unlocked"] = true
					break
		current_region = region_gen.starting_region

	# Oligarchs
	oligarchs.clear()
	for o_dict in config.get("oligarchs", []):
		oligarchs.append(cfg_mgr.rehydrate_oligarch(o_dict))

	# Politicians
	politicians.clear()
	for p_dict in config.get("politicians", []):
		politicians.append(cfg_mgr.rehydrate_politician(p_dict))
	if has_node("/root/SenateDirector"):
		get_node("/root/SenateDirector").register_politicians(politicians)

	# NPCs
	if has_node("/root/PopulationDirector"):
		var pop_dir = get_node("/root/PopulationDirector")
		pop_dir.roster.clear()
		for n_dict in config.get("npcs", []):
			pop_dir.roster.append(cfg_mgr.rehydrate_npc(n_dict))

	print("WorldDirector: loaded world '%s' (%d regions, %d oligarchs, %d politicians, %d NPCs)." % [
		str(config.get("name", "unknown")),
		(config.get("regions", []) as Array).size(),
		(config.get("oligarchs", []) as Array).size(),
		(config.get("politicians", []) as Array).size(),
		(config.get("npcs", []) as Array).size(),
	])
	_finish_setup()

func _assign_oligarch_territories(region_gen) -> void:
	# Link oligarchs to regions matching their sector type
	for o in oligarchs:
		match o.sector_of_influence:
			"Food":
				var farms = region_gen.get_regions_by_type("AGRICULTURAL")
				if farms.size() > 0:
					farms[0]["connected_oligarch"] = o.oligarch_id
			"Security":
				var transits = region_gen.get_regions_by_type("TRANSIT")
				if transits.size() > 0:
					transits[0]["connected_oligarch"] = o.oligarch_id
			"Tech", "Pharma", "Energy":
				var industry = region_gen.get_regions_by_type("INDUSTRIAL")
				for region in industry:
					if region["connected_oligarch"] == "":
						region["connected_oligarch"] = o.oligarch_id
						break
			"Media":
				var elite = region_gen.get_regions_by_type("URBAN_ELITE")
				if elite.size() > 0:
					elite[0]["connected_oligarch"] = o.oligarch_id

# =============================================================
# WORLD CYCLE — Called each tick to evolve everything
# =============================================================

func run_world_cycle() -> void:
	cycle += 1
	_evolve_oligarchs()

	# Evolve NPCs
	if has_node("/root/PopulationDirector"):
		get_node("/root/PopulationDirector").evolve_all_npcs(global_economy)

	# Tick the Senate — resolves last bill, picks a sponsor, proposes a new bill.
	if has_node("/root/SenateDirector") and politicians.size() > 0:
		var senate = get_node("/root/SenateDirector")
		var recent_netfeed: Array = netfeed_history.slice(max(0, netfeed_history.size() - 5))
		senate.begin_cycle(global_economy, oligarchs, recent_netfeed)

	_update_region_dynamics()
	_check_systemic_collapse()
	world_state_changed.emit()

func _evolve_oligarchs() -> void:
	for o in oligarchs:
		var actions = o.process_world_state(global_economy, oligarchs)
		for action in actions:
			_apply_oligarch_action(action)
			oligarch_action_taken.emit(action)

func _apply_oligarch_action(action: Dictionary) -> void:
	var impact = action.get("impact", {})
	
	if impact.has("security_presence"):
		global_economy["security_presence"] = clamp(
			global_economy["security_presence"] + impact["security_presence"], 0, 100)
	if impact.has("tension_increase"):
		global_economy["public_tension"] = clamp(
			global_economy["public_tension"] + impact["tension_increase"], 0, 100)
	if impact.has("tension_decrease"):
		global_economy["public_tension"] = clamp(
			global_economy["public_tension"] - impact["tension_decrease"], 0, 100)
	if impact.has("senate_alignment_shift"):
		global_economy["senate_alignment"] = clamp(
			global_economy["senate_alignment"] + impact["senate_alignment_shift"], 0, 100)
	if impact.has("price_increase"):
		var sector = impact.get("sector", "")
		if sector == "Food":
			global_economy["food_price"] += impact["price_increase"]
		elif sector in ["Tech", "Pharma"]:
			global_economy["tech_price"] += impact["price_increase"]
	if impact.has("tech_price_increase"):
		global_economy["tech_price"] += impact["tech_price_increase"]
	
	# Optionally generate a NetFeed event from the action
	if action.get("type", "") in ["AMBITION_ACTION", "PR_CAMPAIGN", "PRICE_HIKE"]:
		var event = {
			"type": "NEWS_TICKER",
			"headline": action.get("description", ""),
			"timestamp": Time.get_unix_time_from_system()
		}
		netfeed_history.append(event)
		netfeed_event_generated.emit(event)

# ---------------------------------------------------------
# EVENT HANDLING (The Butterfly Effect)
# ---------------------------------------------------------
func trigger_event(action_id: String, target: String = ""):
	print("World Event Triggered: ", action_id, " on ", target)
	event_triggered.emit(action_id, target)
	
	match action_id:
		"sabotage_facility":
			_ripple_sabotage(target)
		"assassinate_oligarch":
			_ripple_assassination(target)
		"hack_grid":
			_ripple_grid_hack()
		"exert_political_pressure":
			_ripple_political_pressure(target)
		"travel":
			_travel_to_region(target)
		"leak_scandal":
			_ripple_leak_scandal(target)
	
	_update_region_dynamics()
	world_state_changed.emit()
	_check_systemic_collapse()

# --- Ripple Logic ---

func _ripple_sabotage(target_sector: String):
	for o in oligarchs:
		if o.sector_of_influence == target_sector and o.alive:
			o.wealth -= 50000
			o.paranoia += 20
			break
	if target_sector == "Food":
		global_economy["food_price"] += 200
	elif target_sector in ["Tech", "Pharma", "Energy"]:
		global_economy["tech_price"] += 150
	global_economy["public_tension"] = clamp(global_economy["public_tension"] + 15, 0, 100)
	global_economy["security_presence"] = clamp(global_economy["security_presence"] + 10, 0, 100)
	print("Ripple: %s sector sabotaged. Prices spike, tension rises." % target_sector)

	var headline: String = _sabotage_headline(target_sector)
	var event := {
		"type": "NEWS_TICKER",
		"headline": headline,
		"timestamp": Time.get_unix_time_from_system(),
	}
	netfeed_history.append(event)
	netfeed_event_generated.emit(event)


func _sabotage_headline(sector: String) -> String:
	var region_tag: String = current_region if current_region != "" else "the Sinks"
	match sector:
		"Food":
			return "Overnight raid on %s food depot — Enforcers sweep neighboring blocks." % region_tag
		"Tech":
			return "%s refinery sabotage suspected; tech prices surge across the grid." % region_tag
		"Pharma":
			return "%s pharma store torched. Medicine shortages reported in The Sinks." % region_tag
		"Energy":
			return "%s power relay downed. Enclave switches to backup; tensions spike." % region_tag
		"Security":
			return "Checkpoint near %s breached overnight. Patrols redeployed." % region_tag
		"Media":
			return "%s media spire goes dark for 18 minutes. No statement issued." % region_tag
	return "Sabotage reported in %s. Authorities investigating." % region_tag

func _ripple_assassination(target_id: String):
	for o in oligarchs:
		if o.oligarch_id == target_id and o.alive:
			o.alive = false
			global_economy["public_tension"] += 40
			print("Ripple: %s eliminated. Power vacuum in %s." % [o.oligarch_name, o.sector_of_influence])
			
			# All surviving oligarchs spike paranoia
			for other in oligarchs:
				if other.alive and other.oligarch_id != target_id:
					other.paranoia += 30
					other.awareness_of_player += 40
			
			# If this was a Media oligarch, controversy explodes
			if o.sector_of_influence == "Media":
				for other in oligarchs:
					if other.alive:
						other.controversy_level = 100
			break

func _ripple_grid_hack():
	for o in oligarchs:
		if o.sector_of_influence == "Tech" and o.alive:
			o.wealth -= 10000
			break
	global_economy["security_presence"] = max(0, global_economy["security_presence"] - 20)
	print("Ripple: Grid hacked. Security blinded temporarily.")

func _ripple_political_pressure(target_faction: String):
	if target_faction == "Sinks":
		global_economy["senate_alignment"] -= 10
		global_economy["public_tension"] -= 5
	elif target_faction == "Enclave":
		global_economy["senate_alignment"] += 10
		global_economy["security_presence"] += 5

func _ripple_leak_scandal(target_id: String):
	for o in oligarchs:
		if o.oligarch_id == target_id and o.alive:
			o.public_image = clamp(o.public_image - 30, -100, 100)
			o.controversy_level = clamp(o.controversy_level + 50, 0, 100)
			o.recent_scandals.append("Player leaked classified datashard.")
			global_economy["public_tension"] = clamp(global_economy["public_tension"] + 8, 0, 100)
			print("Ripple: Scandal hits %s. Public image tanks." % o.oligarch_name)

			var event := {
				"type": "NEWS_TICKER",
				"headline": "LEAK: Internal dossier on %s hits the feed. Outlets scramble to verify." % o.oligarch_name,
				"timestamp": Time.get_unix_time_from_system(),
			}
			netfeed_history.append(event)
			netfeed_event_generated.emit(event)
			break

func _travel_to_region(target_region: String):
	if has_node("/root/RegionGenerator"):
		var region_gen = get_node("/root/RegionGenerator")
		var region = region_gen.get_region_by_name(target_region)
		if region.size() > 0 and region.get("unlocked", false):
			current_region = target_region
			print("Traveled to: ", current_region)
		else:
			print("Travel denied. Region locked or invalid.")

func _update_region_dynamics():
	if not has_node("/root/RegionGenerator"):
		return
	var region_gen = get_node("/root/RegionGenerator")
	
	for region in region_gen.regions:
		match region["type"]:
			"URBAN_SLUM":
				if global_economy["food_price"] > 300:
					region["tension_modifier"] = randi_range(30, 50)
			"URBAN_ELITE":
				if global_economy["senate_alignment"] < 30:
					region["security_modifier"] = randi_range(50, 70)

# ---------------------------------------------------------
# PR & REPUTATION ENGINE & THE NETFEED
# ---------------------------------------------------------
func trigger_news_cycle():
	print("--- DAILY NEWS CYCLE (NETFEED REFRESH) ---")
	
	if has_node("/root/LLMManager"):
		var llm = get_node("/root/LLMManager")
		if not llm.netfeed_stream_received.is_connected(_on_netfeed_stream_received):
			llm.netfeed_stream_received.connect(_on_netfeed_stream_received)
		
		# Build oligarch context for the LLM
		var oligarch_context = {}
		for o in oligarchs:
			if o.alive:
				oligarch_context[o.oligarch_name] = {
					"sector": o.sector_of_influence,
					"wealth": o.wealth,
					"paranoia": o.paranoia,
					"public_image": o.public_image,
					"controversy": o.controversy_level,
					"ambitions": o.ambitions,
					"profile": o.get_behavioral_profile()
				}
		
		llm.request_netfeed_events(global_economy, oligarch_context)
	else:
		push_warning("LLMManager not found. Cannot evaluate complex conjectures.")

func _on_netfeed_stream_received(events: Array):
	for event in events:
		event["timestamp"] = Time.get_unix_time_from_system()
		var event_type = event.get("type", "NEWS_TICKER")
		
		if event_type == "NEWS_TICKER":
			netfeed_history.append(event)
			netfeed_event_generated.emit(event)
			print(">>> [PUBLIC NEWS] " + event.get("headline", ""))
		elif event_type == "SILENT_RIPPLE":
			print(">>> [INVISIBLE SHIFT] " + event.get("systemic_impact", ""))

# ---------------------------------------------------------
# QUERIES
# ---------------------------------------------------------

func get_oligarch_by_id(id: String) -> OligarchData:
	for o in oligarchs:
		if o.oligarch_id == id:
			return o
	return null

func get_oligarch_by_sector(sector: String) -> OligarchData:
	for o in oligarchs:
		if o.sector_of_influence == sector and o.alive:
			return o
	return null

func get_living_oligarchs() -> Array[OligarchData]:
	var result: Array[OligarchData] = []
	for o in oligarchs:
		if o.alive:
			result.append(o)
	return result

# ---------------------------------------------------------
# VICTORY CONDITIONS
# ---------------------------------------------------------
func _check_systemic_collapse():
	if _victory_locked:
		return

	var all_dead: bool = oligarchs.size() > 0
	for o in oligarchs:
		if o.alive:
			all_dead = false
			break

	if all_dead:
		_fire_victory("DIRECT_ACTION",
			"DIRECT ACTION",
			"All oligarchs eliminated. The Enclave falls. A new order writes itself.")
		return

	if int(global_economy.get("public_tension", 0)) >= 100:
		_fire_victory("POLITICAL_REVOLUTION",
			"POLITICAL REVOLUTION",
			"Tension hits 100. The masses storm The Enclave. The NetFeed goes silent.")
		return

	if int(global_economy.get("senate_alignment", 50)) <= 0:
		_fire_victory("POLITICAL_REFORM",
			"POLITICAL REFORM",
			"Senate alignment collapses. Corporate charters dissolved by vote.")
		return

	var total_wealth: int = 0
	for o in oligarchs:
		total_wealth += o.wealth
	if total_wealth < 100000 and oligarchs.size() > 0:
		_fire_victory("SYSTEMIC_COLLAPSE",
			"SYSTEMIC COLLAPSE",
			"Combined oligarch wealth collapses below survival. The Enclave is bankrupt.")
		return


func _fire_victory(kind: String, title: String, flavor: String) -> void:
	_victory_locked = true
	print("VICTORY: [%s] %s — %s" % [kind, title, flavor])
	victory_achieved.emit(kind, title, flavor)
