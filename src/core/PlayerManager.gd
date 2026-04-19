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

enum ClassSeed { WHITE_COLLAR, BLUE_COLLAR }

const HEAT_MAX := 100
const HOPE_MAX := 100
const RENT_ARREARS_THRESHOLD: int = 3   # cycles underwater → eviction
const HOUSING_RECOVERY_COST: int = 500   # shop: get off the streets

var current_class: ClassSeed = ClassSeed.BLUE_COLLAR

# Player State
var credits: int = 0
var intel_level: int = 0
var social_capital: int = 0
var heat: int = 0

# Survival state. The game's premise: the system is killing you.
# You're jobless. Rent drains credits daily. Hope decays passively;
# staying alive requires ACTION, not stasis.
var hope: float = 50.0
var homeless: bool = false
var _rent_arrears_cycles: int = 0

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
	_rent_arrears_cycles = 0
	_severance_end_fired = false
	romantic_partner_ids.clear()
	player_ruthlessness = 0.0
	player_idealism = 0.0
	player_stealth_preference = 0.0
	player_chaos_preference = 0.0
	_defeat_locked = false

	match current_class:
		ClassSeed.WHITE_COLLAR:
			_setup_white_collar()
		ClassSeed.BLUE_COLLAR:
			_setup_blue_collar()

	credits_changed.emit(credits, credits, "run start: %s" % _class_label())
	heat_changed.emit(heat, 0, "run start")
	hope_changed.emit(int(hope), 0, "run start")
	housing_status_changed.emit(homeless)

	print("Run initialized as: %s  (credits=%d, intel=%d, social=%d, hope=%.0f)" % [
		_class_label(), credits, intel_level, social_capital, hope,
	])


func _setup_white_collar() -> void:
	# Laid off last month. 2000 credits of quiet savings. The system
	# is starting to notice — a delinquency notice is in the mail on
	# something (not rent yet). Hope is fragile because you had more
	# to lose.
	credits = 2000
	intel_level = 100
	social_capital = -50
	hope = 55.0


func _setup_blue_collar() -> void:
	# Behind on rent before day one. The landlord sent a registered
	# notice two weeks ago. -200 credits is the starting hole — the
	# first thing the game asks is "how will you dig out?" Hope lower
	# because you've been here before.
	credits = -200
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

# Called by WorldDirector.run_world_cycle() each game day. Drains
# rent / cost-of-living from credits, ticks hope based on situation,
# handles eviction (homeless state, not a run-ender), fires the
# DESPAIR defeat when hope bottoms out.
func apply_daily_tick(economy: Dictionary) -> void:
	# --- Cost of living ---
	# Rent scales with food_price — when the world's expensive,
	# survival eats more of what you have.
	var food_price: int = int(economy.get("food_price", 100))
	var daily_cost: int = 30 + max(0, int((food_price - 100) / 4))
	if homeless:
		daily_cost = 8  # no rent, but you still need to eat & bribe for a cot
	if daily_cost > 0:
		credits -= daily_cost
		credits_changed.emit(credits, -daily_cost, "daily cost of living")

	# --- Eviction state ---
	# Broke for RENT_ARREARS_THRESHOLD consecutive days → lose housing.
	# Does NOT end the run — being homeless is pressure, not defeat.
	if credits < 0 and not homeless:
		_rent_arrears_cycles += 1
		if _rent_arrears_cycles >= RENT_ARREARS_THRESHOLD:
			_evict()
	elif credits >= 0:
		_rent_arrears_cycles = 0

	# --- Severance period (months 1-2) ---
	# Hope decay suspended. You had severance money coming in for two
	# months; you could walk around, talk to neighbors, feel almost okay.
	# Rent still drains — the landlord doesn't wait. At month 3 start,
	# severance ends with a one-shot NetFeed note.
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


func _evict() -> void:
	homeless = true
	_rent_arrears_cycles = 0
	housing_status_changed.emit(true)
	_apply_hope(-10.0, "evicted")
	print("Evicted. Homeless flag set.")
	_publish_feed("Eviction squad came at dawn. Your name is now on the list that gets shorter each month.")


# Called by the shop (or future recovery actions) to reclaim housing.
# Returns false if unaffordable.
func secure_housing() -> bool:
	if not homeless:
		return true
	if credits < HOUSING_RECOVERY_COST:
		return false
	credits -= HOUSING_RECOVERY_COST
	credits_changed.emit(credits, -HOUSING_RECOVERY_COST, "housing deposit")
	homeless = false
	_rent_arrears_cycles = 0
	housing_status_changed.emit(false)
	_apply_hope(8.0, "roof over head again")
	_publish_feed("A landlord took your deposit. The walls creak. You have an address again.")
	return true


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
