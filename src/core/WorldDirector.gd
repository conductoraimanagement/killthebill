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
# Run-start generation progress — fires at each async step so the HUD
# loading overlay can update its bar + phase label live.
signal generation_progress(pct: int, phase: String)

# Flips true the first time a victory condition hits; prevents repeat fires
# until the scene is reloaded / playthrough reinitialized.
var _victory_locked: bool = false

# One-shot warning flag — emits a NetFeed headline the first time the
# player's heat is driven up by hostile NPCs alone (no active action).
# Reset in initialize_playthrough.
var _snitch_warning_fired: bool = false

# ---------------------------------------------------------
# NETFEED (The Internet/Communication Array)
# ---------------------------------------------------------
var netfeed_history = [] # Stores { "type": String, "headline": String, "timestamp": int }

# Continuous NetFeed: the LLM returns a batch (~6-10 events) per cycle;
# we queue them and drip one to the HUD every NETFEED_DRIP_SECONDS so
# the feed streams continuously instead of lurching per phase. When
# the queue runs low (< 2), we optimistically pull the next batch.
var _netfeed_queue: Array[Dictionary] = []
var _netfeed_drip_timer: Timer
const NETFEED_DRIP_SECONDS: float = 30.0
const NETFEED_QUEUE_REFILL_THRESHOLD: int = 2
var _netfeed_request_in_flight: bool = false

# Debug toggle — while true, SILENT_RIPPLE events (impact-only, no
# headline) get a synthesized debug line in the NetFeed so we can see
# what the sim is doing under the hood. Flip to false to hide them.
const DEBUG_SHOW_SILENT_RIPPLES: bool = true

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

# ---------------------------------------------------------
# JOB BOARD — rival oligarch contracts + NPC fixer jobs
# (See docs/04-player/progression.md income mechanisms 3 & 4)
# ---------------------------------------------------------
signal job_posted(job: Dictionary)
signal job_completed(job: Dictionary)
signal job_expired(job: Dictionary)

var active_jobs: Array[Dictionary] = []
var _next_job_index: int = 0
const MAX_ACTIVE_JOBS := 3
const JOB_TTL_CYCLES := 3

func _ready():
	print("WorldDirector initialized. Economy online.")


# Godot 4.6 removed the Array(arr, TYPE_STRING, &"", null) 4-arg
# constructor. Also: LLMs (DeepSeek in particular) sometimes return a
# field as a single String when the prompt asked for an array. This
# helper handles both: accepts Array OR String, returns Array[String].
# Strings are split on ';' or newline — plausible cases when the model
# concatenates list items.
static func _coerce_string_array(value) -> Array[String]:
	var out: Array[String] = []
	if value == null:
		return out
	match typeof(value):
		TYPE_ARRAY:
			for item in value:
				out.append(str(item))
		TYPE_STRING:
			var raw_str: String = str(value)
			# Try semicolon split first, then newline — pick whichever
			# yields multiple non-empty pieces.
			var parts_semi: PackedStringArray = raw_str.split(";", false)
			var parts_newline: PackedStringArray = raw_str.split("\n", false)
			var chosen: PackedStringArray = parts_semi if parts_semi.size() >= parts_newline.size() else parts_newline
			if chosen.size() == 0:
				chosen = [raw_str]
			for part in chosen:
				var clean: String = part.strip_edges()
				if clean != "":
					out.append(clean)
	return out

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
	_snitch_warning_fired = false
	if has_node("/root/LLMManager"):
		get_node("/root/LLMManager").reset_usage_totals()
	# Don't wipe current_region — Main.gd sets it before calling us.

	if has_node("/root/SenateDirector"):
		var senate = get_node("/root/SenateDirector")
		senate.active_bill = {}
		senate.bill_history.clear()
		senate.politicians = []

	# Fresh player state (credits, heat, playstyle trackers).
	if has_node("/root/PlayerManager"):
		get_node("/root/PlayerManager").initialize_run()

	# Fresh cameo trigger state — new playthrough, all cameos eligible again.
	if has_node("/root/CulturalCameos"):
		get_node("/root/CulturalCameos").reset()

	# Fresh chronicle — clear prior-run recaps and snapshot starting state.
	if has_node("/root/Chronicle"):
		get_node("/root/Chronicle").reset()

	# If the user loaded a saved world config, inject it directly and skip
	# LLM generation entirely. Otherwise fall through to the async generator
	# chain that hits LLMManager (with offline fallback).
	if not preloaded_config.is_empty():
		_apply_preloaded_config(preloaded_config)
		return

	generation_progress.emit(5, "> generating world geography…")
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

	generation_progress.emit(20, "> regions seeded — requesting oligarchs…")
	# 2. Oligarchs (Asynchronous)
	_generate_oligarchs_async()

func _generate_oligarchs_async() -> void:
	if has_node("/root/LLMManager"):
		var llm = get_node("/root/LLMManager")
		if not llm.oligarchs_generated.is_connected(_on_oligarchs_generated):
			llm.oligarchs_generated.connect(_on_oligarchs_generated)
		
		# Minimum 5 so the guaranteed 2 AI + 2 Tech still leaves room for
		# at least one non-AI / non-Tech oligarch (Food / Finance / etc.).
		var count = randi_range(5, 7)
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
		o.title = o_data.get("title", "Founder & CEO")
		o.sector_of_influence = o_data.get("sector", "Various")
		# company_name is the made-up corporate brand the oligarch founded.
		# Fall back to a synthetic "<LastName> Holdings" if the generator
		# (old save, partial LLM response) didn't supply one — never use
		# the raw sector as a company name.
		var supplied_company: String = str(o_data.get("company_name", ""))
		if supplied_company.is_empty():
			supplied_company = "%s Holdings" % str(o_data.get("last_name", "Unknown"))
		o.company_name = supplied_company
		o.ambitions = _coerce_string_array(o_data.get("ambitions", []))
		o.quirks = _coerce_string_array(o_data.get("quirks", []))
		
		# Intrinsic traits. Default is random per run, but alter-ego mode
		# (and any LLM response that supplies a 'traits' dict) can pin
		# specific values so the archetype lands — a Musk-alter-ego is
		# always vain + intelligent, a Thiel-alter-ego is always paranoid.
		var trait_overrides: Dictionary = o_data.get("traits", {}) if typeof(o_data.get("traits", null)) == TYPE_DICTIONARY else {}
		o.ruthlessness = clamp(float(trait_overrides.get("ruthlessness", randf())), 0.0, 1.0)
		o.vanity = clamp(float(trait_overrides.get("vanity", randf())), 0.0, 1.0)
		o.paranoia_base = clamp(float(trait_overrides.get("paranoia_base", randf())), 0.0, 1.0)
		o.intelligence = clamp(float(trait_overrides.get("intelligence", randf())), 0.0, 1.0)
		o.greed = clamp(float(trait_overrides.get("greed", randf())), 0.0, 1.0)
		o.ideology = clamp(float(trait_overrides.get("ideology", randf())), 0.0, 1.0)
		
		# Starting state
		o.wealth = randi_range(500000, 3000000)
		o.paranoia = o.paranoia_base * 30.0
		o.public_image = randf_range(-20.0, 50.0)
		
		# Initialize ambitions progress
		for ambition in o.ambitions:
			o.ambition_progress[ambition] = 0.0
			
		oligarchs.append(o)
		print("  - %s — %s of %s [%s]" % [o.oligarch_name, o.title, o.company_name, o.sector_of_influence])

	# 3. Assign territories
	if has_node("/root/RegionGenerator"):
		_assign_oligarch_territories(get_node("/root/RegionGenerator"))

	# 3b. Attribute player debt to a Finance oligarch if one exists.
	# Thematic: Blue Collar's starting -200 cr is owed to someone specific.
	if has_node("/root/PlayerManager"):
		var pm_debt = get_node("/root/PlayerManager")
		for o in oligarchs:
			if o.sector_of_influence == "Finance" and o.alive:
				pm_debt.debt_held_by_oligarch_id = o.oligarch_id
				break
	
	generation_progress.emit(40, "> oligarchs named — populating the city…")
	# 4. NPC roster (Asynchronous)
	if has_node("/root/PopulationDirector"):
		var pop_dir = get_node("/root/PopulationDirector")
		if not pop_dir.population_generated.is_connected(_on_population_generated):
			pop_dir.population_generated.connect(_on_population_generated)
		pop_dir.generate_new_roster()
	else:
		_finish_setup()

