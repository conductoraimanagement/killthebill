extends Node
class_name SenateDirector

# =============================================================
# SenateDirector: Orchestrates bill generation and Senate voting
# =============================================================
# Each world cycle:
#   1. Pick a sponsor (weighted by faction pressure + traits)
#   2. Ask the LLM to generate a Bill from current world state
#      + the sponsor's character
#   3. Open a player-interaction window (one cycle)
#   4. Tally votes in charisma order; peers influence peers
#   5. Pass results back to WorldDirector for economy mutation
#
# The LLM writes the bill. The sim enforces the bill. Effects are
# clamped against an explicit whitelist so a hallucinated key
# cannot mutate unintended state.
# =============================================================

signal bill_proposed(bill: Dictionary)
signal bill_resolved(bill: Dictionary, result: String, vote_record: Array)

var politicians: Array = []           # Array[PoliticianData]
var active_bill: Dictionary = {}      # current bill in debate; {} if none
var bill_history: Array[Dictionary] = []
var _next_bill_index: int = 0


func register_politicians(pols: Array) -> void:
	politicians = pols


func begin_cycle(world: Dictionary, oligarchs: Array, recent_netfeed: Array) -> void:
	# Resolve last cycle's bill first, if any.
	if not active_bill.is_empty():
		_tally_and_resolve(world, oligarchs)

	if politicians.size() < 11:
		push_warning("SenateDirector: fewer than 11 politicians registered (%d)" % politicians.size())

	var sponsor: PoliticianData = _pick_sponsor(world)
	if sponsor == null:
		return
	_propose_bill_async(sponsor, world, oligarchs, recent_netfeed)


# =============================================================
# SPONSOR SELECTION
# =============================================================

func _pick_sponsor(world: Dictionary) -> PoliticianData:
	var tension: float = float(world.get("public_tension", 50.0))
	var senate_alignment: float = float(world.get("senate_alignment", 50.0))

	var last_sponsor_id: String = ""
	if bill_history.size() > 0:
		last_sponsor_id = bill_history.back().get("sponsor_id", "")

	var weights: Array = []
	var total: float = 0.0
	for p in politicians:
		if not p.alive:
			weights.append(0.0)
			continue
		var w: float = p.ambition
		w += _faction_pressure(p.faction, tension, senate_alignment)
		if p.re_election_proximity < 4:
			w += p.populism * 2.0
		if p.scandal_level > 50.0:
			w += 0.5
		# A sponsor cannot sponsor in consecutive cycles.
		if p.politician_id == last_sponsor_id:
			w = 0.0
		weights.append(max(w, 0.0))
		total += weights.back()

	if total <= 0.0:
		return politicians[randi() % politicians.size()] if politicians.size() > 0 else null

	var roll: float = randf() * total
	for i in range(politicians.size()):
		roll -= weights[i]
		if roll <= 0.0:
			return politicians[i]
	return politicians[-1]


func _faction_pressure(faction: String, tension: float, senate_alignment: float) -> float:
	# Populists spike under tension; Corporate Bloc spikes when senate is pro-Enclave.
	match faction:
		"POPULIST":
			return max(0.0, (tension - 50.0) / 50.0)
		"CORPORATE_BLOC":
			return max(0.0, (senate_alignment - 50.0) / 50.0) + 0.3
		"REFORM":
			return 0.4
		"INDEPENDENT":
			return 0.3
	return 0.2

# =============================================================
# BILL GENERATION (LLM-DRIVEN)
# =============================================================

func _propose_bill_async(sponsor: PoliticianData, world: Dictionary, oligarchs: Array, recent_netfeed: Array) -> void:
	_next_bill_index += 1
	var request: Dictionary = {
		"sponsor_context": sponsor.get_llm_context_string(),
		"world_snapshot": world,
		"recent_netfeed": recent_netfeed,
		"active_oligarch_ambitions": _collect_active_ambitions(oligarchs),
		"forbidden_topics": _recent_bill_topics(),
		"effect_whitelist": _effect_whitelist(),
	}
	# LLMManager is expected to post back via _on_bill_generated with parsed JSON.
	# (Mirrors the pattern used for oligarch/region generation.)
	if has_node("/root/LLMManager"):
		var llm = get_node("/root/LLMManager")
		llm.request_bill(request, Callable(self, "_on_bill_generated").bind(sponsor))
	else:
		_on_bill_generated(_fallback_bill(sponsor), sponsor)


