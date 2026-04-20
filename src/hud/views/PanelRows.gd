class_name PanelRows

# =============================================================
# PanelRows: pure BBCode formatters for the HUD list panels.
#
# state(dict) → BBCode string. No side effects, no signals, no
# node lookups (other than WorldDirector for the job-row TTL,
# which is a read). Extracted out of HUD.gd so panel copy can
# be tuned in isolation.
#
# HUD still owns the Panel / RichTextLabel / refresh scheduling.
# These functions just build the text.
# =============================================================


# JOB BOARD rows

static func cameo_arc_row(arc: Dictionary) -> String:
	var def: Dictionary = arc.definition
	var tier: int = int(def.get("tier", 2))
	var badge: String = "CAMEO T%d" % tier
	var cycles_left: int = int(arc.get("cycles_left", 0))
	var ttl_color: Color = HudTheme.COL_HOT if cycles_left <= 1 else HudTheme.COL_DIM

	# Multi-step arcs (Tier 4) show the CURRENT step's objective; legacy
	# single-step arcs fall back to def.objective.
	var objective_label: String = ""
	var waiting_note: String = ""
	var steps: Array = def.get("arc_steps", [])
	if steps.is_empty():
		var obj: Dictionary = def.get("objective", {})
		objective_label = str(obj.get("label", ""))
	else:
		var idx: int = int(arc.get("current_step_index", 0))
		if idx < steps.size():
			var step: Dictionary = steps[idx]
			match str(step.get("kind", "")):
				"action_objective":
					objective_label = str(step.get("objective", {}).get("label", ""))
				"accept_prompt":
					waiting_note = "awaiting decision: accept or decline"
				"binary_decision":
					waiting_note = "awaiting decision: the choice"

	var row: String = ""
	var badge_color: Color = Color(0.85, 0.35, 1.00)
	row += "[color=#%s]▸ %s[/color]  [color=#%s]%d cycles left[/color]\n" % [
		HudTheme.hex(badge_color),
		badge,
		HudTheme.hex(ttl_color),
		cycles_left,
	]
	row += "[b][color=#%s]%s[/color][/b]\n" % [HudTheme.hex(HudTheme.COL_FG), str(def.get("name", ""))]
	row += "[color=#%s]%s[/color]\n" % [HudTheme.hex(HudTheme.COL_DIM), str(def.get("intro_headline", ""))]
	if waiting_note != "":
		row += "  [color=#%s]⧗ %s[/color]" % [HudTheme.hex(HudTheme.COL_WARN), waiting_note]
	elif objective_label != "":
		row += "  → [color=#%s]%s[/color]" % [HudTheme.hex(HudTheme.COL_WARN), objective_label]
	return row


static func job_row(job: Dictionary, current_cycle: int) -> String:
	var src_type: String = str(job.get("source_type", ""))
	var badge: String
	var badge_color: Color
	if src_type == "resistance_cell":
		badge = "CELL"
		badge_color = HudTheme.COL_ACCENT       # rebel fire, not oligarch red
	elif src_type == "npc_fixer":
		badge = "FIXER"
		badge_color = HudTheme.COL_COOL
	else:
		badge = "JOB"
		badge_color = HudTheme.COL_DIM

	var cycles_left: int = int(job.get("expires_at_cycle", 0)) - current_cycle
	var ttl_color := HudTheme.COL_HOT if cycles_left <= 1 else HudTheme.COL_DIM

	var row: String = ""
	row += "[color=#%s]▸ %s[/color]  [color=#%s]+%d cr[/color]  [color=#%s]%d cycles left[/color]\n" % [
		HudTheme.hex(badge_color),
		badge,
		HudTheme.hex(HudTheme.COL_COOL),
		int(job.get("bounty", 0)),
		HudTheme.hex(ttl_color),
		cycles_left,
	]
	row += "[b][color=#%s]%s[/color][/b]\n" % [HudTheme.hex(HudTheme.COL_FG), str(job.get("source_name", "unknown"))]
	row += "[color=#%s]%s[/color]\n" % [HudTheme.hex(HudTheme.COL_DIM), str(job.get("framing", ""))]
	row += "  → [color=#%s]%s[/color]" % [HudTheme.hex(HudTheme.COL_WARN), str(job.get("target_label", ""))]
	return row


# RESOURCE + FACTION COLORS — pure value → Color maps

static func color_for_credits(value: int) -> Color:
	if value >= 1000: return HudTheme.COL_COOL
	if value >= 300:  return HudTheme.COL_FG
	if value >= 100:  return HudTheme.COL_WARN
	return HudTheme.COL_HOT


static func color_for_heat(value: int) -> Color:
	if value > 60: return HudTheme.COL_HOT
	if value > 30: return HudTheme.COL_WARN
	return HudTheme.COL_FG


static func color_for_hope(value: int) -> Color:
	if value <= 20:  return HudTheme.COL_HOT
	if value <= 50:  return HudTheme.COL_WARN
	return HudTheme.COL_FG


# Early (cyan) → mid (fg) → late (warn) → final (hot red).
static func color_for_month(month: int) -> Color:
	if month >= 13: return HudTheme.COL_HOT
	if month >= 10: return HudTheme.COL_WARN
	if month >= 4:  return HudTheme.COL_FG
	return HudTheme.COL_COOL


