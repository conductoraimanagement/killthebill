class_name GigCatalog

# =============================================================
# GigCatalog: the 6 blue-collar gig kinds + humiliation pools.
# Pure data. GigBoard reads GigCatalog.ALL to render listings
# and compute shifts; the humiliation_pool inside each entry
# supplies the offline narrative lines fired on shift completion.
#
# Entry schema:
#   kind              — stable id used by HUD + save
#   title             — display name
#   regions           — array of region_type strings; empty = anywhere
#   hours             — game-hours the shift eats (skipped via TimeSystem)
#   pay               — [min, max] credit range
#   tip_variance      — optional [min, max] extra roll (waiter, delivery)
#   hope_cost         — [min, max] hope drained per shift
#   idealism_drift    — negative bump (you're feeding the thing)
#   humiliation_pool  — offline fallback lines
# =============================================================

const ALL: Array[Dictionary] = [
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
			"The timer on the loading dock ticks out while you're still hauling; the docked hour costs you 14 cr.",
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
			"The app deducted 4 cr for 'late delivery'. The route the app gave you had a closed bridge.",
			"A doorman made you show ID twice and then tipped one credit on a 90 cr order.",
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


# Flavor only — surfaced as NetFeed toast on denial. The real
# mechanical payload is the 30-minute skip, not the text.
const DENIAL_REASONS: Array[String] = [
	"Position filled.",
	"We've decided to move forward with other candidates.",
	"Not a fit at this time.",
	"Thank you for your interest.",
	"This role has been withdrawn.",
	"Unable to proceed with your application.",
]
