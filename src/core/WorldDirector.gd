extends Node

# The core brain of the "Butterfly Effect" system.
# This singleton manages the global economy, Oligarch statuses, and event ripples.

# ---------------------------------------------------------
# SIGNALS
# ---------------------------------------------------------
signal event_triggered(action_id: String, target: String)
signal world_state_changed()
signal netfeed_event_generated(event_data: Dictionary)

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
# SECTOR STATE
# ---------------------------------------------------------
var sectors = {
	"The Sinks": {"security_modifier": -20, "tension_modifier": +10, "unlocked": true},
	"The Neon Docks": {"security_modifier": -10, "tension_modifier": +5, "unlocked": true},
	"Subterranean Farms": {"security_modifier": 0, "tension_modifier": 0, "unlocked": false},
	"Corporate Spire": {"security_modifier": +40, "tension_modifier": -20, "unlocked": false}
}
var current_sector: String = "The Sinks"

# ---------------------------------------------------------
# OLIGARCH STATE (ACTORS)
# ---------------------------------------------------------
var oligarchs = {
	"Food": {"alive": true, "wealth": 1000000, "paranoia": 10, "public_image": 10, "controversy_level": 5, "recent_scandals": []},
	"Tech": {"alive": true, "wealth": 2500000, "paranoia": 20, "public_image": 50, "controversy_level": 10, "recent_scandals": []},
	"Security": {"alive": true, "wealth": 500000, "paranoia": 50, "public_image": -20, "controversy_level": 40, "recent_scandals": []},
	"Media": {"alive": true, "wealth": 800000, "paranoia": 5, "public_image": 30, "controversy_level": 0, "recent_scandals": []}
}

func _ready():
	print("WorldDirector initialized. Economy online.")

# ---------------------------------------------------------
# EVENT HANDLING (The Butterfly Effect)
# ---------------------------------------------------------
func trigger_event(action_id: String, target: String = ""):
	print("World Event Triggered: ", action_id, " on ", target)
	event_triggered.emit(action_id, target)
	
	match action_id:
		"sabotage_facility":
			if target == "Food":
				_ripple_food_sabotage()
		"assassinate_oligarch":
			_ripple_assassination(target)
		"hack_grid":
			_ripple_grid_hack()
		"exert_political_pressure":
			_ripple_political_pressure(target)
		"travel":
			_travel_to_sector(target)
		"leak_scandal":
			_ripple_leak_scandal(target)
		"procedural_gaffe":
			_ripple_procedural_gaffe(target)
			
	# Dynamic Evolution
	_update_sector_dynamics()
	
	# Notify UI and other listeners
	world_state_changed.emit()
	
	# Check victory conditions after every major event
	_check_systemic_collapse()

# --- Specific Ripple Logic ---

func _ripple_food_sabotage():
	oligarchs["Food"]["wealth"] -= 50000
	global_economy["food_price"] += 200
	global_economy["public_tension"] += 15
	oligarchs["Security"]["paranoia"] += 20
	global_economy["security_presence"] += 10
	print("Ripple Effect: Food prices skyrocket. Public tension rises. Security increases patrols.")

func _ripple_assassination(target_oligarch: String):
	if oligarchs.has(target_oligarch):
		oligarchs[target_oligarch]["alive"] = false
		global_economy["public_tension"] += 40
		print("Ripple Effect: ", target_oligarch, " Oligarch eliminated. Power vacuum created.")
		
		# If Media is killed, tension rises faster because propaganda stops
		if target_oligarch == "Media":
			print("Without propaganda, all Oligarchs suffer massive controversy spikes.")
			for key in oligarchs.keys():
				if oligarchs[key]["alive"]:
					oligarchs[key]["controversy_level"] = 100

func _ripple_grid_hack():
	oligarchs["Tech"]["wealth"] -= 10000
	global_economy["security_presence"] -= 20 # Cameras go down
	print("Ripple Effect: Grid hacked. Security blinded temporarily.")

func _ripple_political_pressure(target_faction: String):
	# Target can be "Enclave" or "Sinks"
	if target_faction == "Sinks":
		global_economy["senate_alignment"] -= 10
		global_economy["public_tension"] -= 5 # People feel heard
		oligarchs["Media"]["paranoia"] += 10
		print("Ripple Effect: Political pressure favors the Sinks. Senate shifts away from Enclave control.")
	elif target_faction == "Enclave":
		global_economy["senate_alignment"] += 10
		global_economy["security_presence"] += 5
		print("Ripple Effect: Corporate lobbying succeeds. Senate tightens grip on the Sinks.")

# ---------------------------------------------------------
# PR & REPUTATION ENGINE & THE NETFEED
# ---------------------------------------------------------
func trigger_news_cycle():
	print("--- DAILY NEWS CYCLE (NETFEED REFRESH) ---")
	
	# Ask the LLM to evaluate the complex conjecture of world variables
	# and generate a stream of events.
	if has_node("/root/LLMManager"):
		var llm = get_node("/root/LLMManager")
		if not llm.netfeed_stream_received.is_connected(_on_netfeed_stream_received):
			llm.netfeed_stream_received.connect(_on_netfeed_stream_received)
		
		llm.request_netfeed_events(global_economy, oligarchs)
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
			print("    Systemic Impact: " + event.get("systemic_impact", ""))
		elif event_type == "SILENT_RIPPLE":
			print(">>> [INVISIBLE SHIFT] " + event.get("systemic_impact", ""))
		
		# A full implementation would parse systemic_impact to apply numerical changes.
		# For prototype, we generate the narrative stream and invisible shifts as the user requested.

