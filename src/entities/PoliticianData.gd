extends Resource
class_name PoliticianData

# =============================================================
# PoliticianData: The Senator Character Sheet
# =============================================================
# Each Politician is one of 11 procedural senators. Nature traits
# filter every bill; faction and patronage tilt the scale; player
# leverage, public mood, and peer charisma complete the voting
# equation. No one is a pure function of their faction.
# Mirrors OligarchData in spirit — a character sheet that makes
# decisions each cycle.
# =============================================================

# Identity
@export var politician_id: String = ""
@export var politician_name: String = ""
@export var title: String = ""                # "Senator", "Representative", "Chairman of X"
@export var faction: String = "INDEPENDENT"
## One of: CORPORATE_BLOC, POPULIST, REFORM, INDEPENDENT
@export var seat_district: String = ""        # region_id, or "At-Large"
@export var cause: String = ""                # signature issue, e.g. "labor", "law_and_order"
@export var alive: bool = true

# =============================================================
# INTRINSIC TRAITS (Nature — immutable, set at generation)
# =============================================================

@export_group("Intrinsic Traits")

@export var integrity: float = 0.5
## 1.0 = defends stated positions. 0.0 = will say anything for the moment.

@export var corruption: float = 0.5
## 1.0 = cheap to bribe. 0.0 = cannot be bought, only persuaded.

@export var populism: float = 0.5
## 1.0 = chases the polls. 0.0 = indifferent to public mood.

@export var ambition: float = 0.5
## 1.0 = pushes big risky bills, builds coalitions. 0.0 = coasts, rarely sponsors.

@export var conviction: float = 0.5
## 1.0 = ideologically anchored on `cause`. 0.0 = pragmatic, trades freely.

@export var charisma: float = 0.5
## 1.0 = their vote flips 1-2 peers. 0.0 = ignored in the chamber.

# =============================================================
# DYNAMIC STATE (evolves each cycle)
# =============================================================

@export_group("Dynamic State")

@export var public_approval: float = 0.0          # -100..100
@export var oligarch_patronage: Dictionary = {}   # {oligarch_id: debt_level}
@export var player_leverage: float = 0.0          # 0..100 — blackmail/favor banked
@export var scandal_level: float = 0.0            # 0..100
@export var re_election_proximity: int = 20       # cycles until re-election
@export var recent_votes: Array[Dictionary] = []  # rolling log of {bill_id, stance}
@export var position_consistency: float = 0.5     # derived; drops on flip-voting

# =============================================================
# QUIRKS — Human details for LLM speeches, interviews, headlines
# =============================================================

@export_group("Quirks")
@export var quirks: Array[String] = []

# =============================================================
# VOTING BEHAVIOR
# =============================================================

## Evaluate a bill and return a stance: "YES", "NO", "ABSTAIN", or "ABSENT".
## peer_stances is the list of {politician_id, stance} already cast this round,
## sorted in charisma-descending order.
func evaluate_bill(bill: Dictionary, world: Dictionary, peer_stances: Array = []) -> String:
	if not alive:
		return "ABSENT"

	var score := 0.0

	# 1. Ideological + faction fit
	var faction_pref: float = float(bill.get("faction_preferences", {}).get(faction, 0.0))
	var ideo_fit: float = float(bill.get("ideological_score", 0.0)) * _cause_alignment(bill)
	score += (faction_pref + ideo_fit) * conviction

	# 2. Patronage pull (oligarch money, filtered by effective corruption)
	var effective_corruption: float = corruption * (1.0 - integrity)
	var patronage_pull: float = 0.0
	var oligarch_stances: Dictionary = bill.get("_oligarch_stances", {})
	for oligarch_id in oligarch_patronage.keys():
		var debt: float = float(oligarch_patronage[oligarch_id])
		var oligarch_stance: float = float(oligarch_stances.get(oligarch_id, 0.0))
		patronage_pull += (debt / 100.0) * oligarch_stance
	score += patronage_pull * effective_corruption

	# 3. Populist pull — what does the public think?
	var public_stance: float = _public_stance_on(bill, world)
	score += populism * public_stance

	# 4. Player leverage (only if the player took a position)
	var player_ask: float = float(bill.get("_player_requested_stance", 0.0))  # -1..+1
	score += (player_leverage / 100.0) * player_ask

	# 5. Charisma contagion from peers who already voted
	if peer_stances.size() > 0:
		var peer_sum: float = 0.0
		for s in peer_stances:
			match s.get("stance", "ABSTAIN"):
				"YES": peer_sum += 1.0
				"NO":  peer_sum -= 1.0
		var peer_avg: float = peer_sum / peer_stances.size()
		score += peer_avg * 0.2

	# 6. Re-election jitter — panic near the deadline
	if re_election_proximity < 4:
		score += public_stance * populism * 0.5

	# 7. Resolve
	if abs(score) < 0.2:
		return "ABSTAIN"
	return "YES" if score > 0.0 else "NO"


