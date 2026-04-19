extends Node
class_name CulturalCameos

# =============================================================
# CulturalCameos: the trigger engine for pop-culture intrusions.
#
# Each cameo is gated by world state + player profile. Evaluated
# once per news cycle. Tier 1 Whispers (NetFeed-only, no mechanical
# impact) are live today; Tier 2-4 are designed in
# docs/03-characters/cultural-cameos.md and awaited.
#
# Cameos that have fired once during the run won't fire again —
# rarity is preserved across the playthrough.
# =============================================================

signal cameo_triggered(cameo: Dictionary)
signal cameo_arc_started(arc: Dictionary)
signal cameo_arc_completed(arc: Dictionary)
signal cameo_arc_expired(arc: Dictionary)

const CAMEOS := [
	{
		"id": "soap_broadcast",
		"tier": 1,
		"archetype": "chaos_prophet",
		"name": "The Soap Broadcast",
		"min_cycle": 3,
		"probability": 0.15,
		"gate": {
			"public_tension": {"min": 45.0},
			"player_chaos_preference": {"min": 0.25},
		},
		"headline": "Unlicensed broadcast crackles across Pirate 88.8 for 47 seconds: 'Thou shalt not own soap.' Enforcers tracing the signal.",
	},
	{
		"id": "mask_in_the_crowd",
		"tier": 1,
		"archetype": "masked_symbol",
		"name": "The Mask in the Crowd",
		"min_cycle": 4,
		"probability": 0.13,
		"gate": {
			"senate_alignment": {"max": 45.0},
		},
		"headline": "A crowd of strangers all wearing the same blank mask filed silently past the senate building this morning. No organization has claimed it.",
	},
	{
		"id": "compliance_error_7",
		"tier": 1,
		"archetype": "rogue_ai",
		"name": "Compliance Error 7",
		"min_cycle": 5,
		"probability": 0.11,
		"gate": {
			"player_heat": {"min": 50.0},
		},
		"headline": "Public advisory servers glitch for 47 seconds. Error logs contain one line: COMPLIANCE ERROR 7. PATTERN MATCH EXCEEDED.",
	},
	{
		"id": "unsigned_manifesto",
		"tier": 1,
		"archetype": "lone_manifesto",
		"name": "Unsigned Papers",
		"min_cycle": 4,
		"probability": 0.12,
		"gate": {
			"public_tension": {"min": 40.0},
			"player_idealism": {"min": 0.20},
		},
		"headline": "A 47-page unsigned manifesto circulates in Substrate Fields. Half demands, half lament. Nobody knows who wrote it.",
	},
	{
		"id": "yellow_hymn",
		"tier": 1,
		"archetype": "cult_of_personality",
		"name": "Hymns from the Undercity",
		"min_cycle": 6,
		"probability": 0.09,
		"gate": {
			"public_tension": {"min": 55.0},
			"senate_alignment": {"max": 55.0},
		},
		"headline": "Citizens report a yellow-robed figure leading night prayer in the lower Sinks. The hymn does not appear in any database.",
	},
	{
		"id": "kindly_coffee",
		"tier": 1,
		"archetype": "kindly_stranger",
		"name": "A Coffee on the House",
		"min_cycle": 3,
		"probability": 0.10,
		"gate": {
			"player_ruthlessness": {"max": 0.30},
		},
		"headline": "An old man ran a small stand at the transit pier today, handing strangers coffee free of charge. He smiled at anyone who looked tired.",
	},

	# ------------------------------------------------------------
	# Tier 2 — Brush. One-scene arc with a concrete objective.
	# Triggers surface a NetFeed headline + add to active_arcs; matching
	# a ripple within arc_duration_cycles completes it for a reward.
	# ------------------------------------------------------------
	{
		"id": "bread_thief_arc",
		"tier": 2,
		"archetype": "folk_hero_from_the_sinks",
		"name": "The Bread Thief",
		"min_cycle": 5,
		"probability": 0.18,
		"gate": {"public_tension": {"min": 50.0}},
		"intro_headline": "A woman's been hitting Enclave bakeries at night and leaving bread in the Sinks. NetFeed says patrols are closing on her.",
		"objective": {
			"kind": "sabotage_sector",
			"target_ref": "Security",
			"label": "hit Security-sector infrastructure to draw patrols away from her route"
		},
		"arc_duration_cycles": 3,
		"completion_headline": "The Bread Thief slipped the cordon tonight. Bread distribution quietly resumed in the lower Sinks.",
		"timeout_headline": "The Bread Thief was caught at dawn. The patrols went quiet. The Sinks went quieter.",
		"reward": {"credits": 800, "tension_delta": -8, "idealism_bump": 0.08},
	},
	{
		"id": "admin_last_login",
		"tier": 2,
		"archetype": "whistleblower",
		"name": "The Admin Who Got Fired",
		"min_cycle": 6,
		"probability": 0.14,
		"gate": {"player_heat": {"min": 30.0}},
		"intro_headline": "Anonymous admin account 'LAST_LOGIN' is leaking Tech-sector emails in six-hour bursts. Someone wants a specific oligarch embarrassed.",
		"objective": {
			"kind": "leak_sector",
			"target_ref": "Tech",
			"label": "surface public dirt on the Tech oligarch before the admin is traced"
		},
		"arc_duration_cycles": 4,
		"completion_headline": "'LAST_LOGIN' went dark after a coordinated leak hit every major outlet at 03:12. An admin is going to jail — somewhere.",
		"timeout_headline": "'LAST_LOGIN' was traced and terminated. Fragments vanished from the feed overnight.",
		"reward": {"credits": 700, "tension_delta": 6, "senate_alignment_delta": -6},
	},

	# ------------------------------------------------------------
	# Tier 3 — Entanglement. Multi-cycle arc with passive per-cycle
	# modifiers while active, bigger reward on completion, bigger
	# silent fallout if it times out. Only one Tier-3+ arc at a time.
	# ------------------------------------------------------------
	{
		"id": "hermit_substrate_fields",
		"tier": 3,
		"archetype": "lone_manifesto",
		"name": "The Hermit of Substrate Fields",
		"min_cycle": 7,
		"probability": 0.10,
		"gate": {
			"public_tension": {"min": 50.0},
			"player_idealism": {"min": 0.30},
		},
		"intro_headline": "An old man's 47-page manifesto has begun appearing in Agricultural-region terminals. He demands a meeting with a senator. He has a list.",
		"objective": {
			"kind": "sabotage_sector",
			"target_ref": "Food",
			"label": "disrupt the Food sector so his message reaches the senate floor"
		},
		"arc_duration_cycles": 6,
		"while_active_modifiers": {"public_tension": 1},  # +1 tension/day while running
		"completion_headline": "The Hermit of Substrate Fields stands on a grain silo tonight, his manifesto blaring over the region PA. Enforcers are surrounding — but nobody moves.",
		"timeout_headline": "The Hermit was 'relocated' to a state facility for evaluation. His manifesto vanished from the terminals overnight.",
		"reward": {"credits": 1500, "tension_delta": 10, "idealism_bump": 0.15, "senate_alignment_delta": -8},
	},
	{
		"id": "yellow_priest_arc",
		"tier": 3,
		"archetype": "cult_of_personality",
		"name": "The Yellow Priest",
		"min_cycle": 8,
		"probability": 0.09,
		"gate": {
			"public_tension": {"min": 60.0},
			"senate_alignment": {"max": 50.0},
		},
		"intro_headline": "A yellow-robed figure has been holding nightly prayer in the lower Sinks. Congregations are growing. The hymns aren't indexed.",
		"objective": {
			"kind": "leak_sector",
			"target_ref": "Media",
			"label": "leak dirt on the Media oligarch so the cult stays off the censored list"
		},
		"arc_duration_cycles": 5,
		"while_active_modifiers": {"public_tension": 2},
		"completion_headline": "By week's end, the Priest's congregation numbered in the thousands. The NetFeed pretended otherwise.",
		"timeout_headline": "The Yellow Priest was quietly 'relocated' for 'mental evaluation'. Hymns stopped. Congregations dispersed.",
		"reward": {"credits": 1800, "tension_delta": 15, "idealism_bump": 0.10, "senate_alignment_delta": -12},
	},
]