static func color_for_faction(faction: String) -> Color:
	match faction:
		"CORPORATE_BLOC": return HudTheme.COL_HOT
		"POPULIST":       return HudTheme.COL_ACCENT
		"REFORM":         return HudTheme.COL_COOL
		"INDEPENDENT":    return HudTheme.COL_DIM
	return HudTheme.COL_DIM


static func shorten_faction(faction: String) -> String:
	match faction:
		"CORPORATE_BLOC": return "CORP_BLOC"
		"POPULIST":       return "POPULIST "
		"REFORM":         return "REFORM   "
		"INDEPENDENT":    return "INDEP    "
	return faction


static func color_for_approval(value: float) -> Color:
	if value > 40.0:  return HudTheme.COL_WARN
	if value > 0.0:   return HudTheme.COL_FG
	if value > -40.0: return HudTheme.COL_DIM
	return HudTheme.COL_HOT


static func action_label(action_id: String) -> String:
	match action_id:
		"leak_scandal":
			return "LEAK SCANDAL TO NETFEED"
		"sell_scandal":
			return "SELL SCANDAL TO MEDIA OLIGARCH"
		"assassinate_oligarch":
			return "MARK FOR ASSASSINATION"
	return action_id.to_upper()


# STATE PANEL rows (top-left — economy readout)

static func econ_row(key: String, value, unit: String) -> String:
	var color_hex := econ_color(key, value)
	return "[color=#%s]%s[/color]  [color=#%s]%s[/color] [color=#%s]%s[/color]" % [
		HudTheme.hex(HudTheme.COL_DIM),
		key.rpad(18),
		color_hex,
		str(value).rpad(5),
		HudTheme.hex(HudTheme.COL_DIM),
		unit,
	]


# Per-variable color mapping — thresholds chosen so the panel tells
# the player "you should be worried" without needing a legend.
static func econ_color(key: String, value) -> String:
	match key:
		"food_price":
			if value > 250: return HudTheme.hex(HudTheme.COL_HOT)
			if value > 150: return HudTheme.hex(HudTheme.COL_WARN)
			return HudTheme.hex(HudTheme.COL_FG)
		"tech_price":
			if value > 800: return HudTheme.hex(HudTheme.COL_HOT)
			if value > 600: return HudTheme.hex(HudTheme.COL_WARN)
			return HudTheme.hex(HudTheme.COL_FG)
		"security_presence":
			if value > 70: return HudTheme.hex(HudTheme.COL_HOT)
			if value > 50: return HudTheme.hex(HudTheme.COL_WARN)
			return HudTheme.hex(HudTheme.COL_COOL)
		"public_tension":
			if value > 70: return HudTheme.hex(HudTheme.COL_HOT)
			if value > 40: return HudTheme.hex(HudTheme.COL_WARN)
			return HudTheme.hex(HudTheme.COL_FG)
		"senate_alignment":
			if value > 70: return HudTheme.hex(HudTheme.COL_HOT)
			if value < 30: return HudTheme.hex(HudTheme.COL_COOL)
			return HudTheme.hex(HudTheme.COL_FG)
	return HudTheme.hex(HudTheme.COL_FG)


# GIG BOARD rows

static func wc_listing_row(idx: int, listing: Dictionary) -> String:
	var row: String = ""
	row += "[color=#%s]▸ Q%d[/color]  [color=#%s]%d cr/mo salary[/color]\n" % [
		HudTheme.hex(HudTheme.COL_WARN),
		idx + 1,
		HudTheme.hex(HudTheme.COL_COOL),
		int(listing.get("monthly_salary", 0)),
	]
	row += "[b][color=#%s]%s[/color][/b]  [color=#%s]— %s[/color]\n" % [
		HudTheme.hex(HudTheme.COL_FG),
		str(listing.get("title", "")),
		HudTheme.hex(HudTheme.COL_DIM),
		str(listing.get("company", "")),
	]
	row += "  [color=#%s]%s[/color]" % [HudTheme.hex(HudTheme.COL_DIM), str(listing.get("description", ""))]
	return row


static func gig_row(slot: int, g: Dictionary) -> String:
	var pay_range: Array = g.get("pay", [0, 0])
	var tip_range: Array = g.get("tip_variance", [0, 0])
	var tip_note: String = ""
	if int(tip_range[1]) > 0:
		tip_note = " (+ tip 0–%d cr)" % int(tip_range[1])
	var hours: int = int(g.get("hours", 3))
	var row: String = ""
	row += "[color=#%s]▸ [%d][/color]  [color=#%s]%d–%d cr%s[/color]  [color=#%s]%dh shift[/color]\n" % [
		HudTheme.hex(HudTheme.COL_WARN),
		slot,
		HudTheme.hex(HudTheme.COL_COOL),
		int(pay_range[0]),
		int(pay_range[1]),
		tip_note,
		HudTheme.hex(HudTheme.COL_DIM),
		hours,
	]
	row += "[b][color=#%s]%s[/color][/b]" % [HudTheme.hex(HudTheme.COL_FG), str(g.get("title", ""))]
	return row
