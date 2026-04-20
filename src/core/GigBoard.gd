extends Node

# =============================================================
# GigBoard: the low-status job layer — the compliance path.
#
# The player opens the gig board on a computer (home apartment
# when housed; a public terminal when homeless — deferred).
# They pick a shift; ~40% of applications are silently denied,
# no reason given. Successful shifts cost game-time + hope
# (humiliation dialogue), pay USD wages that accrue into
# PlayerManager.pending_wages, and deposit every 7 days on
# TimeSystem.payday.
#
# GIGS are gated by current_region (a waiter only works the
# Elite, a day-laborer only works Industrial). The board only
# shows gigs available in the player's current region.
# =============================================================

signal gig_application_denied(gig_kind: String, reason: String)
signal gig_shift_completed(gig_kind: String, pay: int, humiliation_line: String)
signal gig_listing_refreshed()

const DENIAL_PROBABILITY: float = 0.40

# Every gig catalog entry:
#   kind             — stable id used by HUD + save
#   title            — display name on the listing
#   regions          — array of region_type strings; empty = anywhere
#   hours            — game-hours the shift eats (skipped via TimeSystem)
#   pay              — [min, max] USD range
#   tip_variance     — optional [min, max] extra roll (waiter, delivery)
#   hope_cost        — [min, max] hope drained per shift
#   idealism_drift   — negative bump (you're feeding the thing)
#   humiliation_pool — offline fallback lines (LLM seeded in future)
const GIG_CATALOG: Array[Dictionary] = [
	{
		"kind": "dishwasher",
		"title": "Back-of-house dishwasher (shift)",
		"regions": [],  # anywhere
		"hours": 3,
		"pay": [36, 48],
		"tip_variance": [0, 0],
		"hope_cost": [1, 2],
		"idealism_drift": -0.02,
		"humiliation_pool": [
			"The line cook mutters your name wrong for the fourth time. You stop correcting it.",
			"A server dumps a full tray in your pit at 11:47. Nobody offers to help.",
			"The manager docks you fifteen minutes for 'being in the way'. You were mopping.",
			"A party of six leaves without tipping and one of them looked exactly like your old boss's nephew.",
		],
	},
	{
		"kind": "street_sweep",
		"title": "Municipal sidewalk sweep",
		"regions": [],
		"hours": 3,
		"pay": [42, 54],
		"tip_variance": [0, 0],
		"hope_cost": [1, 3],
		"idealism_drift": -0.02,
		"humiliation_pool": [
			"A commuter steps over your pile without looking down. The coffee cup clips your shoulder.",
			"Two kids film you on a burner phone for forty seconds. You don't react. They lose interest.",
			"The shift supervisor reminds you that 'this used to be a punishment job'.",
			"The pile you swept an hour ago is back. Someone dumped a coffee filter over it deliberately.",
		],
	},
	{
		"kind": "trash_hauler",
		"title": "Industrial waste removal",
		"regions": ["INDUSTRIAL"],
		"hours": 4,
		"pay": [54, 72],
		"tip_variance": [0, 0],
		"hope_cost": [2, 3],
		"idealism_drift": -0.01,
		"humiliation_pool": [
			"The foreman says 'don't worry, this stuff's only lightly toxic'. He is not wearing a mask.",
			"You lift something that cracks open and seeps into your left boot. Nobody comps a new pair.",
			"The timer on the loading dock ticks out while you're still hauling; the docked hour costs you $14.",
			"A middle-manager watches you work through the window, phone out, clearly texting about you.",
		],
	},
	{
		"kind": "delivery_runner",
		"title": "Package delivery runner (gig-app)",
		"regions": ["URBAN_SLUM", "TRANSIT"],
		"hours": 3,
		"pay": [30, 54],
		"tip_variance": [0, 22],
		"hope_cost": [1, 2],
		"idealism_drift": -0.02,
		"humiliation_pool": [
			"The customer rated you three stars for 'doorstep placement'. The package arrived in six minutes.",
			"The app deducted $4 for 'late delivery'. The route the app gave you had a closed bridge.",
			"A doorman made you show ID twice and then tipped one dollar on a $90 order.",
			"The customer cracked the door, took the bag, and closed it without looking at you.",
		],
	},
	{
		"kind": "waiter",
		"title": "Banquet service (tipped)",
		"regions": ["URBAN_ELITE"],
		"hours": 3,
		"pay": [30, 45],
		"tip_variance": [0, 60],
		"hope_cost": [2, 3],
		"idealism_drift": -0.03,
		"humiliation_pool": [
			"The table of Enclave associates tip 0.5% and leave the receipt annotated with 'service was adequate'.",
			"A patron called you by the previous server's name for an hour. You said nothing.",
			"The maître d' reminds you that your uniform shirt is 'almost clean enough'. It is clean.",
			"A former colleague from your old firm sits at table six and pretends not to recognize you.",
		],
	},
	{
		"kind": "day_labor",
		"title": "Construction day-labor",
		"regions": ["INDUSTRIAL"],
		"hours": 4,
		"pay": [60, 84],
		"tip_variance": [0, 0],
		"hope_cost": [2, 3],
		"idealism_drift": -0.01,
		"humiliation_pool": [
			"The site foreman calls you 'number seven' all day. There are eleven day-laborers.",
			"Your shift runs 20 minutes over. The clock in the office was set fast; no one corrects it.",
			"A bolt drops on your left hand. The foreman asks if you want to file a report or keep working.",
			"The safety briefing is a printed sheet you're asked to sign unread. You sign it.",
		],
	},
]