func _on_population_generated() -> void:
	generation_progress.emit(60, "> citizens seeded — assembling the senate…")
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
		p.quirks = _coerce_string_array(p_data.get("quirks", []))

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

	generation_progress.emit(80, "> senate sworn in — building the region…")
	_finish_setup()

func _finish_setup() -> void:
	# Hook TimeSystem signals (once per process lifetime; safe to re-check)
	if has_node("/root/TimeSystem"):
		var ts = get_node("/root/TimeSystem")
		if not ts.day_advanced.is_connected(_on_day_advanced):
			ts.day_advanced.connect(_on_day_advanced)
		if not ts.phase_changed.is_connected(_on_phase_changed):
			ts.phase_changed.connect(_on_phase_changed)
		if not ts.year_ended.is_connected(_on_year_ended):
			ts.year_ended.connect(_on_year_ended)
		if not ts.payday.is_connected(_on_payday):
			ts.payday.connect(_on_payday)
		if not ts.rent_due.is_connected(_on_rent_due):
			ts.rent_due.connect(_on_rent_due)
		ts.reset()
		ts.start()

	# NetFeed drip timer — emits one queued event every N seconds so the
	# feed streams continuously. First batch request happens immediately.
	if _netfeed_drip_timer == null:
		_netfeed_drip_timer = Timer.new()
		_netfeed_drip_timer.name = "NetFeedDripTimer"
		_netfeed_drip_timer.wait_time = NETFEED_DRIP_SECONDS
		_netfeed_drip_timer.autostart = false
		_netfeed_drip_timer.one_shot = false
		add_child(_netfeed_drip_timer)
		_netfeed_drip_timer.timeout.connect(_on_netfeed_drip)
	_netfeed_drip_timer.start()

	# Emit setup-complete BEFORE firing the first news cycle. If the
	# news-cycle build ever errors, we still want Main to spawn the
	# landscape and let the player into the world.
	playthrough_setup_complete.emit()
	print("WorldDirector: Playthrough setup complete.")

	# Kick a first batch so the feed isn't empty at run-start.
	trigger_news_cycle()


func _on_day_advanced(_day: int) -> void:
	# Full world simulation tick happens once per day.
	run_world_cycle()


func _on_phase_changed(_phase: int) -> void:
	# NetFeed + job board refresh on each phase boundary (3x per day).
	trigger_news_cycle()


func _on_payday(_day: int) -> void:
	# Weekly wage deposit. PlayerManager does its own no-op if there's
	# nothing pending.
	if has_node("/root/PlayerManager"):
		get_node("/root/PlayerManager").apply_weekly_payday()


func _on_rent_due(_month: int) -> void:
	# Month rollover — landlord wants rent. PlayerManager raises its
	# modal signal for the HUD to catch.
	if has_node("/root/PlayerManager"):
		get_node("/root/PlayerManager").handle_rent_due()


func _on_year_ended() -> void:
	# 13 months passed without a victory condition firing. Run ends
	# with a timeout defeat — the Enclave absorbed the player without
	# needing to act against them.
	if _victory_locked:
		return
	if has_node("/root/PlayerManager"):
		get_node("/root/PlayerManager").fire_defeat(
			"TIMEOUT_ABSORBED",
			"YEAR'S END",
			"Thirteen months passed. No oligarch fell by your hand. No revolution took the streets. No reform passed the chamber. No collapse bent the Enclave's balance sheet. The year ended. The year absorbed you."
		)


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
	# Link oligarchs to regions matching their sector type.
	# Multiple oligarchs can share a sector now, so this is best-effort:
	# assigns to first open slot of the matching region type, skipping
	# if no region exists (the Enclave doesn't HAVE to have e.g. an
	# Island for the Food oligarchs).
	for o in oligarchs:
		match o.sector_of_influence:
			"Food":
				_try_assign_to_first_region(region_gen, "AGRICULTURAL", o)
			"Military":
				_try_assign_to_first_region(region_gen, "TRANSIT", o)
			"Tech", "Pharma", "Energy":
				_try_assign_to_first_region(region_gen, "INDUSTRIAL", o)
			"Media", "Finance", "AI":
				_try_assign_to_first_region(region_gen, "URBAN_ELITE", o)


func _try_assign_to_first_region(region_gen, type_key: String, o) -> void:
	var regions: Array = region_gen.get_regions_by_type(type_key)
	for region in regions:
		if region.get("connected_oligarch", "") == "":
			region["connected_oligarch"] = o.oligarch_id
			return
	# No open region of this type — oligarch has no formal territory
	# this run. Works abstractly (they still exist in the economy).

# =============================================================
# WORLD CYCLE — Called each tick to evolve everything
# =============================================================

