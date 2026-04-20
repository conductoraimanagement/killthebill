extends Node

# =============================================================
# PlayerManager: tracks the player's resources, archetype, and
# the small state that doesn't belong in the world model.
#
# Two live economy fields — credits and heat — are mutated via
# add_credits / spend_credits / add_heat, each emitting a signal
# the HUD listens to. Every source has a reason string for the
# console + future analytics.
# =============================================================

signal credits_changed(new_total: int, delta: int, reason: String)
signal heat_changed(new_total: int, delta: int, reason: String)
signal hope_changed(new_total: int, delta: int, reason: String)
signal housing_status_changed(homeless: bool)
signal defeat_triggered(kind: String, title: String, flavor: String)
signal rent_due_prompt(rent_amount: int, months_behind: int)
signal payday_deposited(amount: int, source_breakdown: Dictionary)
signal pending_wages_changed(total: int)

enum ClassSeed { WHITE_COLLAR, BLUE_COLLAR }

const HEAT_MAX := 100
const HOPE_MAX := 100
const RENT_ARREARS_MONTHS_TO_EVICTION: int = 2   # 2 months unpaid → eviction
const RENT_MIN: int = 700                         # credits — rolled per run
const RENT_MAX: int = 2000

var current_class: ClassSeed = ClassSeed.BLUE_COLLAR

# Player State
var credits: int = 0
var intel_level: int = 0
var social_capital: int = 0
var heat: int = 0

# Survival state. The game's premise: the system is killing you.
# You're jobless. Rent is monthly and your decision — [PAY] or [SKIP]
# at end-of-month. Two months unpaid → eviction. Hope decays passively
# after the severance window; staying alive requires ACTION.
var hope: float = 50.0
var homeless: bool = false
var monthly_rent: int = 1200              # rolled at run-start in [RENT_MIN, RENT_MAX]
var rent_arrears_months: int = 0          # months of unpaid rent
var _rent_due_pending: bool = false       # waiting on player to [PAY]/[SKIP]

# Gig wages accrue here between paydays. Deposited to credits every
# DAYS_PER_WEEK via TimeSystem.payday. Broken out so the HUD can show
# "pending: X cr — next payday in N days".
var pending_wages: int = 0
var pending_wages_breakdown: Dictionary = {}   # gig_kind → cr subtotal

# Finance-sector bookkeeping. debt_held_by_oligarch_id is set by
# WorldDirector after oligarch generation if a Finance oligarch rolled.
# rent_drain_multiplier spikes after a Finance sabotage, decays back.
var debt_held_by_oligarch_id: String = ""
var rent_drain_multiplier: float = 1.0
var _finance_shock_cycles_remaining: int = 0

# Romantic partners — polyamorous. Can court many, at risk and cost
# per partner's personality. See docs/03-characters/relationships.md.
var romantic_partner_ids: Array[String] = []


func is_romantic_partner(npc_id: String) -> bool:
	return npc_id in romantic_partner_ids


func add_romantic_partner(npc_id: String) -> void:
	if npc_id != "" and npc_id not in romantic_partner_ids:
		romantic_partner_ids.append(npc_id)


func remove_romantic_partner(npc_id: String) -> void:
	romantic_partner_ids.erase(npc_id)

# Playstyle trackers (read by cultural cameos to gate archetype rolls).
# See docs/03-characters/cultural-cameos.md — "player profile tracking".
var player_ruthlessness: float = 0.0
var player_idealism: float = 0.0
var player_stealth_preference: float = 0.0
var player_chaos_preference: float = 0.0

var _defeat_locked: bool = false

# Chosen victory path — set at run start by the goal-choice modal.
# "ANY" means any path wins. Otherwise only the matching kind fires
# (see WorldDirector._maybe_fire_victory).
var chosen_victory_path: String = "ANY"

# "Severance" period — months 1-2 — paused hope decay. Rent still drains.
# At start of month 3, severance ends with a NetFeed note. One-shot flag.
var _severance_end_fired: bool = false


func _ready():
	print("PlayerManager initialized.")