var fired_ids: Array[String] = []

# Active higher-tier arcs currently running.
# Each entry: {cameo_id, definition, cycles_left, completed}
var active_arcs: Array[Dictionary] = []

# Only one Tier-3+ arc active at a time — the world can sustain one
# hijacking, not three.
const MAX_HIGH_TIER_ACTIVE := 1


func reset() -> void:
	fired_ids.clear()
	active_arcs.clear()


# Called by WorldDirector.trigger_news_cycle — one evaluation per
# phase boundary (3× per day), NOT per day.
func evaluate_triggers() -> void:
	for cameo in CAMEOS:
		var cameo_id: String = str(cameo.get("id", ""))
		if cameo_id in fired_ids:
			continue
		if not _is_gate_satisfied(cameo):
			continue
		if randf() < float(cameo.get("probability", 0.0)):
			_fire(cameo)


func _is_gate_satisfied(cameo: Dictionary) -> bool:
	var wd := get_node_or_null("/root/WorldDirector")
	if wd == null:
		return false
	if wd.cycle < int(cameo.get("min_cycle", 0)):
		return false

	# Cap Tier-3+ concurrent arcs. The world sustains one hijacking, not three.
	var tier: int = int(cameo.get("tier", 1))
	if tier >= 3 and _count_active_high_tier() >= MAX_HIGH_TIER_ACTIVE:
		return false

	var gate: Dictionary = cameo.get("gate", {})
	for key in gate.keys():
		var range_spec: Dictionary = gate[key]
		var value: float = _read_state_var(key)
		if range_spec.has("min") and value < float(range_spec["min"]):
			return false
		if range_spec.has("max") and value > float(range_spec["max"]):
			return false
	return true