func run_world_cycle() -> void:
	cycle += 1

	# Passive heat decay — multiplier drops in Climactic + Year's End bands.
	if has_node("/root/PlayerManager"):
		var pm = get_node("/root/PlayerManager")
		var decay: int = 1
		if has_node("/root/TimeSystem"):
			decay = max(0, int(round(1.0 * get_node("/root/TimeSystem").heat_decay_multiplier())))
		if decay > 0:
			pm.cool_heat(decay)
		# Daily survival tick — rent/food drain, hope decay, eviction,
		# despair-defeat check. See docs/04-player/progression.md.
		pm.apply_daily_tick(global_economy)

	# NPC mortality — accident + murder rolls for every alive NPC.
	if has_node("/root/PopulationDirector"):
		var pd = get_node("/root/PopulationDirector")
		pd.evaluate_deaths(global_economy, cycle)
		# Random NPC-NPC pair interactions — mood contagion, radicalization
		# spread, opinion-of-player diffusion, occasional romance. The
		# social graph lives independently of the player.
		pd.tick_social_graph(cycle)
		# Romantic partners discover each other — trait-driven reactions.
		pd.evaluate_infidelity_discoveries(cycle)

	# Year-arc ambient tension drift — the world tightens around you.
	if has_node("/root/TimeSystem"):
		var drift: int = int(get_node("/root/TimeSystem").tension_drift_per_cycle())
		if drift != 0:
			global_economy["public_tension"] = clamp(
				int(global_economy.get("public_tension", 0)) + drift, 0, 100)

	_expire_jobs()

	# Tick active cultural-cameo arcs once per day — apply while-active
	# modifiers and decrement TTLs.
	if has_node("/root/CulturalCameos"):
		get_node("/root/CulturalCameos").tick_daily()

	_apply_social_pressure()
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

# Hostile NPCs (knowledge>0.5, opinion<-0.3) passively drip heat onto
# the player each day cycle; allies (trust>60, opinion>0.3) drip it back.
# Only NPCs active in the current phase count — night-only fixers you
# wronged can't snitch at noon. See docs/04-player/heat.md.
func _apply_social_pressure() -> void:
	if not has_node("/root/PopulationDirector") or not has_node("/root/PlayerManager"):
		return
	var pop_dir = get_node("/root/PopulationDirector")
	var pm = get_node("/root/PlayerManager")
	var ts = get_node_or_null("/root/TimeSystem")
	var is_night_now: bool = false
	if ts:
		is_night_now = ts.is_night()

	var hostile_count: int = 0
	var ally_count: int = 0
	for n in pop_dir.roster:
		if not n.alive:
			continue
		var phase: String = str(n.active_phase) if n.active_phase else "both"
		var active_now: bool = phase == "both" \
			or (phase == "day" and not is_night_now) \
			or (phase == "night" and is_night_now)
		if not active_now:
			continue
		if n.is_hostile_to_player():
			hostile_count += 1
		elif n.is_ally_to_player():
			ally_count += 1

	var net_heat: int = hostile_count - int(float(ally_count) * 0.5)
	if net_heat != 0:
		pm.add_heat(net_heat, "neighborhood disposition")

	if hostile_count >= 2 and not _snitch_warning_fired:
		_snitch_warning_fired = true
		var event := {
			"type": "NEWS_TICKER",
			"headline": "A neighborhood is watching you. Their quiet is reporting.",
			"timestamp": Time.get_unix_time_from_system(),
		}
		netfeed_history.append(event)
		netfeed_event_generated.emit(event)


func _evolve_oligarchs() -> void:
	for o in oligarchs:
		var actions = o.process_world_state(global_economy, oligarchs, cycle)
		for action in actions:
			_apply_oligarch_action(action)
			oligarch_action_taken.emit(action)

		# Check for stagnant ambitions. If any get swapped, NetFeed flags it.
		var swaps: Array = o.reevaluate_ambitions(cycle)
		for swap in swaps:
			var from_txt: String = str(swap.get("from", ""))
			var to_txt: String = str(swap.get("to", ""))
			if from_txt == "" or to_txt == "":
				continue
			var event := {
				"type": "NEWS_TICKER",
				"headline": "%s quietly shifts strategy — analysts note the abandoned '%s' and a new focus on '%s'." % [
					o.oligarch_name, from_txt, to_txt,
				],
				"timestamp": Time.get_unix_time_from_system(),
			}
			netfeed_history.append(event)
			netfeed_event_generated.emit(event)

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
		"sell_scandal":
			_ripple_sell_scandal(target)
		"bribe_politician":
			# target format: "politician_id|direction" where direction is "YES" or "NO"
			var parts: PackedStringArray = target.split("|")
			if parts.size() == 2:
				_ripple_bribe_politician(parts[0], parts[1])
	
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
	elif target_sector == "Finance":
		# Credit freeze — prices rise, rent drain spikes, tension jumps.
		global_economy["food_price"] += 30
		global_economy["tech_price"] += 30
		if has_node("/root/PlayerManager"):
			get_node("/root/PlayerManager").apply_finance_shock()
	elif target_sector == "AI":
		# A training-cluster hit cripples the Compliance AI's pattern
		# matching for a stretch — surveillance goes partially blind.
		# Net effect: security_presence DROPS (rare — this is the one
		# sector whose sabotage reduces enforcer saturation), tech_price
		# spikes (GPUs + training data go scarce).
		global_economy["tech_price"] += 40
		global_economy["security_presence"] = clamp(
			global_economy["security_presence"] - 15, 0, 100)
	if target_sector != "AI":
		# Non-AI sabotage always bumps security saturation (Enforcers
		# respond). AI sabotage is the exception — handled above.
		global_economy["security_presence"] = clamp(
			global_economy["security_presence"] + 10, 0, 100)
	global_economy["public_tension"] = clamp(
		global_economy["public_tension"] + (20 if target_sector == "Finance" else 15), 0, 100)
	print("Ripple: %s sector sabotaged. Prices spike, tension rises." % target_sector)

	var headline: String = _sabotage_headline(target_sector)
	var event := {
		"type": "NEWS_TICKER",
		"headline": headline,
		"timestamp": Time.get_unix_time_from_system(),
	}
	netfeed_history.append(event)
	netfeed_event_generated.emit(event)

	# Loot & heat — see docs/04-player/progression.md (income mechanism #1).
	# Heat threshold: above 60, your haste halves the loot you can carry.
	if has_node("/root/PlayerManager"):
		var pm = get_node("/root/PlayerManager")
		var loot: int = _sabotage_loot_for(target_sector)
		if pm.heat > 60:
			loot = int(loot * 0.5)
		var base_heat: int = _sabotage_heat_for(target_sector)
		var heat_amt: int = pm.compute_heat_cost(base_heat, {"method": "sabotage"})
		pm.add_credits(loot, "sabotage loot: %s" % target_sector)
		pm.add_heat(heat_amt, "sabotage: %s" % target_sector)
		pm.bump_playstyle(0.08, 0.02, 0.0, 0.0)
		pm.add_hope(3.0, "sabotage landed")   # you hit back

	_check_jobs_match("sabotage_sector", target_sector)
	if has_node("/root/CulturalCameos"):
		get_node("/root/CulturalCameos").check_action_match("sabotage_sector", target_sector)


