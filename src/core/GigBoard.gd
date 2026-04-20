extends Node

# =============================================================
# GigBoard: the low-status job layer — the compliance path.
#
# The player opens the gig board on a computer (home apartment
# when housed; a public terminal when homeless — deferred).
# They pick a shift; ~40% of applications are silently denied,
# no reason given. Successful shifts cost game-time + hope
# (humiliation dialogue), pay wages (cr) that accrue into
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
signal wc_listings_refreshed()
signal wc_gauntlet_ready(listing_id: String, gauntlet: Dictionary)
signal wc_interview_resolved(listing_id: String, accepted: bool, outcome: Dictionary)

const DENIAL_PROBABILITY: float = 0.40

# White-collar listings — always present, brutal to access. The player
# sees attractive monthly salaries, passes an absurd 3-round interview
# gauntlet, and 95% of the time gets rejected. The 5% that land pay
# weekly (monthly_salary / 4), lock weekday mornings, and carry a 10%
# weekly firing roll. See docs/04-player/gigs.md.
const WC_ACCEPTANCE_RATE: float = 0.05
const WC_LISTINGS_PER_REFRESH: int = 4   # how many appear at once
const WC_REFRESH_EVERY_DAYS: int = 7     # re-rolls weekly

# Every gig catalog entry:
#   kind             — stable id used by HUD + save
#   title            — display name on the listing
#   regions          — array of region_type strings; empty = anywhere
#   hours            — game-hours the shift eats (skipped via TimeSystem)
#   pay              — [min, max] credit range
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


# =============================================================
# WHITE-COLLAR LISTINGS — always present, always brutal.
# =============================================================
#
# Offline content pools drive generation today. `LLMManager` hookup is
# stubbed via `_maybe_llm_generate_listing()` / `_maybe_llm_generate_gauntlet()`
# — when the LLM path lands, it overrides these with per-run unique
# copy. Until then, these pools keep the compliance theatre running.

var wc_listings: Array[Dictionary] = []
var _wc_listing_serial: int = 0
var _wc_last_refresh_day: int = 0

const _WC_TITLES: Array[String] = [
	"Associate Brand Strategist",
	"Junior Compliance Analyst",
	"Content Moderator (Temp, 90-day)",
	"Assistant Director of Vibes",
	"Senior Junior Product Evangelist",
	"Growth Enablement Specialist",
	"Revenue Operations Generalist",
	"Customer Outcomes Coordinator",
	"People & Culture Analyst",
	"Strategic Initiatives Fellow",
	"Digital Transformation Consultant (Contract)",
	"Head of Adjacency (Individual Contributor)",
]

const _WC_COMPANIES: Array[String] = [
	"Vextol Capital Partners",
	"Krynne Systems Group",
	"Aurelius Wellness Holdings",
	"Paperclip & Thorne, LLP",
	"Convergent Harmony Consulting",
	"OpticalLatitude Inc.",
	"Ascendant Logistics Co-op",
	"Meridian Compliance Bureau",
	"Fifth-Wave Outcomes",
	"Gant Trust & Fiduciary",
	"Monarch Parallel Ventures",
	"Quantum Lattice Research Foundation",
]

const _WC_DESCRIPTIONS: Array[String] = [
	"Drive cross-functional alignment across high-leverage workstreams. Travel 15%. Snacks.",
	"Own the compliance story end-to-end. Move fast without breaking the audit trail.",
	"Seeking a self-starter who thrives in ambiguity and can pivot without complaining.",
	"Hybrid role. Six days in-office, one day 'flex'. Laptop provided (recovered at separation).",
	"Build the future of [BLANK]. We'll figure out what [BLANK] means together.",
	"Non-traditional compensation structure. Equity-leaning. Ask in round two.",
	"Looking for a 'founder mindset'. This is not a founder role.",
	"Report to three directors. Priority-negotiate across all three weekly.",
	"Expected: 50 hours. Billed: 40. 'Growth mindset' essential.",
	"The successful candidate will be humble, hungry, smart — and 'unreasonably available'.",
]