# --- Manual Fallback / Legacy PR Triggers ---
func _generate_consequence_event():
	# Generate an event based on current world pressures
	var event = {"type": "CONSEQUENCE", "headline": "", "timestamp": Time.get_unix_time_from_system()}
	
	if global_economy["food_price"] > 250:
		event["headline"] = "Sinks food riots leave 34 dead. Food Oligarch claims 'supply chain issues'."
		oligarchs["Food"]["public_image"] -= 10
		oligarchs["Food"]["controversy_level"] += 20
	elif global_economy["public_tension"] > 70:
		event["headline"] = "Enforcer union threatens strike amidst rising civilian hostilities."
		global_economy["security_presence"] -= 15
	else:
		# Default procedural gaffe
		event["headline"] = "Tech Oligarch caught on hot mic: 'Humanity shouldn't endure.'"
		trigger_event("procedural_gaffe", "Tech")
		
	if event["headline"] != "":
		netfeed_history.append(event)
		netfeed_event_generated.emit(event)
		print(">>> NETFEED CONSEQUENCE: ", event["headline"])

func _ripple_leak_scandal(target_actor: String):
	if oligarchs.has(target_actor):
		oligarchs[target_actor]["public_image"] = clamp(oligarchs[target_actor]["public_image"] - 30, -100, 100)
		oligarchs[target_actor]["controversy_level"] = clamp(oligarchs[target_actor]["controversy_level"] + 50, 0, 100)
		oligarchs[target_actor]["recent_scandals"].append("Player leaked classified datashard.")
		print("Ripple Effect: Massive scandal hits ", target_actor, ". Public image tanks.")
		
		if target_actor == "Food":
			global_economy["food_price"] -= 50 # Try to buy favor
			global_economy["security_presence"] += 20 # Double patrols
			print("Food Oligarch drops prices to buy favor, but doubles security patrols.")

func _ripple_procedural_gaffe(target_actor: String):
	if oligarchs.has(target_actor):
		oligarchs[target_actor]["public_image"] = clamp(oligarchs[target_actor]["public_image"] - 40, -100, 100)
		oligarchs[target_actor]["controversy_level"] = clamp(oligarchs[target_actor]["controversy_level"] + 40, 0, 100)
		var gaffe = "Said humanity shouldn't endure."
		oligarchs[target_actor]["recent_scandals"].append(gaffe)
		print("Ripple Effect: ", target_actor, " caught on mic: '", gaffe, "'")
		
		if target_actor == "Tech":
			oligarchs["Tech"]["wealth"] -= 200000 # Stock crash
			global_economy["public_tension"] += 25
			print("Tech stocks crash. Riots break out against Tech infrastructure.")

func _travel_to_sector(target_sector: String):
	if sectors.has(target_sector) and sectors[target_sector]["unlocked"]:
		current_sector = target_sector
		print("Player traveled to: ", current_sector)
		# Sector dynamics temporarily modify the global economy feel
		var local_security = max(0, global_economy["security_presence"] + sectors[current_sector]["security_modifier"])
		print("Local Security Presence is now: ", local_security)
	else:
		print("Travel denied. Sector locked or invalid.")

func _update_sector_dynamics():
	# Modifiers evolve based on the current state of the global economy
	
	# Sinks: If food is too expensive, tension explodes locally
	if global_economy["food_price"] > 300:
		sectors["The Sinks"]["tension_modifier"] = 40
	else:
		sectors["The Sinks"]["tension_modifier"] = 10
		
	# Docks: If security presence is low, Docks become less secure (black market thrives)
	if global_economy["security_presence"] < 30:
		sectors["The Neon Docks"]["security_modifier"] = -30
	else:
		sectors["The Neon Docks"]["security_modifier"] = -10
		
	# Spire: If senate is reformist (Pro-Sinks), Corporate Spire security tightens locally
	if global_economy["senate_alignment"] < 30:
		sectors["Corporate Spire"]["security_modifier"] = 60
	else:
		sectors["Corporate Spire"]["security_modifier"] = 40

	print("Sector dynamics updated based on world evolution.")

# ---------------------------------------------------------
# VICTORY CONDITIONS
# ---------------------------------------------------------
func _check_systemic_collapse():
	# Example condition: If all oligarchs are dead
	var all_dead = true
	for key in oligarchs.keys():
		if oligarchs[key]["alive"]:
			all_dead = false
			break
			
	if all_dead:
		print("VICTORY TRIGGERED: Direct Action (Assassination). The Enclave falls.")
		
	if global_economy["public_tension"] >= 100:
		print("VICTORY TRIGGERED: Political Revolution. The masses storm The Enclave.")
		
	if global_economy["senate_alignment"] <= 0:
		print("VICTORY TRIGGERED: Political Reform. The Senate dissolves corporate charters. A peaceful transition of power.")