func _sabotage_loot_for(sector: String) -> int:
	match sector:
		"Food":     return randi_range(300, 600)
		"Tech":     return randi_range(500, 900)
		"Pharma":   return randi_range(600, 1000)
		"Energy":   return randi_range(400, 700)
		"Military": return randi_range(200, 400)
		"Media":    return randi_range(200, 500)
		"Finance":  return randi_range(800, 1400)   # a vault hit is a vault hit
		"AI":       return randi_range(700, 1200)   # GPU racks resell on the black market
	return 250


func _sabotage_heat_for(sector: String) -> int:
	match sector:
		"Food":     return 3
		"Tech":     return 4
		"Pharma":   return 4
		"Energy":   return 3
		"Military": return 5
		"Media":    return 2
		"Finance":  return 6                        # the grid notices everything
		"AI":       return 7                        # the Compliance AI itself goes looking
	return 3


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
		"Military":
			return "Checkpoint near %s breached overnight. Patrols redeployed." % region_tag
		"Media":
			return "%s media spire goes dark for 18 minutes. No statement issued." % region_tag
		"Finance":
			return "%s clearing house hit overnight. Credit markets froze for 91 minutes. The feed is careful with numbers." % region_tag
		"AI":
			return "%s training cluster taken offline. Compliance AI's arrest-rate dropped 40%% for 96 hours. The board is not returning calls." % region_tag
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
	# The player's biggest one-shot payout. Hitting the financial grid
	# siphons credits from the Finance oligarch's holdings (they own the
	# clearing-house). Falls back to Tech if no Finance oligarch rolled
	# this run. See docs/04-player/progression.md income mechanism #6.
	var target_oligarch: OligarchData = null
	for o in oligarchs:
		if o.sector_of_influence == "Finance" and o.alive:
			target_oligarch = o
			break
	if target_oligarch == null:
		for o in oligarchs:
			if o.sector_of_influence == "Tech" and o.alive:
				target_oligarch = o
				break

	var payout: int = randi_range(1500, 3000)

	if target_oligarch:
		target_oligarch.wealth = max(0, target_oligarch.wealth - 15000)
		target_oligarch.paranoia = clamp(target_oligarch.paranoia + 30.0, 0.0, 100.0)
		target_oligarch.awareness_of_player = clamp(target_oligarch.awareness_of_player + 25.0, 0.0, 100.0)

	global_economy["security_presence"] = clamp(global_economy["security_presence"] - 20, 0, 100)

	if has_node("/root/PlayerManager"):
		var pm = get_node("/root/PlayerManager")
		pm.add_credits(payout, "grid hack")
		# Digital act — darkness and empty streets don't help hide packet
		# flow, but covering tracks (stealth) still reduces the trail.
		pm.add_heat(pm.compute_heat_cost(8, {"method": "hack", "digital": true}), "grid hack")
		pm.bump_playstyle(0.06, 0.04, 0.0, 0.15)  # chaos + stealth
		pm.add_hope(4.0, "hit the grid")     # big payoff, feels like a blow

	var event := {
		"type": "NEWS_TICKER",
		"headline": "Financial grid breached overnight. Unusual asset movement reported in the Tech sector. Investigation 'ongoing'.",
		"timestamp": Time.get_unix_time_from_system(),
	}
	netfeed_history.append(event)
	netfeed_event_generated.emit(event)

	print("Ripple: Grid hacked. Siphoned %d credits; security -20; Tech oligarch paranoia spiked." % payout)

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

			if has_node("/root/PlayerManager"):
				var pm_leak = get_node("/root/PlayerManager")
				pm_leak.bump_playstyle(0.05, 0.0, 0.1, 0.02)
				pm_leak.add_hope(2.0, "leak hit home")

			_check_jobs_match("leak_oligarch", target_id)
			if has_node("/root/CulturalCameos"):
				var cameos = get_node("/root/CulturalCameos")
				cameos.check_action_match("leak_oligarch", target_id)
				cameos.check_action_match("leak_sector", o.sector_of_influence)
			break


# See progression.md, income mechanism #2 — sell scandal to Media oligarch.
# Corrupt option: payout now, but suppresses the leak and shifts the senate
# pro-Enclave. Heat +2. Playstyle ruthlessness bump.
func _ripple_sell_scandal(target_id: String):
	var target: OligarchData = null
	var media: OligarchData = null
	for o in oligarchs:
		if o.oligarch_id == target_id and o.alive:
			target = o
		if o.sector_of_influence == "Media" and o.alive:
			media = o
	if target == null:
		return

	var payout: int = 500 + int(target.controversy_level * 30)
	if media != null:
		payout += 1000

	target.controversy_level = clamp(target.controversy_level - 20, 0, 100)
	global_economy["senate_alignment"] = clamp(
		global_economy["senate_alignment"] + 5, 0, 100)

	var silent_event := {
		"type": "SILENT_RIPPLE",
		"headline": "",
		"systemic_impact": "scandal on %s suppressed; Media consolidates leverage" % target.oligarch_name,
		"timestamp": Time.get_unix_time_from_system(),
	}
	netfeed_history.append(silent_event)
	netfeed_event_generated.emit(silent_event)

	if has_node("/root/PlayerManager"):
		var pm = get_node("/root/PlayerManager")
		pm.add_credits(payout, "scandal sold to Media")
		pm.add_heat(pm.compute_heat_cost(2, {"method": "sell_scandal"}), "dealing in stolen info")
		pm.bump_playstyle(0.0, 0.08, 0.0, 0.04)
		pm.add_hope(-2.0, "you compromised")    # corrupt act eats hope

	print("Ripple: Sold dirt on %s for %d credits. Senate shifts pro-Enclave." % [
		target.oligarch_name, payout,
	])