const _WC_INTERVIEW_QUESTIONS: Array[Dictionary] = [
	{
		"prompt": "Describe a time you exceeded expectations without extra compensation. What did you learn about yourself?",
		"options": [
			{"label": "I stayed late on a launch. Learned I can do more.", "rejection_fragment": "we found your response at (1) to lean excessively on time-based heroics, which is orthogonal to our culture of sustainable overperformance"},
			{"label": "I reframed the problem and avoided scope creep.", "rejection_fragment": "your answer at (1) revealed a preference for boundary-setting that does not align with the adjacency model we're building toward"},
			{"label": "I don't believe in unpaid labor.", "rejection_fragment": "your candor on (1) was refreshing, but we require a certain flexibility around the compensation conversation"},
			{"label": "I delegated upward to create visibility.", "rejection_fragment": "on (1), 'delegating upward' reads to our panel as misreading your lane — a common failure mode"},
		],
	},
	{
		"prompt": "Estimate the number of pigeons currently residing within The Enclave. Show your reasoning.",
		"options": [
			{"label": "~5,000. Back-of-envelope: 1 per 4 residents, minus nets.", "rejection_fragment": "the 5,000 figure at (2) reveals insufficient top-down calibration — a senior hire would have started with airspace volume, not resident density"},
			{"label": "Uncountable — we'd need a stratified sampling method first.", "rejection_fragment": "declining to estimate at (2) signaled a risk aversion our team does not value at this level"},
			{"label": "Zero. Pigeons are prohibited by ordinance 41-C.", "rejection_fragment": "technically correct on (2), but pedantic answers rarely survive the room in a pitch"},
			{"label": "Why is this relevant to the role?", "rejection_fragment": "challenging the premise on (2) was brave — and, in this case, misread"},
		],
	},
	{
		"prompt": "If you were a currently-disrupting consumer brand, which would you be, and why?",
		"options": [
			{"label": "Soap Man Broadcast — grassroots, viral, unapologetic.", "rejection_fragment": "naming Soap Man at (3) raised compliance flags we cannot ignore post-hire"},
			{"label": "Indexed Debt — transparent, accountable, unstoppable.", "rejection_fragment": "the Indexed Debt reference at (3) is not one our brand legal team wants adjacent to us"},
			{"label": "Paperclip & Thorne — steady, trusted, adult.", "rejection_fragment": "on (3) you cited our own company, which reads as either sycophancy or a lack of imagination"},
			{"label": "The concept of 'disruption' is downstream of late-capital exhaustion.", "rejection_fragment": "your answer at (3) was 'thought-provoking', per the panel — which is a polite red flag"},
		],
	},
	{
		"prompt": "What's your biggest weakness? (Note: answers framed as strengths will be penalized.)",
		"options": [
			{"label": "I work too hard and burn out others.", "rejection_fragment": "on (4) you violated the preamble of the question itself, which the panel found self-diagnostic"},
			{"label": "I struggle to let go when a project isn't right.", "rejection_fragment": "(4) telegraphed a perfectionism that at our stage reads as risk-averse"},
			{"label": "I'm not good at performing enthusiasm I don't feel.", "rejection_fragment": "the honesty on (4) was appreciated — and, candidly, disqualifying"},
			{"label": "I don't have a meaningful weakness I'd disclose in an interview.", "rejection_fragment": "refusing to disclose on (4) is a tell the panel found louder than any admission"},
		],
	},
	{
		"prompt": "Why do you want to work here specifically, as opposed to a competitor?",
		"options": [
			{"label": "I've followed your work for years — it sets the standard.", "rejection_fragment": "on (5) you could not name a specific initiative beyond generalities, which broke the spell"},
			{"label": "Your compensation band is more aligned with my situation.", "rejection_fragment": "framing (5) around compensation was received as transactional in a way the panel does not reward"},
			{"label": "This is the role that was open when I needed one.", "rejection_fragment": "(5) was admirably honest. This is an unseeded culture; honest signal is a rare mistake here"},
			{"label": "I don't, particularly — I want the role, not the brand.", "rejection_fragment": "drawing the distinction at (5) was a structural misread of what we interview for"},
		],
	},
	{
		"prompt": "Walk us through a disagreement with a previous manager. What was the outcome?",
		"options": [
			{"label": "I escalated through proper channels. The policy changed.", "rejection_fragment": "'escalating through proper channels' at (6) reads as un-collaborative in our matrix"},
			{"label": "I presented data, they overruled me, we moved on.", "rejection_fragment": "the stoic acceptance at (6) suggested passivity where we need friction"},
			{"label": "I was right, they were wrong, I left.", "rejection_fragment": "the framing of (6) as binary right/wrong revealed a conflict-resolution style we've historically found incompatible"},
			{"label": "I haven't disagreed with a manager. That's how I work.", "rejection_fragment": "on (6) you presented as non-confrontational to a degree that concerned the debrief panel"},
		],
	},
]