func _read_state_var(key: String) -> float:
	var wd := get_node_or_null("/root/WorldDirector")
	var pm := get_node_or_null("/root/PlayerManager")
	match key:
		"public_tension":
			return float(wd.global_economy.get("public_tension", 0)) if wd else 0.0
		"senate_alignment":
			return float(wd.global_economy.get("senate_alignment", 50)) if wd else 50.0
		"food_price":
			return float(wd.global_economy.get("food_price", 0)) if wd else 0.0
		"security_presence":
			return float(wd.global_economy.get("security_presence", 0)) if wd else 0.0
		"player_heat":
			return float(pm.heat) if pm else 0.0
		"player_chaos_preference":
			return float(pm.player_chaos_preference) if pm else 0.0
		"player_idealism":
			return float(pm.player_idealism) if pm else 0.0
		"player_stealth_preference":
			return float(pm.player_stealth_preference) if pm else 0.0
		"player_ruthlessness":
			return float(pm.player_ruthlessness) if pm else 0.0
	return 0.0


func _fire(cameo: Dictionary) -> void:
	fired_ids.append(str(cameo.get("id", "")))
	cameo_triggered.emit(cameo)

	var tier: int = int(cameo.get("tier", 1))
	if tier == 1:
		# Whisper — flavor-only NetFeed note and we're done.
		_netfeed(str(cameo.get("headline", "")))
	else:
		# Higher tier — start an active arc
		var arc: Dictionary = {
			"cameo_id": str(cameo.get("id", "")),
			"definition": cameo,
			"cycles_left": int(cameo.get("arc_duration_cycles", 3)),
			"completed": false,
		}
		active_arcs.append(arc)
		_netfeed(str(cameo.get("intro_headline", "")))
		cameo_arc_started.emit(arc)

	print("Cameo triggered: [%s] %s (tier %d)" % [
		str(cameo.get("archetype", "?")),
		str(cameo.get("name", "?")),
		tier,
	])