# See progression.md, spending mechanism — bribe a politician on the active bill.
# direction: "YES" or "NO" — the stance the player paid for.
func _ripple_bribe_politician(politician_id: String, direction: String) -> void:
	var p: PoliticianData = null
	for pol in politicians:
		if pol.politician_id == politician_id:
			p = pol
			break
	if p == null or not p.alive:
		return

	if not has_node("/root/PlayerManager"):
		return
	var pm = get_node("/root/PlayerManager")
	var cost: int = effective_bribe_cost(p)
	if not pm.spend_credits(cost, "bribe: %s" % p.politician_name):
		return

	# Set the pending direction that PoliticianData.evaluate_bill reads on
	# the next tally. Heavier pull than ambient player_leverage.
	p.pending_bribe_direction = 1.0 if direction == "YES" else -1.0
	p.player_leverage = min(100.0, p.player_leverage + 20.0)

	pm.add_heat(pm.compute_heat_cost(2, {"method": "bribe_politician"}), "bribery")
	pm.bump_playstyle(0.0, 0.05, 0.0, 0.03)
	pm.add_hope(-1.0, "compromised a senator")

	# Most real bribes go unreported — roll for a leak. About 1 in 3
	# bumps up as a SILENT_RIPPLE (off-screen scandal seed); the rest
	# fire a proper NetFeed line, which also nudges the politician's
	# scandal level.
	var leaked_publicly: bool = randf() > 0.33
	var bribe_line: String = "Records leaked overnight suggest a single operative paid %s for a %s vote on the bill in debate. The sum was not disclosed. %s's office 'strongly denies' any arrangement." % [
		p.politician_name, direction, p.politician_name.split(" ")[-1],
	]
	var bribe_event: Dictionary = {}
	if leaked_publicly:
		bribe_event = {
			"type": "NEWS_TICKER",
			"headline": bribe_line,
			"timestamp": Time.get_unix_time_from_system(),
		}
	else:
		# Debug-visible ripple: attach an impact dict so the debug
		# formatter surfaces it in the feed while DEBUG_SHOW_SILENT_RIPPLES
		# is on. The scandal bump below would fire anyway; this just
		# makes it readable.
		var ripple_headline: String = ""
		if DEBUG_SHOW_SILENT_RIPPLES:
			ripple_headline = "[color=#888][DEBUG • silent ripple][/color] player bribe · %s.scandal +6 (unleaked)" % p.politician_name
		bribe_event = {
			"type": "SILENT_RIPPLE" if not DEBUG_SHOW_SILENT_RIPPLES else "NEWS_TICKER",
			"headline": ripple_headline,
			"timestamp": Time.get_unix_time_from_system(),
		}
	netfeed_history.append(bribe_event)
	netfeed_event_generated.emit(bribe_event)
	# Scandal + controversy shift on the politician regardless — the
	# world moves whether or not the public saw it.
	p.scandal_level = clamp(p.scandal_level + 6.0, 0.0, 100.0)

	print("Ripple: Bribed %s for %s on the active bill (%d credits). Leaked: %s." % [
		p.politician_name, direction, cost, str(leaked_publicly),
	])

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

	# Also refresh the job board during the news cycle — batched with NetFeed
	# so jobs feel like they arrive "with the broadcast" rather than on a
	# separate tick.
	_maybe_post_jobs()

	# Evaluate cultural cameos once per news cycle.
	if has_node("/root/CulturalCameos"):
		get_node("/root/CulturalCameos").evaluate_triggers()

	if has_node("/root/LLMManager"):
		var llm = get_node("/root/LLMManager")
		if not llm.netfeed_stream_received.is_connected(_on_netfeed_stream_received):
			llm.netfeed_stream_received.connect(_on_netfeed_stream_received)
		
		# Build oligarch context for the LLM
		var oligarch_context = {}
		for o in oligarchs:
			if o.alive:
				oligarch_context[o.oligarch_name] = {
					"company": o.company_name,
					"title": o.title,
					"sector": o.sector_of_influence,
					"wealth": o.wealth,
					"paranoia": o.paranoia,
					"public_image": o.public_image,
					"controversy": o.controversy_level,
					"ambitions": o.ambitions,
					"profile": o.get_behavioral_profile()
				}

		# Pack a sample of politicians + NPCs so the LLM can attribute
		# posts across the whole cast, not just oligarchs. Keep it lean
		# so the prompt stays within token budget.
		var politician_context = {}
		for p in politicians:
			if p.alive:
				politician_context[p.politician_name] = {
					"faction": p.faction,
					"approval": int(p.public_approval),
					"scandal": int(p.scandal_level),
					"corruption": p.corruption,
				}

		var npc_context = {}
		var pop_dir = get_node_or_null("/root/PopulationDirector")
		if pop_dir and "roster" in pop_dir and pop_dir.roster != null:
			var sample: Array = pop_dir.roster.duplicate()
			sample.shuffle()
			var take: int = min(8, sample.size())
			for i in range(take):
				var n = sample[i]
				if n == null or not is_instance_valid(n):
					continue
				if "alive" in n and not n.alive:
					continue
				var nname: String = str(n.npc_name) if "npc_name" in n else ""
				if nname == "":
					continue
				var entry: Dictionary = {}
				entry["archetype"] = str(n.archetype) if "archetype" in n else "citizen"
				if n.has_method("get_behavioral_profile"):
					entry["mood"] = n.get_behavioral_profile()
				else:
					entry["mood"] = ""
				entry["trust_in_player"] = int(n.trust) if "trust" in n else 0
				npc_context[nname] = entry

		_netfeed_request_in_flight = true
		llm.request_netfeed_events(global_economy, oligarch_context, politician_context, npc_context)
	else:
		push_warning("LLMManager not found. Cannot evaluate complex conjectures.")

func _on_netfeed_stream_received(events: Array):
	_netfeed_request_in_flight = false
	# NEWS_TICKER events drip to the HUD over time. Both NEWS_TICKER and
	# SILENT_RIPPLE can carry a structured 'impact' dict — we apply it
	# immediately as bounded deltas to world state. The news the player
	# reads has REAL consequences; SILENT_RIPPLEs are the same mechanic
	# but without a headline, for pure off-screen shifts.
	for event in events:
		event["timestamp"] = Time.get_unix_time_from_system()
		var event_type = event.get("type", "NEWS_TICKER")
		var impact = event.get("impact", null)
		if impact != null and typeof(impact) == TYPE_DICTIONARY:
			_apply_systemic_impact(impact)
		if event_type == "NEWS_TICKER":
			var headline: String = str(event.get("headline", ""))
			if headline == "":
				continue
			_netfeed_queue.append(event)
		elif event_type == "SILENT_RIPPLE":
			var legacy_str: String = str(event.get("systemic_impact", ""))
			if DEBUG_SHOW_SILENT_RIPPLES:
				# Surface SILENT_RIPPLEs in the feed with a visible DEBUG
				# tag so we can audit what the LLM is nudging. Set the flag
				# to false (top of file) to hide them for release.
				var debug_line: String = _format_impact_for_debug(impact, legacy_str)
				if debug_line != "":
					event["headline"] = "[color=#888][DEBUG • silent ripple][/color] " + debug_line
					_netfeed_queue.append(event)
			elif legacy_str != "" and impact == null:
				print(">>> [INVISIBLE SHIFT] " + legacy_str)
	print("LLMManager stream: %d headlines queued, drip starting" % _netfeed_queue.size())