const _WC_FINAL_REJECTION_PREAMBLES: Array[String] = [
	"After careful consideration from the full hiring panel, we regret to inform you that we've decided to move forward with other candidates.",
	"Thank you for your time today. While your background is impressive, we've elected to pursue other applicants who more closely match what we are looking for right now.",
	"We appreciate you taking the time to interview with us. Unfortunately, we will not be moving forward with your candidacy at this time.",
	"After internal deliberation, the team has opted to continue its search.",
]

const _WC_FINAL_REJECTION_CLOSINGS: Array[String] = [
	"We encourage you to re-apply in 12 months once you've had more time to grow in your current role.",
	"We wish you the very best in your ongoing search and future career.",
	"Please do keep us in mind for roles that may be more aligned with your profile in the future.",
	"We appreciate your interest in our organization and wish you continued success.",
]


# Rolls WC listings if we've crossed the refresh cadence (weekly).
# Called when the gig panel is opened OR on TimeSystem.payday.
func ensure_wc_listings_fresh() -> void:
	var ts := get_node_or_null("/root/TimeSystem")
	var current_day: int = int(ts.day) if ts else 1
	if wc_listings.is_empty() or (current_day - _wc_last_refresh_day) >= WC_REFRESH_EVERY_DAYS:
		_regenerate_wc_listings()
		_wc_last_refresh_day = current_day


func _regenerate_wc_listings() -> void:
	wc_listings.clear()
	for i in range(WC_LISTINGS_PER_REFRESH):
		_wc_listing_serial += 1
		var listing := {
			"id": "wc_%04d" % _wc_listing_serial,
			"title": _WC_TITLES[randi() % _WC_TITLES.size()],
			"company": _WC_COMPANIES[randi() % _WC_COMPANIES.size()],
			"description": _WC_DESCRIPTIONS[randi() % _WC_DESCRIPTIONS.size()],
			"monthly_salary": randi_range(2000, 4000),
		}
		wc_listings.append(listing)
	wc_listings_refreshed.emit()


# Build a 3-question interview gauntlet from the offline pool. Each
# question has 4 options — every one leads to a rejection fragment
# that's assembled into the final rejection paragraph. Shuffling keeps
# the same role from feeling identical across replays.
func build_interview_gauntlet(listing_id: String) -> Dictionary:
	var listing: Dictionary = _find_wc_listing(listing_id)
	if listing.is_empty():
		return {}

	# Pick 3 distinct questions from the pool.
	var pool: Array = _WC_INTERVIEW_QUESTIONS.duplicate()
	pool.shuffle()
	var picked: Array[Dictionary] = []
	for i in range(min(3, pool.size())):
		var q: Dictionary = pool[i].duplicate(true)
		# Shuffle the options so position-bias doesn't train the player.
		var opts: Array = q.options.duplicate()
		opts.shuffle()
		q["options"] = opts
		picked.append(q)

	var gauntlet := {
		"listing_id": listing_id,
		"title": listing.title,
		"company": listing.company,
		"questions": picked,
	}
	wc_gauntlet_ready.emit(listing_id, gauntlet)
	return gauntlet