func initialize_run(seed: ClassSeed = ClassSeed.BLUE_COLLAR) -> void:
	current_class = seed
	heat = 0
	hope = 50.0
	homeless = false
	rent_arrears_months = 0
	_rent_due_pending = false
	pending_wages = 0
	pending_wages_breakdown.clear()
	_severance_end_fired = false
	debt_held_by_oligarch_id = ""
	rent_drain_multiplier = 1.0
	_finance_shock_cycles_remaining = 0
	romantic_partner_ids.clear()
	player_ruthlessness = 0.0
	player_idealism = 0.0
	player_stealth_preference = 0.0
	player_chaos_preference = 0.0
	_defeat_locked = false

	# Roll the apartment's monthly rent once per run. The range is
	# broad — a lucky Sinks studio costs 700 cr, an unlucky one 2,000 cr.
	# The number never changes over a playthrough.
	monthly_rent = randi_range(RENT_MIN, RENT_MAX)

	match current_class:
		ClassSeed.WHITE_COLLAR:
			_setup_white_collar()
		ClassSeed.BLUE_COLLAR:
			_setup_blue_collar()

	credits_changed.emit(credits, credits, "run start: %s" % _class_label())
	heat_changed.emit(heat, 0, "run start")
	hope_changed.emit(int(hope), 0, "run start")
	housing_status_changed.emit(homeless)
	pending_wages_changed.emit(pending_wages)

	print("Run initialized as: %s  (credits=%d cr, rent=%d cr/mo, hope=%.0f)" % [
		_class_label(), credits, monthly_rent, hope,
	])


func _setup_white_collar() -> void:
	# Laid off last month. 50,000 cr in savings — a year's cushion if you
	# don't bleed it on the rent-plus-food baseline. Hope is fragile
	# because you had more to lose, and the unemployment line is long.
	credits = 50000
	intel_level = 100
	social_capital = -50
	hope = 55.0


func _setup_blue_collar() -> void:
	# Union layoff. 29,000 cr is the severance + what the 401(k) cashed out
	# to. Covers rent and groceries for most of the year if nothing goes
	# wrong — and something always goes wrong. Social capital is your
	# edge: neighbors remember you.
	credits = 29000
	intel_level = 10
	social_capital = 80
	hope = 45.0


func _class_label() -> String:
	return "White Collar" if current_class == ClassSeed.WHITE_COLLAR else "Blue Collar"


# =============================================================
# CREDITS
# =============================================================

func add_credits(amount: int, reason: String = "") -> void:
	if amount <= 0:
		return
	credits += amount
	print("+%d credits (%s). Total: %d." % [amount, reason, credits])
	credits_changed.emit(credits, amount, reason)


func spend_credits(amount: int, reason: String = "") -> bool:
	if amount <= 0:
		return true
	if credits < amount:
		return false
	credits -= amount
	print("-%d credits (%s). Total: %d." % [amount, reason, credits])
	credits_changed.emit(credits, -amount, reason)
	return true


func can_afford(amount: int) -> bool:
	return credits >= amount


# =============================================================
# HEAT
# =============================================================

func add_heat(amount: int, reason: String = "") -> void:
	if amount == 0:
		return
	var before: int = heat
	heat = clamp(heat + amount, 0, HEAT_MAX)
	var delta: int = heat - before
	if delta != 0:
		print("%+d heat (%s). Total: %d." % [delta, reason, heat])
		heat_changed.emit(heat, delta, reason)

	# NetFeed ambient warnings on threshold crossings (up direction only).
	if heat >= 30 and before < 30:
		_publish_heat_note("Enforcer patrols thicken near the Sinks. Someone's on the list.")
	if heat >= 60 and before < 60:
		_publish_heat_note("Compliance AI flags a person of interest. Biometric cameras on alert.")
	if heat >= 80 and before < 80:
		_publish_heat_note("Arrest warrants issued. Checkpoints running live facial scans.")

	# Defeat at heat cap.
	if heat >= HEAT_MAX and not _defeat_locked:
		_defeat_locked = true
		defeat_triggered.emit(
			"ARRESTED",
			"ARRESTED",
			"Heat maxed. Compliance AI picked up your scent; Enforcers kicked the safehouse door at dawn. Run ends here."
		)


# External callers (encounter resolutions, etc.) can force-fire a defeat
# with a custom flavor without needing heat to cap.
func fire_defeat(kind: String, title: String, flavor: String) -> void:
	if _defeat_locked:
		return
	_defeat_locked = true
	defeat_triggered.emit(kind, title, flavor)