# Format a silent-ripple impact dict (or a legacy string) as a readable
# one-line summary so debug mode can surface it in the NetFeed panel.
func _format_impact_for_debug(impact, legacy_str: String = "") -> String:
	var parts: Array[String] = []
	if impact != null and typeof(impact) == TYPE_DICTIONARY:
		for key in _SYSTEMIC_GLOBAL_CAPS.keys():
			if impact.has(key):
				var v: int = int(impact[key])
				var short: String = key.replace("_delta", "")
				parts.append("%s %+d" % [short, v])
		if impact.has("oligarch") and typeof(impact.oligarch) == TYPE_DICTIONARY:
			var oname: String = str(impact.oligarch.get("name", "?"))
			for k in _SYSTEMIC_OLIGARCH_CAPS.keys():
				if impact.oligarch.has(k):
					parts.append("%s.%s %+d" % [oname, k, int(impact.oligarch[k])])
		if impact.has("politician") and typeof(impact.politician) == TYPE_DICTIONARY:
			var pname: String = str(impact.politician.get("name", "?"))
			for k in _SYSTEMIC_POLITICIAN_CAPS.keys():
				if impact.politician.has(k):
					parts.append("%s.%s %+d" % [pname, k, int(impact.politician[k])])
	if parts.is_empty() and legacy_str != "":
		return legacy_str
	return " · ".join(parts) if not parts.is_empty() else ""


# =============================================================
# SYSTEMIC IMPACT — bounded LLM-driven world mutation
# =============================================================
# SILENT_RIPPLE events can ship a structured impact dict that nudges
# world state. Only whitelisted keys with clamped ranges are honored;
# unknown keys are logged + ignored. This is the "middle path":
# the LLM narrates AND moves the sim by small increments, but can
# never swing a variable by more than the caps here.
const _SYSTEMIC_GLOBAL_CAPS: Dictionary = {
	"public_tension_delta":     5,     # ±5 per ripple
	"security_presence_delta":  5,
	"senate_alignment_delta":   3,
	"food_price_delta":         20,
	"tech_price_delta":         50,
}
const _SYSTEMIC_OLIGARCH_CAPS: Dictionary = {
	"controversy":   10,
	"paranoia":      10,
	"public_image":  15,
	"wealth":        50000,   # ±50k per ripple
}
const _SYSTEMIC_POLITICIAN_CAPS: Dictionary = {
	"scandal":   10,
	"approval":  15,
}


func _apply_systemic_impact(impact: Dictionary) -> void:
	# --- Global economy deltas ---
	for key in _SYSTEMIC_GLOBAL_CAPS.keys():
		if not impact.has(key):
			continue
		var raw: float = float(impact[key])
		var cap: int = int(_SYSTEMIC_GLOBAL_CAPS[key])
		var delta: int = int(clamp(raw, -cap, cap))
		var economy_key: String = key.replace("_delta", "")
		if not global_economy.has(economy_key):
			continue
		var new_val: int = int(global_economy[economy_key]) + delta
		# Clamp 0..100 for normalized sim variables; no upper bound on prices.
		if economy_key in ["public_tension", "security_presence", "senate_alignment"]:
			new_val = clamp(new_val, 0, 100)
		elif economy_key in ["food_price", "tech_price"]:
			new_val = max(0, new_val)
		global_economy[economy_key] = new_val
		print(">>> [RIPPLE] %s %+d → %d" % [economy_key, delta, new_val])

	# --- Oligarch-targeted impacts (by name, since LLM only sees names) ---
	var oligarch_impact = impact.get("oligarch", null)
	if oligarch_impact != null and typeof(oligarch_impact) == TYPE_DICTIONARY:
		var target_name: String = str(oligarch_impact.get("name", ""))
		var target_o: OligarchData = _find_oligarch_by_name(target_name)
		if target_o != null and target_o.alive:
			for k in _SYSTEMIC_OLIGARCH_CAPS.keys():
				if not oligarch_impact.has(k):
					continue
				var raw: float = float(oligarch_impact[k])
				var cap: int = int(_SYSTEMIC_OLIGARCH_CAPS[k])
				var delta: int = int(clamp(raw, -cap, cap))
				match k:
					"controversy":  target_o.controversy_level = clamp(target_o.controversy_level + delta, 0.0, 100.0)
					"paranoia":     target_o.paranoia = clamp(target_o.paranoia + delta, 0.0, 100.0)
					"public_image": target_o.public_image = clamp(target_o.public_image + delta, -100.0, 100.0)
					"wealth":       target_o.wealth = max(0, target_o.wealth + delta)
				print(">>> [RIPPLE] %s.%s %+d" % [target_o.oligarch_name, k, delta])
		elif target_name != "":
			push_warning("Systemic impact named unknown oligarch: " + target_name)

	# --- Politician-targeted impacts ---
	var politician_impact = impact.get("politician", null)
	if politician_impact != null and typeof(politician_impact) == TYPE_DICTIONARY:
		var target_name: String = str(politician_impact.get("name", ""))
		var target_p: PoliticianData = _find_politician_by_name(target_name)
		if target_p != null and target_p.alive:
			for k in _SYSTEMIC_POLITICIAN_CAPS.keys():
				if not politician_impact.has(k):
					continue
				var raw: float = float(politician_impact[k])
				var cap: int = int(_SYSTEMIC_POLITICIAN_CAPS[k])
				var delta: int = int(clamp(raw, -cap, cap))
				match k:
					"scandal":   target_p.scandal_level = clamp(target_p.scandal_level + delta, 0.0, 100.0)
					"approval":  target_p.public_approval = clamp(target_p.public_approval + delta, -100.0, 100.0)
				print(">>> [RIPPLE] %s.%s %+d" % [target_p.politician_name, k, delta])
		elif target_name != "":
			push_warning("Systemic impact named unknown politician: " + target_name)

	world_state_changed.emit()


func _find_oligarch_by_name(name: String) -> OligarchData:
	if name == "":
		return null
	for o in oligarchs:
		if o.oligarch_name == name:
			return o
	return null


func _find_politician_by_name(name: String) -> PoliticianData:
	if name == "":
		return null
	for p in politicians:
		if p.politician_name == name:
			return p
	return null


