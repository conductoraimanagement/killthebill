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
signal npc_bond_formed(a, b)
signal npc_romance_formed(a, b)

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

	# NPC-to-NPC partner takes a hit. The social graph mourns too.
	if npc.npc_partner_id != "":
		var survivor = _find_by_id(npc.npc_partner_id)
		if survivor != null and survivor.alive:
			survivor.hope = max(0.0, survivor.hope - 30.0)
			survivor.stress_level = min(100.0, survivor.stress_level + 15.0)
			survivor.npc_partner_id = ""
			if wd:
				var grief_event := {
					"type": "NEWS_TICKER",
					"headline": "%s heard about %s. They were seen on their balcony through the night." % [
						survivor.npc_name, npc.npc_name,
					],
					"timestamp": Time.get_unix_time_from_system(),
				}
				wd.netfeed_history.append(grief_event)
				wd.netfeed_event_generated.emit(grief_event)

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


const SOCIAL_PAIRS_PER_CYCLE: int = 8
const BOND_INCREMENT_PER_MEETING: float = 2.5
const BOND_FIRST_MENTION_THRESHOLD: float = 30.0
const BOND_ROMANCE_THRESHOLD: float = 75.0


# Called by WorldDirector each day. Picks SOCIAL_PAIRS_PER_CYCLE random
# pairs of alive NPCs active in the current phase and runs them through
# a single interaction — bond bump + mood contagion + radicalization
# spread + opinion-of-player diffusion + occasional romance formation.
# The roster lives independently of the player.
func tick_social_graph(cycle: int) -> void:
	var ts := get_node_or_null("/root/TimeSystem")
	var is_night_now: bool = ts.is_night() if ts else false

	var active_pool: Array = []
	for n in roster:
		if not n.alive:
			continue
		var phase: String = str(n.active_phase) if n.active_phase else "both"
		var active_now: bool = phase == "both" \
			or (phase == "day" and not is_night_now) \
			or (phase == "night" and is_night_now)
		if active_now:
			active_pool.append(n)

	if active_pool.size() < 2:
		return

	for i in range(SOCIAL_PAIRS_PER_CYCLE):
		var a = active_pool.pick_random()
		var b = active_pool.pick_random()
		if a.npc_id == b.npc_id:
			continue
		_interact_pair(a, b, cycle)


func _interact_pair(a, b, cycle: int) -> void:
	# --- Bond bump (symmetric) ---
	var prev_bond: float = float(a.npc_bonds.get(b.npc_id, 0.0))
	var new_bond: float = min(100.0, prev_bond + BOND_INCREMENT_PER_MEETING)
	a.npc_bonds[b.npc_id] = new_bond
	b.npc_bonds[a.npc_id] = new_bond

	# NetFeed the first time a bond crosses the "notable" threshold — a
	# one-shot cue that two roster members have become a pair of interest.
	if prev_bond < BOND_FIRST_MENTION_THRESHOLD and new_bond >= BOND_FIRST_MENTION_THRESHOLD:
		_emit_social_note("%s and %s were seen deep in conversation at the breadline. Subject unknown." % [
			a.npc_name, b.npc_name,
		])
		npc_bond_formed.emit(a, b)

	# --- Mood contagion, weighted by bond ---
	# Strong bonds spread mood faster. Weak acquaintances barely affect
	# each other. Split the delta so both move toward a midpoint.
	var weight: float = new_bond / 100.0 * 0.25   # 0..0.25
	_pull_toward(a, b, "hope", weight)
	_pull_toward(a, b, "stress_level", weight * 0.6)

	# --- Radicalization spread ---
	# Agitators infect the cautious, unless the cautious have high conformity.
	if a.radicalization > 70.0 and b.radicalization < 40.0 and b.conformity < 0.6:
		b.radicalization = min(100.0, b.radicalization + 2.0)
	if b.radicalization > 70.0 and a.radicalization < 40.0 and a.conformity < 0.6:
		a.radicalization = min(100.0, a.radicalization + 2.0)

	# --- Opinion-of-player diffusion ---
	# Stronger opinion drags the weaker toward it, scaled by bond.
	if randf() < 0.15:
		var pull: float = weight * 0.4
		if abs(a.opinion_of_player) > abs(b.opinion_of_player):
			b.opinion_of_player = lerp(b.opinion_of_player, a.opinion_of_player, pull)
		else:
			a.opinion_of_player = lerp(a.opinion_of_player, b.opinion_of_player, pull)

	# --- Romance formation ---
	# High bond, both unpartnered (NPC-NPC), compatible dispositions.
	if new_bond >= BOND_ROMANCE_THRESHOLD \
	and a.npc_partner_id == "" and b.npc_partner_id == "" \
	and a.relationship_type != 4 and b.relationship_type != 4 \
	and randf() < 0.06:
		_pair_romance(a, b)


func _pull_toward(a, b, field: String, weight: float) -> void:
	# Move a[field] and b[field] partway toward each other.
	var av: float = float(a.get(field))
	var bv: float = float(b.get(field))
	var mid: float = (av + bv) * 0.5
	a.set(field, clampf(lerp(av, mid, weight), 0.0, 100.0))
	b.set(field, clampf(lerp(bv, mid, weight), 0.0, 100.0))


func _pair_romance(a, b) -> void:
	a.npc_partner_id = b.npc_id
	b.npc_partner_id = a.npc_id
	a.hope = min(100.0, a.hope + 10.0)
	b.hope = min(100.0, b.hope + 10.0)
	_emit_social_note("%s and %s walked home together under the overpass. The neighborhood noticed." % [
		a.npc_name, b.npc_name,
	])
	npc_romance_formed.emit(a, b)