# Player submitted their 3 answers. Roll the 5% acceptance and return
# either an acceptance dict or a compiled rejection paragraph referencing
# each specific answer. Clears the listing from the board either way —
# you get one shot per posting.
func submit_interview_answers(listing_id: String, gauntlet: Dictionary, answer_indices: Array) -> Dictionary:
	var listing: Dictionary = _find_wc_listing(listing_id)
	if listing.is_empty() or gauntlet.is_empty():
		return {"accepted": false, "letter": "Your application has expired."}

	var pm := get_node_or_null("/root/PlayerManager")
	var ts := get_node_or_null("/root/TimeSystem")
	# Applying costs 2 game-hours regardless of outcome.
	if ts:
		ts.skip_hours(2.0)

	var accepted: bool = randf() < WC_ACCEPTANCE_RATE
	var outcome: Dictionary = {}

	if accepted:
		var salary: int = int(listing.get("monthly_salary", 2500))
		outcome = {
			"accepted": true,
			"listing_id": listing_id,
			"title": str(listing.get("title", "")),
			"company": str(listing.get("company", "")),
			"monthly_salary": salary,
			"letter": "Congratulations — %s at %s. Starting salary: %d cr/month. Please arrive Monday. Your on-boarding has been pre-scheduled." % [
				str(listing.get("title", "")), str(listing.get("company", "")), salary,
			],
		}
		if pm:
			pm.accept_wc_role(listing.title, listing.company, salary)
			pm.add_hope(15.0, "hired at %s" % listing.company)
			pm.bump_playstyle(0.0, 0.0, -0.05, 0.0)   # compliance dents idealism
	else:
		# Compile the rejection letter from the fragments the player's
		# answers generated. The specificity is the humiliation.
		var fragments := PackedStringArray()
		var qs: Array = gauntlet.get("questions", [])
		for i in range(qs.size()):
			var idx: int = int(answer_indices[i]) if i < answer_indices.size() else 0
			var opts: Array = qs[i].get("options", [])
			if idx < opts.size():
				fragments.append(str(opts[idx].get("rejection_fragment", "")))
		var preamble: String = _WC_FINAL_REJECTION_PREAMBLES[randi() % _WC_FINAL_REJECTION_PREAMBLES.size()]
		var closing: String = _WC_FINAL_REJECTION_CLOSINGS[randi() % _WC_FINAL_REJECTION_CLOSINGS.size()]
		var body: String = preamble + " Specifically, " + "; ".join(fragments) + ". " + closing
		outcome = {
			"accepted": false,
			"listing_id": listing_id,
			"title": str(listing.get("title", "")),
			"company": str(listing.get("company", "")),
			"letter": body,
		}
		if pm:
			pm.add_hope(-randi_range(3, 5), "WC rejection: %s" % listing.company)
			pm.bump_playstyle(0.0, 0.0, -0.03, 0.0)

	# Remove the listing — one shot per posting.
	_remove_wc_listing(listing_id)
	wc_interview_resolved.emit(listing_id, accepted, outcome)
	return outcome


func _find_wc_listing(listing_id: String) -> Dictionary:
	for l in wc_listings:
		if str(l.get("id", "")) == listing_id:
			return l
	return {}


func _remove_wc_listing(listing_id: String) -> void:
	var remaining: Array[Dictionary] = []
	for l in wc_listings:
		if str(l.get("id", "")) != listing_id:
			remaining.append(l)
	wc_listings = remaining
	wc_listings_refreshed.emit()