func _cause_alignment(bill: Dictionary) -> float:
	# Bills whose summary mentions my cause hit harder.
	if cause == "":
		return 0.5
	var summary: String = str(bill.get("summary", "")).to_lower()
	return 1.0 if cause.to_lower() in summary else 0.3


func _public_stance_on(bill: Dictionary, world: Dictionary) -> float:
	# Proxy: high-tension worlds hate Pro-Enclave bills more. -1..+1 range.
	var tension: float = float(world.get("public_tension", 50.0))
	var ideo: float = float(bill.get("ideological_score", 0.0))
	return -ideo * (0.5 + tension / 200.0)

# =============================================================
# BEHAVIORAL PROFILE
# =============================================================

func get_behavioral_profile() -> String:
	if scandal_level > 70.0:
		return "The Collapsed"
	if conviction > 0.7 and charisma > 0.6:
		return "The Fire-brand"
	if corruption > 0.6 and integrity < 0.3:
		return "The Bagman"
	if integrity > 0.8 and corruption < 0.2:
		return "The Conscience"
	if ambition > 0.8 and populism > 0.6:
		return "The Climber"
	if populism < 0.3 and conviction > 0.5:
		return "The Sphinx"
	if ambition < 0.3 and re_election_proximity > 10:
		return "The Lifer"
	return "The Loyalist"

# =============================================================
# LLM CONTEXT — for bill sponsorship, speeches, interviews
# =============================================================

func get_llm_context_string() -> String:
	var ctx := "You are %s, %s of the %s faction, representing %s. " \
		% [politician_name, title, faction, seat_district]
	ctx += "Behavioral profile: %s. Signature issue: %s. " \
		% [get_behavioral_profile(), cause]
	ctx += "Public approval: %.0f/100. Scandal level: %.0f/100. " \
		% [public_approval, scandal_level]
	ctx += "Re-election in %d cycles. " % re_election_proximity

	ctx += "Personality: "
	if integrity > 0.6: ctx += "publicly principled, "
	elif integrity < 0.3: ctx += "shape-shifting, "
	if corruption > 0.6: ctx += "easily bought, "
	elif corruption < 0.3: ctx += "incorruptible, "
	if populism > 0.6: ctx += "camera-hungry, "
	elif populism < 0.3: ctx += "indifferent to the public, "
	if ambition > 0.6: ctx += "hungry for more, "
	if conviction > 0.6: ctx += "ideologically anchored, "
	elif conviction < 0.3: ctx += "pragmatic to a fault, "
	if charisma > 0.6: ctx += "a commanding speaker. "
	elif charisma < 0.3: ctx += "a backbencher. "
	else: ctx += "competent at the lectern. "

	if quirks.size() > 0:
		ctx += "Quirks you MUST embody: " + ", ".join(quirks) + ". "

	if oligarch_patronage.size() > 0:
		ctx += "You owe favors to: %s. " % ", ".join(oligarch_patronage.keys())

	return ctx