func _publish_heat_note(text: String) -> void:
	var wd := get_node_or_null("/root/WorldDirector")
	if wd == null:
		return
	var event := {
		"type": "NEWS_TICKER",
		"headline": text,
		"timestamp": Time.get_unix_time_from_system(),
	}
	wd.netfeed_history.append(event)
	wd.netfeed_event_generated.emit(event)


func cool_heat(amount: int = 1) -> void:
	add_heat(-amount, "passive decay")


# =============================================================
# SURVIVAL TICK
# =============================================================

# Called by WorldDirector.run_world_cycle() each game day. Handles
# daily groceries (food cost), hope drift, and the despair defeat.
# Rent is no longer daily — it's a monthly decision surfaced by a
# HUD modal via rent_due_prompt on month rollover.
func apply_daily_tick(economy: Dictionary) -> void:
	# --- Daily food & utilities ---
	# Scales with food_price. Homeless: no rent, but food/bribes are
	# still a cost of breathing. Finance shock multiplies this because
	# everything jumps when the clearing houses blink.
	var food_price: int = int(economy.get("food_price", 100))
	var daily_cost: int = 25 + max(0, int((food_price - 100) / 3))
	if homeless:
		daily_cost += 8   # exposure tax — a cot, a bribe, a meal from a can
	daily_cost = int(float(daily_cost) * rent_drain_multiplier)
	if daily_cost > 0:
		credits -= daily_cost
		credits_changed.emit(credits, -daily_cost, "daily food & utilities")

	# Decay the finance shock
	if _finance_shock_cycles_remaining > 0:
		_finance_shock_cycles_remaining -= 1
		if _finance_shock_cycles_remaining == 0:
			rent_drain_multiplier = 1.0

	# --- Severance period (months 1-2) ---
	# Hope decay suspended. You had severance money coming in for two
	# months; you could walk around, talk to neighbors, feel almost okay.
	# Rent's landlord still expects his check on the 1st. At month 3
	# start, severance ends with a one-shot NetFeed note.
	var ts := get_node_or_null("/root/TimeSystem")
	var in_severance: bool = ts != null and int(ts.month) <= 2

	if not in_severance and not _severance_end_fired:
		_severance_end_fired = true
		_publish_feed("Your severance ran out this morning. The weight finds you now. Hope starts to drift.")

	# --- Hope decay ---
	if not in_severance:
		var hope_delta: float = -1.0   # baseline
		if credits < 0:
			hope_delta -= 1.0          # broke compounds the dread
		if heat > 60:
			hope_delta -= 1.0          # hunted
		if homeless:
			hope_delta -= 1.0          # exposed
		if rent_arrears_months >= 1:
			hope_delta -= 0.5          # the envelope says FINAL NOTICE in red
		if ts and int(ts.month) >= 10:
			hope_delta -= 1.0          # the year's end is heavy
		_apply_hope(hope_delta, "daily drift")

	# --- Despair defeat ---
	if hope <= 0.0 and not _defeat_locked:
		_defeat_locked = true
		defeat_triggered.emit(
			"DESPAIR_WITHDRAWAL",
			"DESPAIR",
			"You stopped leaving the apartment three days ago. The NetFeed moved on. The run ended quietly, the way most of them do."
		)


# =============================================================
# MONTHLY RENT
# =============================================================

# Called by WorldDirector on TimeSystem.rent_due (month rollover).
# Surfaces the [PAY] / [SKIP] modal via rent_due_prompt. Player
# answers via pay_rent() / skip_rent() below.
func handle_rent_due() -> void:
	if homeless:
		return   # no landlord, no rent — the streets don't bill you
	_rent_due_pending = true
	var effective: int = int(float(monthly_rent) * rent_drain_multiplier)
	rent_due_prompt.emit(effective, rent_arrears_months)


func effective_monthly_rent() -> int:
	return int(float(monthly_rent) * rent_drain_multiplier)


# Player clicked [PAY]. Drains credits (can go negative — they chose
# the hole), clears arrears, closes the pending modal.
func pay_rent() -> bool:
	if not _rent_due_pending:
		return false
	var owed: int = effective_monthly_rent() * (rent_arrears_months + 1)
	credits -= owed
	credits_changed.emit(credits, -owed, "rent paid (%d months)" % (rent_arrears_months + 1))
	_apply_hope(2.0, "rent paid — roof secure another month")
	rent_arrears_months = 0
	_rent_due_pending = false
	_publish_feed("Rent cleared. The landlord's receipt is in the mail slot by noon.")
	return true