func _on_bill_generated(result: Dictionary, sponsor: PoliticianData) -> void:
	var bill: Dictionary
	if result.is_empty() or result.has("error") or not result.has("title"):
		push_warning("SenateDirector: LLM failed, using fallback bill")
		bill = _fallback_bill(sponsor)
	else:
		bill = result

	bill["bill_id"] = "bill_%05d" % _next_bill_index
	bill["sponsor_id"] = sponsor.politician_id
	active_bill = bill
	emit_signal("bill_proposed", bill)

# =============================================================
# VOTING RESOLUTION
# =============================================================

func _tally_and_resolve(world: Dictionary, oligarchs: Array) -> void:
	if active_bill.is_empty():
		return

	# Inject each oligarch's stance so politicians can weigh patronage pull.
	active_bill["_oligarch_stances"] = _compute_oligarch_stances(active_bill, oligarchs)

	# Charisma-desc vote order — earlier voters sway later ones.
	var order: Array = politicians.duplicate()
	order.sort_custom(func(a, b): return a.charisma > b.charisma)

	var votes: Array = []
	for p in order:
		var stance: String = p.evaluate_bill(active_bill, world, votes)
		votes.append({"politician_id": p.politician_id, "stance": stance})
		p.recent_votes.append({
			"bill_id": active_bill.get("bill_id", ""),
			"stance": stance,
		})
		# One-shot bribes clear after the vote they paid for.
		p.pending_bribe_direction = 0.0

	var yes: int = 0
	var no: int = 0
	for v in votes:
		match v.stance:
			"YES": yes += 1
			"NO":  no += 1

	var result: String = "PASS" if yes > no else "FAIL"
	active_bill["result"] = result
	active_bill["margin"] = yes - no
	active_bill["vote_record"] = votes
	bill_history.append(active_bill)
	emit_signal("bill_resolved", active_bill, result, votes)
	active_bill = {}


func _compute_oligarch_stances(bill: Dictionary, oligarchs: Array) -> Dictionary:
	# Each oligarch's enthusiasm for the bill, -1..+1.
	# Simple model: start from ideological_score, nudge by ambitions.
	var out: Dictionary = {}
	var ideo: float = float(bill.get("ideological_score", 0.0))
	for o in oligarchs:
		if not o.alive:
			continue
		var stance: float = ideo
		if "Purge The Sinks" in o.ambitions:
			stance += 0.5
		if "Build a legacy" in o.ambitions:
			stance -= 0.2
		if "Transcend humanity" in o.ambitions:
			stance += 0.3
		if "Crush the resistance" in o.ambitions:
			stance += 0.3
		out[o.oligarch_id] = clamp(stance, -1.0, 1.0)
	return out

# =============================================================
# LLM PROMPT HELPERS
# =============================================================

func _collect_active_ambitions(oligarchs: Array) -> Array:
	var out: Array = []
	for o in oligarchs:
		if not o.alive:
			continue
		for a in o.ambitions:
			out.append({"oligarch_id": o.oligarch_id, "ambition": a})
	return out


func _recent_bill_topics() -> Array:
	var out: Array = []
	var start: int = max(0, bill_history.size() - 2)
	for i in range(start, bill_history.size()):
		out.append(bill_history[i].get("title", ""))
	return out


func _effect_whitelist() -> Dictionary:
	# The LLM may only write these keys, within these ranges.
	return {
		"public_tension":    {"min": -50, "max": 50},
		"security_presence": {"min": -30, "max": 30},
		"food_price":        {"min": -200, "max": 200},
		"tech_price":        {"min": -200, "max": 200},
		"senate_alignment":  {"min": -20, "max": 20},
	}

# =============================================================
# FALLBACK — offline / LLM-failure path
# =============================================================

func _fallback_bill(sponsor: PoliticianData) -> Dictionary:
	var ideo: float = 0.0
	match sponsor.faction:
		"CORPORATE_BLOC": ideo = 0.6
		"POPULIST":       ideo = -0.6
		"REFORM":         ideo = -0.3
		"INDEPENDENT":    ideo = 0.1
	return {
		"title": "Omnibus Appropriations Amendment",
		"summary": "Adjusts sector allocations based on quarterly projections.",
		"stated_rationale": "Fiscal responsibility.",
		"honest_rationale": "",
		"ideological_score": ideo,
		"faction_preferences": {
			"CORPORATE_BLOC":  0.5,
			"POPULIST":       -0.5,
			"REFORM":         -0.2,
			"INDEPENDENT":     0.0,
		},
		"proposed_effects": {
			"senate_alignment": int(ideo * 10.0),
		},
		"scandal_hooks": [],
		"netfeed_flavor": "routine legislation; small print, big effect",
	}