func _emit_social_note(text: String) -> void:
	var wd := get_node_or_null("/root/WorldDirector")
	if wd == null:
		return
	var event := {
		"type": "NEWS_TICKER",
		"headline": text,
		"timestamp": Time.get_unix_time_from_system(),
	}
	wd.netfeed_history.append(event)
	wd.netfeed_event_generated.emit(event)


# Called by WorldDirector each day. For each romantic partner who
# doesn't yet know about the others, roll a discovery chance. On
# discovery, fire the partner's personality-based reaction once.
func evaluate_infidelity_discoveries(cycle: int) -> void:
	var pm := get_node_or_null("/root/PlayerManager")
	if pm == null or pm.romantic_partner_ids.size() < 2:
		return
	var wd := get_node_or_null("/root/WorldDirector")

	for partner_id in pm.romantic_partner_ids:
		var p = _find_by_id(partner_id)
		if p == null or not p.alive:
			continue
		if p.infidelity_reacted:
			continue

		# Conformist NPCs pay attention to social norms and find out sooner.
		# Scale with partner count — more partners = harder to hide.
		var base: float = 0.03   # 3%/day baseline
		var conformity_bump: float = float(p.conformity) * 0.05
		var partner_count_bump: float = float(pm.romantic_partner_ids.size() - 1) * 0.02
		var chance: float = base + conformity_bump + partner_count_bump
		if randf() < chance:
			p.infidelity_known = true
			_apply_infidelity_reaction(p, pm, wd)


func _apply_infidelity_reaction(p, pm, wd) -> void:
	p.infidelity_reacted = true
	var name_str: String = p.npc_name

	# Personality-driven fork. Each reaction fires once per partner.
	if p.empathy > 0.6:
		# Polyamorous acceptance (with cost). Trust dips slightly.
		p.trust = max(0.0, p.trust - 5.0)
		_emit_relationship_note(wd, "%s tells you she knows about the others. 'I understand.' Her hand stays on yours a half-beat longer than normal." % name_str)
		pm.add_hope(-2.0, "quiet forgiveness costs")
		return

	if p.aggression > 0.6:
		# Confrontation — may get physical, heat spikes, they may become hostile.
		p.trust = max(0.0, p.trust - 40.0)
		p.opinion_of_player = max(-1.0, p.opinion_of_player - 0.5)
		p.knowledge_of_player = min(1.0, p.knowledge_of_player + 0.4)
		p.relationship_type = 1  # Acquaintance — no longer romantic
		pm.remove_romantic_partner(p.npc_id)
		pm.add_heat(20, "partner called in a favor")
		pm.add_hope(-10.0, "it got ugly with %s" % name_str)
		_emit_relationship_note(wd, "%s cornered you. Voices carried. A neighbor called the patrol." % name_str)
		return

	if p.conformity > 0.6 and p.empathy < 0.4:
		# Public denunciation — scandal in the feed.
		p.trust = max(0.0, p.trust - 30.0)
		p.opinion_of_player = max(-1.0, p.opinion_of_player - 0.4)
		p.relationship_type = 1
		pm.remove_romantic_partner(p.npc_id)
		pm.add_hope(-15.0, "%s denounced you" % name_str)
		_emit_relationship_note(wd, "%s posted a long message on the block's bulletin — names, dates, the whole list. The Sinks read it twice." % name_str)
		return

	if p.greed > 0.6:
		# Hush money demand.
		var demand: int = 500
		var paid: bool = false
		if pm.can_afford(demand):
			pm.spend_credits(demand, "hush money to %s" % name_str)
			paid = true
			p.trust = max(0.0, p.trust - 10.0)
			pm.add_hope(-4.0, "bought silence")
			_emit_relationship_note(wd, "%s wanted 500 credits 'for silence'. You paid. The silence held." % name_str)
		else:
			# Can't afford → full scandal treatment.
			p.trust = max(0.0, p.trust - 30.0)
			p.opinion_of_player = max(-1.0, p.opinion_of_player - 0.4)
			p.relationship_type = 1
			pm.remove_romantic_partner(p.npc_id)
			pm.add_hope(-10.0, "%s cashed out on you" % name_str)
			_emit_relationship_note(wd, "%s wanted 500 credits for silence. You couldn't pay. The story is out." % name_str)
		return

	if p.idealism > 0.6:
		# Quiet idealistic breakup — they expected better.
		p.trust = max(0.0, p.trust - 25.0)
		p.opinion_of_player = max(-1.0, p.opinion_of_player - 0.2)
		p.relationship_type = 2  # Friend tier, they still care
		pm.remove_romantic_partner(p.npc_id)
		pm.add_hope(-12.0, "%s expected more" % name_str)
		p.hope = max(0.0, p.hope - 15.0)   # their hope drops too
		_emit_relationship_note(wd, "%s sent a note. Short. 'I thought we were building something.' She's still speaking to you. Differently." % name_str)
		return

	# Default quiet fallout — trust erodes, relationship downgrades.
	p.trust = max(0.0, p.trust - 20.0)
	p.opinion_of_player = max(-1.0, p.opinion_of_player - 0.2)
	p.relationship_type = 2
	pm.remove_romantic_partner(p.npc_id)
	pm.add_hope(-8.0, "%s quietly stepped away" % name_str)
	_emit_relationship_note(wd, "%s stopped calling. Didn't say why. Didn't need to." % name_str)


func _find_by_id(npc_id: String):
	for n in roster:
		if n.npc_id == npc_id:
			return n
	return null


func _emit_relationship_note(wd, text: String) -> void:
	if wd == null:
		return
	var event := {
		"type": "NEWS_TICKER",
		"headline": text,
		"timestamp": Time.get_unix_time_from_system(),
	}
	wd.netfeed_history.append(event)
	wd.netfeed_event_generated.emit(event)


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