func _ready() -> void:
	print("GigBoard initialized — %d gig kinds in catalog." % GIG_CATALOG.size())


# Returns catalog entries available in the player's current region.
func listings_for_region(region_type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g in GIG_CATALOG:
		var regions: Array = g.get("regions", [])
		if regions.is_empty() or region_type in regions:
			out.append(g)
	return out


# Player clicked APPLY on a listing. Returns a descriptor dict:
#   { denied: bool, pay: int, hours: int, humiliation: String, hope_delta: int }
# On denial: no pay, 30 game-mins wasted, no hope hit.
# On success: pay accrues to PlayerManager.pending_wages (deposits
# on TimeSystem.payday), game-time advances by hours, humiliation line
# fires, hope takes a hit.
func apply_for_shift(gig_kind: String) -> Dictionary:
	var entry: Dictionary = _find_entry(gig_kind)
	if entry.is_empty():
		return {"denied": true, "pay": 0, "hours": 0, "humiliation": "", "hope_delta": 0}

	var ts := get_node_or_null("/root/TimeSystem")
	var pm := get_node_or_null("/root/PlayerManager")

	# Denial roll — no reason given, ~30 game-mins burned applying.
	if randf() < DENIAL_PROBABILITY:
		if ts:
			ts.skip_hours(0.5)
		gig_application_denied.emit(gig_kind, _denial_reason())
		return {"denied": true, "pay": 0, "hours": 0, "humiliation": "", "hope_delta": 0}

	# Accepted — compute pay, advance game-time, charge hope, accrue wages.
	var pay_range: Array = entry.get("pay", [0, 0])
	var pay: int = randi_range(int(pay_range[0]), int(pay_range[1]))
	var tip_range: Array = entry.get("tip_variance", [0, 0])
	if int(tip_range[1]) > 0:
		pay += randi_range(int(tip_range[0]), int(tip_range[1]))
	var hours: int = int(entry.get("hours", 3))
	var hope_range: Array = entry.get("hope_cost", [1, 2])
	var hope_hit: int = randi_range(int(hope_range[0]), int(hope_range[1]))
	var idealism_drift: float = float(entry.get("idealism_drift", -0.02))
	var humiliation_pool: Array = entry.get("humiliation_pool", [""])
	var humiliation: String = humiliation_pool[randi() % humiliation_pool.size()]

	if ts:
		ts.skip_hours(float(hours))
	if pm:
		pm.accrue_wages(pay, gig_kind)
		pm.add_hope(-float(hope_hit), "%s shift" % str(entry.get("title", gig_kind)))
		pm.bump_playstyle(0.0, 0.0, idealism_drift, 0.0)

	gig_shift_completed.emit(gig_kind, pay, humiliation)
	return {
		"denied": false,
		"pay": pay,
		"hours": hours,
		"humiliation": humiliation,
		"hope_delta": -hope_hit,
	}


func _find_entry(kind: String) -> Dictionary:
	for g in GIG_CATALOG:
		if str(g.get("kind", "")) == kind:
			return g
	return {}


# Flavor only — the HUD toast shows the player a brief, anonymous
# nothing. The real mechanical payload is the wasted 30 minutes.
const _DENIAL_REASONS: Array[String] = [
	"Position filled.",
	"We've decided to move forward with other candidates.",
	"Not a fit at this time.",
	"Thank you for your interest.",
	"This role has been withdrawn.",
	"Unable to proceed with your application.",
]


func _denial_reason() -> String:
	return _DENIAL_REASONS[randi() % _DENIAL_REASONS.size()]
