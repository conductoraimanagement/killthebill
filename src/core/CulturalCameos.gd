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
]

var fired_ids: Array[String] = []


func reset() -> void:
	fired_ids.clear()


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

	var wd := get_node_or_null("/root/WorldDirector")
	if wd == null:
		return
	var event := {
		"type": "NEWS_TICKER",
		"headline": str(cameo.get("headline", "")),
		"timestamp": Time.get_unix_time_from_system(),
	}
	wd.netfeed_history.append(event)
	wd.netfeed_event_generated.emit(event)
	print("Cameo triggered: [%s] %s" % [
		str(cameo.get("archetype", "?")),
		str(cameo.get("name", "?")),
	])
