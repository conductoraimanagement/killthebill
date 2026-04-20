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


func _ready() -> void:
	print("GigBoard initialized — %d gig kinds in catalog." % GigCatalog.ALL.size())


# Returns catalog entries available in the player's current region.
func listings_for_region(region_type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g in GigCatalog.ALL:
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
	for g in GigCatalog.ALL:
		if str(g.get("kind", "")) == kind:
			return g
	return {}




func _denial_reason() -> String:
	return GigCatalog.DENIAL_REASONS[randi() % GigCatalog.DENIAL_REASONS.size()]


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
			"title": WCPool.TITLES[randi() % WCPool.TITLES.size()],
			"company": WCPool.COMPANIES[randi() % WCPool.COMPANIES.size()],
			"description": WCPool.DESCRIPTIONS[randi() % WCPool.DESCRIPTIONS.size()],
			"monthly_salary": randi_range(2000, 4000),
		}
		wc_listings.append(listing)
	wc_listings_refreshed.emit()


# Async: try LLM first, fall back to offline pool. Callback signature:
#   func(gauntlet: Dictionary) -> void
# where gauntlet = {listing_id, title, company, questions: [...]}.
# HUD uses this (not build_interview_gauntlet directly) so per-run
# unique interview copy is generated when LLMManager has an API key.
func request_interview_gauntlet(listing_id: String, callback: Callable) -> void:
	var listing: Dictionary = _find_wc_listing(listing_id)
	if listing.is_empty() or not callback.is_valid():
		if callback.is_valid():
			callback.call({})
		return

	var llm := get_node_or_null("/root/LLMManager")
	if llm == null:
		callback.call(_assemble_gauntlet_from_pool(listing))
		return
	# LLMManager.request_wc_gauntlet routes to offline fallback when no
	# API key is configured — in that case the callback gets {} and we
	# fall back to the pool here.
	llm.request_wc_gauntlet(listing, Callable(self, "_on_llm_gauntlet_response").bind(listing_id, callback))


func _on_llm_gauntlet_response(llm_response: Dictionary, listing_id: String, forward_to: Callable) -> void:
	var listing: Dictionary = _find_wc_listing(listing_id)
	if listing.is_empty():
		if forward_to.is_valid():
			forward_to.call({})
		return

	var gauntlet: Dictionary = _normalize_llm_gauntlet(llm_response, listing)
	if gauntlet.is_empty():
		# LLM returned empty, malformed, or offline fallback — use pool.
		gauntlet = _assemble_gauntlet_from_pool(listing)

	wc_gauntlet_ready.emit(listing_id, gauntlet)
	if forward_to.is_valid():
		forward_to.call(gauntlet)


# Pull out usable {questions} from the LLM payload and wrap with the
# listing metadata the HUD expects. Returns {} if the response didn't
# carry 3 questions × 4 options with labels + rejection_fragment.
func _normalize_llm_gauntlet(raw: Dictionary, listing: Dictionary) -> Dictionary:
	if raw.is_empty() or not raw.has("questions"):
		return {}
	var questions: Array = raw.questions
	if questions.size() < 3:
		return {}
	var cleaned: Array[Dictionary] = []
	for q_raw in questions.slice(0, 3):
		if typeof(q_raw) != TYPE_DICTIONARY:
			return {}
		var q: Dictionary = q_raw
		var opts_raw: Array = q.get("options", [])
		if opts_raw.size() < 4:
			return {}
		var opts: Array[Dictionary] = []
		for o_raw in opts_raw.slice(0, 4):
			if typeof(o_raw) != TYPE_DICTIONARY:
				return {}
			var o: Dictionary = o_raw
			var label: String = str(o.get("label", ""))
			var frag: String = str(o.get("rejection_fragment", ""))
			if label == "" or frag == "":
				return {}
			opts.append({"label": label, "rejection_fragment": frag})
		cleaned.append({"prompt": str(q.get("prompt", "")), "options": opts})

	return {
		"listing_id": str(listing.get("id", "")),
		"title": str(listing.get("title", "")),
		"company": str(listing.get("company", "")),
		"questions": cleaned,
	}


func _assemble_gauntlet_from_pool(listing: Dictionary) -> Dictionary:
	# Synonym for build_interview_gauntlet that takes a listing dict
	# directly — called from the LLM response path when we need to fall
	# back mid-flow.
	var pool: Array = WCPool.INTERVIEW_QUESTIONS.duplicate()
	pool.shuffle()
	var picked: Array[Dictionary] = []
	for i in range(min(3, pool.size())):
		var q: Dictionary = pool[i].duplicate(true)
		var opts: Array = q.options.duplicate()
		opts.shuffle()
		q["options"] = opts
		picked.append(q)
	return {
		"listing_id": str(listing.get("id", "")),
		"title": str(listing.get("title", "")),
		"company": str(listing.get("company", "")),
		"questions": picked,
	}


# Synchronous offline-only build. Kept for any caller that wants the
# pool directly (tests, migrations). HUD uses request_interview_gauntlet.
func build_interview_gauntlet(listing_id: String) -> Dictionary:
	var listing: Dictionary = _find_wc_listing(listing_id)
	if listing.is_empty():
		return {}

	# Pick 3 distinct questions from the pool.
	var pool: Array = WCPool.INTERVIEW_QUESTIONS.duplicate()
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
		var preamble: String = WCPool.REJECTION_PREAMBLES[randi() % WCPool.REJECTION_PREAMBLES.size()]
		var closing: String = WCPool.REJECTION_CLOSINGS[randi() % WCPool.REJECTION_CLOSINGS.size()]
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