# Fires every NETFEED_DRIP_SECONDS. Pops the oldest queued event,
# publishes it to the HUD + history. Pulls a fresh batch from LLM when
# the queue is running low so the feed never starves.
func _on_netfeed_drip() -> void:
	if _netfeed_queue.size() > 0:
		var event: Dictionary = _netfeed_queue.pop_front()
		netfeed_history.append(event)
		netfeed_event_generated.emit(event)
		print(">>> [PUBLIC NEWS] " + str(event.get("headline", "")))

	# Top up before the well runs dry. Guard in-flight so we don't fire
	# multiple concurrent requests at the LLM.
	if _netfeed_queue.size() <= NETFEED_QUEUE_REFILL_THRESHOLD and not _netfeed_request_in_flight:
		trigger_news_cycle()

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

	# Year's End softens thresholds by a chosen amount. Makes month 13
	# the resolution month — the world bends toward an ending.
	var softness: int = 0
	if has_node("/root/TimeSystem"):
		softness = int(get_node("/root/TimeSystem").year_end_softness())

	# Chosen victory path — if the player picked one at run start, only
	# that triggers a win. Others fire a muted NetFeed note (close but
	# not the path you chose) and the run continues.
	var chosen_path: String = "ANY"
	if has_node("/root/PlayerManager"):
		chosen_path = str(get_node("/root/PlayerManager").chosen_victory_path)

	var all_dead: bool = oligarchs.size() > 0
	for o in oligarchs:
		if o.alive:
			all_dead = false
			break

	if all_dead:
		_maybe_fire_victory("DIRECT_ACTION",
			"DIRECT ACTION",
			"All oligarchs eliminated. The Enclave falls. A new order writes itself.",
			chosen_path)
		return

	if int(global_economy.get("public_tension", 0)) >= (100 - softness):
		_maybe_fire_victory("POLITICAL_REVOLUTION",
			"POLITICAL REVOLUTION",
			"Tension crosses the revolution threshold. The masses storm The Enclave. The NetFeed goes silent.",
			chosen_path)
		return

	if int(global_economy.get("senate_alignment", 50)) <= (0 + softness):
		_maybe_fire_victory("POLITICAL_REFORM",
			"POLITICAL REFORM",
			"Senate alignment collapses. Corporate charters dissolved by vote.",
			chosen_path)
		return

	var total_wealth: int = 0
	for o in oligarchs:
		total_wealth += o.wealth
	var wealth_threshold: int = 100000 + softness * 5000
	if total_wealth < wealth_threshold and oligarchs.size() > 0:
		_maybe_fire_victory("SYSTEMIC_COLLAPSE",
			"SYSTEMIC COLLAPSE",
			"Combined oligarch wealth collapses below survival. The Enclave is bankrupt.",
			chosen_path)
		return


# Bounce through chosen-path gate. If the detected victory kind matches
# the player's chosen path (or they picked "ANY"), fire it. Otherwise
# note the near-miss in NetFeed and keep the run going.
func _maybe_fire_victory(kind: String, title: String, flavor: String, chosen_path: String) -> void:
	if chosen_path == "ANY" or chosen_path == kind:
		_fire_victory(kind, title, flavor)
		return
	# Close but not the path you chose.
	var event := {
		"type": "NEWS_TICKER",
		"headline": "A %s condition fired — but that wasn't the path you chose. The run continues." % kind.replace("_", " ").to_lower(),
		"timestamp": Time.get_unix_time_from_system(),
	}
	netfeed_history.append(event)
	netfeed_event_generated.emit(event)


func _fire_victory(kind: String, title: String, flavor: String) -> void:
	_victory_locked = true
	print("VICTORY: [%s] %s — %s" % [kind, title, flavor])
	victory_achieved.emit(kind, title, flavor)


# Pickpocket result applier. Called by Main after it has rolled the
# stealth check, so the caller and the world stay in sync (caller needs
# the result to decide whether the CrowdNPC consumes or flees).
# See docs/04-player/progression.md income mechanism #5.
func apply_pickpocket_result(npc_id: String, success: bool) -> void:
	if not has_node("/root/PopulationDirector") or not has_node("/root/PlayerManager"):
		return
	var pop_dir = get_node("/root/PopulationDirector")
	var pm = get_node("/root/PlayerManager")
	var target = null
	for n in pop_dir.roster:
		if n.npc_id == npc_id:
			target = n
			break
	if target == null:
		return

	if success:
		var take: int = randi_range(20, 80)
		pm.add_credits(take, "pickpocket: %s" % target.npc_name)
		# Success = subtle lift. Target felt something, wasn't sure.
		pm.add_heat(pm.compute_heat_cost(1, {"method": "pickpocket_success"}), "pickpocket")
		pm.bump_playstyle(0.02, 0.03, 0.0, 0.06)
		target.opinion_of_player = max(-1.0, target.opinion_of_player - 0.05)
		pm.add_hope(-1.0, "stole from a neighbor")
		var event := {
			"type": "SILENT_RIPPLE",
			"headline": "",
			"systemic_impact": "pickpocketing reported near %s; one more shadow in the feed" % target.npc_name,
			"timestamp": Time.get_unix_time_from_system(),
		}
		netfeed_history.append(event)
		netfeed_event_generated.emit(event)
	else:
		# Failure = a witness is already on the phone. Force a high
		# witness count into the ctx so the Sinks don't forgive you
		# just because the street was empty — the ONE witness matters.
		pm.add_heat(pm.compute_heat_cost(3, {"method": "pickpocket_failure", "witness_count": 8}), "pickpocket failed")
		pm.bump_playstyle(0.01, 0.02, 0.0, 0.0)
		target.knowledge_of_player = min(1.0, target.knowledge_of_player + 0.30)
		target.opinion_of_player = max(-1.0, target.opinion_of_player - 0.15)
		var event := {
			"type": "NEWS_TICKER",
			"headline": "A witness called the patrol on an attempted lift near %s. Perpetrator fled empty-handed." % target.npc_name,
			"timestamp": Time.get_unix_time_from_system(),
		}
		netfeed_history.append(event)
		netfeed_event_generated.emit(event)


# Bribe cost with heat multiplier applied. Centralized so HUD and the
# _ripple_bribe_politician ripple agree on the number.
func effective_bribe_cost(p: PoliticianData) -> int:
	var base: int = p.get_bribe_cost()
	if has_node("/root/PlayerManager"):
		var heat: int = int(get_node("/root/PlayerManager").heat)
		if heat > 80:
			return base * 2
	return base


# ---------------------------------------------------------
# JOB BOARD — contracts + fixer jobs
# Called from trigger_news_cycle() every 3rd world cycle. Posting
# is probabilistic so the board has rhythm, not clockwork.
# ---------------------------------------------------------

func _maybe_post_jobs() -> void:
	if active_jobs.size() >= MAX_ACTIVE_JOBS:
		return
	if randf() < 0.65 and active_jobs.size() < MAX_ACTIVE_JOBS:
		_try_post_resistance_contract()
	if randf() < 0.45 and active_jobs.size() < MAX_ACTIVE_JOBS:
		_try_post_fixer_job()




