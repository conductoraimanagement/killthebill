extends Node
class_name Chronicle

# =============================================================
# Chronicle: the run's narrative artifact.
#
# Subscribes to TimeSystem.month_advanced. At each month boundary,
# captures a snapshot diff against the previous snapshot — top
# headlines from the month, economy deltas, bills resolved, cameos
# fired, oligarchs killed. The accumulated list of MonthlyRecaps is
# the player's year in review, displayed on the victory/defeat
# modal and serializable with world configs.
# =============================================================

signal recap_appended(recap: Dictionary)

var recaps: Array = []

# Snapshot captured at the start of the current (ongoing) month,
# so at month rollover we can diff and generate the recap.
var _month_start_snapshot: Dictionary = {}


func _ready() -> void:
	var ts := get_node_or_null("/root/TimeSystem")
	if ts:
		if not ts.month_advanced.is_connected(_on_month_advanced):
			ts.month_advanced.connect(_on_month_advanced)


func reset() -> void:
	recaps.clear()
	_month_start_snapshot = _take_snapshot()


# Called when month just rolled over. `new_month` is the month we're
# entering (e.g. 2, 3...); the recap captures the month that JUST ENDED.
func _on_month_advanced(new_month: int) -> void:
	var end_snap: Dictionary = _take_snapshot()
	var ending_month: int = new_month - 1
	if ending_month >= 1:
		var recap: Dictionary = _compose_recap(ending_month, _month_start_snapshot, end_snap)
		recaps.append(recap)
		recap_appended.emit(recap)
	_month_start_snapshot = end_snap


func _take_snapshot() -> Dictionary:
	var wd := get_node_or_null("/root/WorldDirector")
	if wd == null:
		return {}
	var living: int = 0
	for o in wd.oligarchs:
		if o.alive:
			living += 1

	var bill_count: int = 0
	var senate := get_node_or_null("/root/SenateDirector")
	if senate:
		bill_count = senate.bill_history.size()

	var pm := get_node_or_null("/root/PlayerManager")
	var credits: int = int(pm.credits) if pm else 0
	var heat: int = int(pm.heat) if pm else 0

	var cameo_fired_count: int = 0
	var cameos := get_node_or_null("/root/CulturalCameos")
	if cameos:
		cameo_fired_count = cameos.fired_ids.size()

	return {
		"economy": wd.global_economy.duplicate(true),
		"netfeed_count": wd.netfeed_history.size(),
		"oligarchs_alive": living,
		"bill_count": bill_count,
		"credits": credits,
		"heat": heat,
		"cameo_fired_count": cameo_fired_count,
	}


func _compose_recap(month: int, start_snap: Dictionary, end_snap: Dictionary) -> Dictionary:
	var wd := get_node("/root/WorldDirector")
	var senate := get_node_or_null("/root/SenateDirector")
	var cameos := get_node_or_null("/root/CulturalCameos")

	# Slice of NetFeed captured during this month
	var all_headlines: Array = wd.netfeed_history
	var start_idx: int = int(start_snap.get("netfeed_count", 0))
	var end_idx: int = int(end_snap.get("netfeed_count", all_headlines.size()))
	end_idx = min(end_idx, all_headlines.size())
	var month_headlines: Array = []
	for i in range(start_idx, end_idx):
		var h: String = str(all_headlines[i].get("headline", ""))
		if h != "":
			month_headlines.append(h)
	# Keep the last 5 of the month — most recent headlines tend to be
	# the climactic ones.
	var top_headlines: Array = month_headlines.slice(
		max(0, month_headlines.size() - 5), month_headlines.size())

	# Bills resolved this month
	var bills: Array = []
	if senate:
		var bill_start: int = int(start_snap.get("bill_count", 0))
		for i in range(bill_start, senate.bill_history.size()):
			var b: Dictionary = senate.bill_history[i]
			bills.append({
				"title": str(b.get("title", "")),
				"result": str(b.get("result", "")),
				"margin": int(b.get("margin", 0)),
			})

	# Cameos fired this month
	var cameo_names: Array = []
	if cameos:
		var fired: Array = cameos.fired_ids
		var cameo_start: int = int(start_snap.get("cameo_fired_count", 0))
		for i in range(cameo_start, fired.size()):
			# Find the cameo name from id
			for c in cameos.CAMEOS:
				if str(c.get("id", "")) == str(fired[i]):
					cameo_names.append(str(c.get("name", fired[i])))
					break

	# Economy deltas
	var s_eco: Dictionary = start_snap.get("economy", {})
	var e_eco: Dictionary = end_snap.get("economy", {})
	var deltas: Dictionary = {}
	for key in ["food_price", "tech_price", "security_presence", "public_tension", "senate_alignment"]:
		deltas[key] = int(e_eco.get(key, 0)) - int(s_eco.get(key, 0))

	return {
		"month": month,
		"top_headlines": top_headlines,
		"bills": bills,
		"cameos_fired": cameo_names,
		"economy_deltas": deltas,
		"oligarchs_alive_start": int(start_snap.get("oligarchs_alive", 0)),
		"oligarchs_alive_end": int(end_snap.get("oligarchs_alive", 0)),
		"credits_end": int(end_snap.get("credits", 0)),
		"heat_end": int(end_snap.get("heat", 0)),
	}


# Export the chronicle as a text narrative — used by the HUD viewer
# and potentially saved alongside world configs for sharing.
func to_text() -> String:
	if recaps.is_empty():
		return "The year has not yet begun."
	var lines: Array[String] = []
	lines.append("─────── THE CHRONICLE ───────")
	lines.append("")
	for recap in recaps:
		lines.append("MONTH %d" % int(recap.get("month", 0)))
		lines.append("-" .repeat(40))
		for h in recap.get("top_headlines", []):
			lines.append("  • %s" % str(h))

		var bills: Array = recap.get("bills", [])
		if bills.size() > 0:
			lines.append("")
			lines.append("  Senate activity:")
			for b in bills:
				lines.append("    %s [%s, %+d]" % [
					str(b.get("title", "")),
					str(b.get("result", "")),
					int(b.get("margin", 0)),
				])

		var cameos_fired: Array = recap.get("cameos_fired", [])
		if cameos_fired.size() > 0:
			lines.append("")
			lines.append("  Cultural arcs that surfaced:")
			for c in cameos_fired:
				lines.append("    %s" % str(c))

		var deltas: Dictionary = recap.get("economy_deltas", {})
		var nonzero: Array[String] = []
		for key in deltas.keys():
			var v: int = int(deltas[key])
			if v != 0:
				nonzero.append("%s %+d" % [str(key), v])
		if nonzero.size() > 0:
			lines.append("")
			lines.append("  Economy shift: " + ", ".join(nonzero))

		lines.append("")
	return "\n".join(lines)