# -------------------------------------------------------------
# Higher-tier arcs — completion, per-cycle modifiers, expiry
# -------------------------------------------------------------

# Called by WorldDirector.run_world_cycle (once per day).
func tick_daily() -> void:
	var remaining: Array[Dictionary] = []
	for arc in active_arcs:
		if bool(arc.get("completed", false)):
			continue
		_apply_cycle_modifiers(arc)
		arc["cycles_left"] = int(arc.get("cycles_left", 0)) - 1
		if int(arc["cycles_left"]) <= 0:
			_expire_arc(arc)
		else:
			remaining.append(arc)
	active_arcs = remaining


# Called by WorldDirector ripples when the player takes a mapped action.
# kind: "sabotage_sector" | "leak_oligarch" | "leak_sector"
# target_ref: sector name or oligarch_id
func check_action_match(kind: String, target_ref: String) -> void:
	var remaining: Array[Dictionary] = []
	for arc in active_arcs:
		if bool(arc.get("completed", false)):
			continue
		var obj: Dictionary = arc.definition.get("objective", {})
		if str(obj.get("kind", "")) == kind and str(obj.get("target_ref", "")) == target_ref:
			_complete_arc(arc)
		else:
			remaining.append(arc)
	active_arcs = remaining


func _complete_arc(arc: Dictionary) -> void:
	arc["completed"] = true
	var def: Dictionary = arc.definition
	var reward: Dictionary = def.get("reward", {})

	var pm := get_node_or_null("/root/PlayerManager")
	var wd := get_node_or_null("/root/WorldDirector")

	if pm and reward.has("credits"):
		pm.add_credits(int(reward.credits), "cameo: %s" % str(def.get("name", "")))
	if pm and reward.has("idealism_bump"):
		pm.bump_playstyle(0.0, 0.0, float(reward.idealism_bump), 0.0)
	if wd:
		if reward.has("tension_delta"):
			wd.global_economy["public_tension"] = clamp(
				int(wd.global_economy.get("public_tension", 0)) + int(reward.tension_delta),
				0, 100)
		if reward.has("senate_alignment_delta"):
			wd.global_economy["senate_alignment"] = clamp(
				int(wd.global_economy.get("senate_alignment", 50)) + int(reward.senate_alignment_delta),
				0, 100)

	_netfeed(str(def.get("completion_headline", "")))
	cameo_arc_completed.emit(arc)


func _expire_arc(arc: Dictionary) -> void:
	var def: Dictionary = arc.definition
	_netfeed(str(def.get("timeout_headline", "")))
	cameo_arc_expired.emit(arc)


func _apply_cycle_modifiers(arc: Dictionary) -> void:
	var mods: Dictionary = arc.definition.get("while_active_modifiers", {})
	if mods.is_empty():
		return
	var wd := get_node_or_null("/root/WorldDirector")
	if wd == null:
		return
	for key in mods.keys():
		var delta: int = int(mods[key])
		if wd.global_economy.has(key):
			wd.global_economy[key] = clamp(
				int(wd.global_economy[key]) + delta, 0, 100)


func _count_active_high_tier() -> int:
	var n: int = 0
	for arc in active_arcs:
		if bool(arc.get("completed", false)):
			continue
		if int(arc.definition.get("tier", 1)) >= 3:
			n += 1
	return n


func _netfeed(headline: String) -> void:
	if headline == "":
		return
	var wd := get_node_or_null("/root/WorldDirector")
	if wd == null:
		return
	var event := {
		"type": "NEWS_TICKER",
		"headline": headline,
		"timestamp": Time.get_unix_time_from_system(),
	}
	wd.netfeed_history.append(event)
	wd.netfeed_event_generated.emit(event)