# Player clicked [SKIP]. Arrears tick up. At 2 months unpaid, the
# eviction squad comes. Does NOT end the run — homeless is pressure.
func skip_rent() -> void:
	if not _rent_due_pending:
		return
	rent_arrears_months += 1
	_rent_due_pending = false
	if rent_arrears_months >= RENT_ARREARS_MONTHS_TO_EVICTION:
		_evict()
	else:
		_apply_hope(-4.0, "rent skipped — the envelope sits on the counter")
		_publish_feed("You didn't pay rent this month. The landlord's first notice arrived by evening.")


# =============================================================
# WEEKLY PAYDAY (gigs)
# =============================================================

# Called by WorldDirector on TimeSystem.payday (every 7 days). Dumps
# pending_wages into credits with a source breakdown for the HUD
# toast. GigBoard is the only accruer today; extensible to salaried
# WC jobs in Commit B.
func apply_weekly_payday() -> void:
	if pending_wages <= 0:
		return
	var amount: int = pending_wages
	var breakdown := pending_wages_breakdown.duplicate(true)
	credits += amount
	credits_changed.emit(credits, amount, "weekly payday")
	pending_wages = 0
	pending_wages_breakdown.clear()
	pending_wages_changed.emit(0)
	payday_deposited.emit(amount, breakdown)


# Called by GigBoard on shift completion (or any weekly-salary source).
func accrue_wages(amount: int, source: String = "gig") -> void:
	if amount <= 0:
		return
	pending_wages += amount
	var prior: int = int(pending_wages_breakdown.get(source, 0))
	pending_wages_breakdown[source] = prior + amount
	pending_wages_changed.emit(pending_wages)


func _evict() -> void:
	homeless = true
	rent_arrears_months = 0
	_rent_due_pending = false
	housing_status_changed.emit(true)
	_apply_hope(-10.0, "evicted")
	print("Evicted. Homeless flag set.")
	_publish_feed("Eviction squad came at dawn. Your name is now on the list that gets shorter each month.")


# Called by the shop (or future recovery actions) to reclaim housing.
# Returns false if unaffordable.
# Called by WorldDirector._ripple_sabotage when the Finance sector is
# hit. Credit markets freeze → rent spikes temporarily.
func apply_finance_shock() -> void:
	rent_drain_multiplier = 1.15
	_finance_shock_cycles_remaining = 10


func secure_housing() -> bool:
	if not homeless:
		return true
	var deposit: int = monthly_rent   # first month up front, standard
	if credits < deposit:
		return false
	credits -= deposit
	credits_changed.emit(credits, -deposit, "housing deposit (%d cr)" % deposit)
	homeless = false
	rent_arrears_months = 0
	housing_status_changed.emit(false)
	_apply_hope(8.0, "roof over head again")
	_publish_feed("A landlord took your deposit (%d cr). The walls creak. You have an address again." % deposit)
	return true


func housing_deposit_cost() -> int:
	return monthly_rent


# =============================================================
# HOPE
# =============================================================

func add_hope(amount: float, reason: String = "") -> void:
	_apply_hope(amount, reason)


func _apply_hope(amount: float, reason: String) -> void:
	var before: float = hope
	hope = clampf(hope + amount, 0.0, float(HOPE_MAX))
	var delta: int = int(hope) - int(before)
	if delta != 0:
		hope_changed.emit(int(hope), delta, reason)


func _publish_feed(text: String) -> void:
	var wd := get_node_or_null("/root/WorldDirector")
	if wd == null:
		return
	var event := {
		"type": "NEWS_TICKER",
		"headline": text,
		"timestamp": Time.get_unix_time_from_system(),
	}
	wd.netfeed_history.append(event)
	wd.netfeed_event_generated.emit(event)


# =============================================================
# PLAYSTYLE TRACKERS (incremented by actions; read by cameos)
# =============================================================

func bump_playstyle(chaos: float = 0.0, ruthlessness: float = 0.0, idealism: float = 0.0, stealth: float = 0.0) -> void:
	player_chaos_preference = clamp(player_chaos_preference + chaos, 0.0, 1.0)
	player_ruthlessness = clamp(player_ruthlessness + ruthlessness, 0.0, 1.0)
	player_idealism = clamp(player_idealism + idealism, 0.0, 1.0)
	player_stealth_preference = clamp(player_stealth_preference + stealth, 0.0, 1.0)