func _try_post_resistance_contract() -> void:
	var living: Array = get_living_oligarchs()
	if living.is_empty():
		return

	# Resistance cells target the most hated / aggressive oligarch, weighted
	# by awareness_of_player + active-ambition intensity. The cell pays the
	# bounty out of black-market funds — no oligarch is transacting with
	# the player (the player's fighting oligarchs, not working for one).
	var weights: Array = []
	var total: float = 0.0
	for o in living:
		var w: float = 1.0
		w += float(o.awareness_of_player) * 0.02     # they know who you are
		w += float(o.paranoia) * 0.01                # they've been making moves
		if "Purge The Sinks" in o.ambitions:         # active threats get targeted
			w += 2.0
		if "Crush the resistance" in o.ambitions:
			w += 2.5
		weights.append(w)
		total += w

	if total <= 0.0:
		return

	var roll: float = randf() * total
	var target_oligarch = living[0]
	for i in range(living.size()):
		roll -= weights[i]
		if roll <= 0.0:
			target_oligarch = living[i]
			break

	var cell_name: String = JobBoardData.RESISTANCE_CELLS.pick_random()
	var target_sector: String = target_oligarch.sector_of_influence

	# Skip if this cell already has a live contract — and skip if another
	# cell is already calling for a hit on this sector (don't stack).
	for j in active_jobs:
		if j.get("source_name", "") == cell_name:
			return
		if j.get("source_type", "") == "resistance_cell" and j.get("target_ref", "") == target_sector:
			return

	_post_job({
		"source_type": "resistance_cell",
		"source_id": "cell_" + cell_name.replace(" ", "_").to_lower(),
		"source_name": cell_name,
		"target_kind": "sabotage_sector",
		"target_ref": target_sector,
		"target_label": "disrupt %s sector" % target_sector,
		"bounty": randi_range(500, 2500),
		"framing": "%s wants %s's operations damaged. Payment on verification." % [
			cell_name, target_oligarch.oligarch_name,
		],
	})


func _try_post_fixer_job() -> void:
	if not has_node("/root/PopulationDirector"):
		return
	var pop_dir = get_node("/root/PopulationDirector")

	# Only NPCs active during the current phase can post a job — some
	# fixers only work nights, some only days. See NPCData.active_phase.
	var is_night_now: bool = false
	if has_node("/root/TimeSystem"):
		is_night_now = get_node("/root/TimeSystem").is_night()

	var candidates: Array = []
	for n in pop_dir.roster:
		if not n.alive:
			continue
		if n.trust < 30.0:
			continue
		var phase: String = str(n.active_phase) if n.active_phase else "both"
		if phase == "both":
			candidates.append(n)
		elif phase == "day" and not is_night_now:
			candidates.append(n)
		elif phase == "night" and is_night_now:
			candidates.append(n)
	if candidates.is_empty():
		return
	var fixer = candidates.pick_random()
	# Skip if fixer already has a job on the board
	for j in active_jobs:
		if j.get("source_id", "") == fixer.npc_id:
			return

	var use_leak: bool = (randf() < 0.4) and not get_living_oligarchs().is_empty()
	var job_dict: Dictionary
	if use_leak:
		var target_oligarch = get_living_oligarchs().pick_random()
		job_dict = {
			"source_type": "npc_fixer",
			"source_id": fixer.npc_id,
			"source_name": fixer.npc_name,
			"target_kind": "leak_oligarch",
			"target_ref": target_oligarch.oligarch_id,
			"target_label": "leak on %s" % target_oligarch.oligarch_name,
			"bounty": randi_range(150, 350),
			"framing": "%s has been asking around — they want dirt on %s." % [
				fixer.npc_name, target_oligarch.oligarch_name,
			],
		}
	else:
		var sectors := ["Food", "Tech", "Energy", "Pharma"]
		var sector: String = sectors.pick_random()
		job_dict = {
			"source_type": "npc_fixer",
			"source_id": fixer.npc_id,
			"source_name": fixer.npc_name,
			"target_kind": "sabotage_sector",
			"target_ref": sector,
			"target_label": "disrupt %s" % sector,
			"bounty": randi_range(200, 400),
			"framing": "%s wants the %s sector disrupted. They say it's personal." % [
				fixer.npc_name, sector,
			],
		}
	_post_job(job_dict)


func _post_job(job: Dictionary) -> void:
	_next_job_index += 1
	job["job_id"] = "job_%04d" % _next_job_index
	job["posted_at_cycle"] = cycle
	job["expires_at_cycle"] = cycle + JOB_TTL_CYCLES
	active_jobs.append(job)
	job_posted.emit(job)

	var event := {
		"type": "NEWS_TICKER",
		"headline": JobBoardData.post_headline(job),
		"timestamp": Time.get_unix_time_from_system(),
	}
	netfeed_history.append(event)
	netfeed_event_generated.emit(event)


func _expire_jobs() -> void:
	var remaining: Array[Dictionary] = []
	for j in active_jobs:
		if cycle >= int(j.get("expires_at_cycle", 0)):
			job_expired.emit(j)
			var event := {
				"type": "NEWS_TICKER",
				"headline": "Job on '%s' expired unclaimed." % str(j.get("target_label", "")),
				"timestamp": Time.get_unix_time_from_system(),
			}
			netfeed_history.append(event)
			netfeed_event_generated.emit(event)
		else:
			remaining.append(j)
	active_jobs = remaining


func _check_jobs_match(kind: String, target_ref: String) -> void:
	var remaining: Array[Dictionary] = []
	for j in active_jobs:
		if str(j.get("target_kind", "")) == kind and str(j.get("target_ref", "")) == target_ref:
			_complete_job(j)
		else:
			remaining.append(j)
	active_jobs = remaining


func _complete_job(job: Dictionary) -> void:
	var bounty: int = int(job.get("bounty", 0))

	# Resistance cells pay from black-market funds — no oligarch transacts
	# with the player. Fixers bump their trust in the player.
	if str(job.get("source_type", "")) == "npc_fixer":
		if has_node("/root/PopulationDirector"):
			var pop_dir = get_node("/root/PopulationDirector")
			for n in pop_dir.roster:
				if n.npc_id == str(job.get("source_id", "")):
					n.trust = min(100.0, n.trust + 15.0)
					n.bond_history.append("Completed job: " + str(job.get("target_label", "")))
					break

	if has_node("/root/PlayerManager"):
		var pm_job = get_node("/root/PlayerManager")
		pm_job.add_credits(bounty, "job: %s" % str(job.get("target_label", "")))
		# Fixer jobs from humans restore more hope than faceless cells.
		if str(job.get("source_type", "")) == "npc_fixer":
			pm_job.add_hope(5.0, "fixer paid out")
		else:
			pm_job.add_hope(4.0, "cell paid out")

	var event := {
		"type": "NEWS_TICKER",
		"headline": JobBoardData.complete_headline(job),
		"timestamp": Time.get_unix_time_from_system(),
	}
	netfeed_history.append(event)
	netfeed_event_generated.emit(event)

	job_completed.emit(job)
