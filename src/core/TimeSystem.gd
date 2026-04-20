extends Node

# =============================================================
# TimeSystem: the game's temporal backbone.
#
# 1 day = 10 real-time minutes. Each day has 3 phases
# (morning/afternoon/night), each 1/3 of the day, aligned to the
# NetFeed cycle. 30 days = 1 month. 13 months = 1 full playthrough.
# Month 14 → year_ended signal → WorldDirector fires TIMEOUT defeat.
#
# Fast-forward scales delta: 1× → 6× (Space) → 24× (Shift+Space).
# The 24× super-FF is essential for the long 13-month runs — ~1.1h
# of real time per playthrough at super-fast.
#
# get_tree().paused naturally stops time when a modal is open.
#
# Clock display maps tod (0.0-1.0) to a 24h clock starting at
# dawn: tod 0.0 → 06:00, tod 0.5 → 18:00, tod 1.0 → 06:00 next.
# =============================================================

signal day_advanced(day: int)
signal phase_changed(phase: int)       # 0=morning, 1=afternoon, 2=night
signal time_of_day_updated(tod: float) # 0..1 inside current day
signal speed_changed(speed: float)
signal month_advanced(month: int)      # 1..13, fired on day_of_month rollover
signal year_ended()                    # fires once when month would roll to 14
signal payday(day: int)                # fires every DAYS_PER_WEEK days (gig wages deposit)
signal rent_due(month: int)            # fires on month rollover (landlord wants rent)

const DAY_REAL_SECONDS: float = 600.0  # 10 minutes per day
const PHASES_PER_DAY: int = 3
const FAST_SPEED: float = 6.0
const SUPER_FAST_SPEED: float = 24.0   # Shift+Space — keeps 13-month runs reasonable
const DEFAULT_SPEED: float = 1.0

const DAYS_PER_MONTH: int = 30
const MONTHS_PER_YEAR: int = 13
const TOTAL_DAYS: int = DAYS_PER_MONTH * MONTHS_PER_YEAR  # 390
const DAYS_PER_WEEK: int = 7                        # gig payday cadence

enum Phase { MORNING, AFTERNOON, NIGHT }

# `day` is the absolute day count (1..390 across a full run). `month`
# and `day_of_month` partition it for display + narrative pacing.
var day: int = 1
var month: int = 1
var day_of_month: int = 1
var time_of_day: float = 0.0
var current_phase: int = Phase.MORNING
var time_scale: float = DEFAULT_SPEED
var running: bool = false     # flipped true by WorldDirector after playthrough setup
var year_ended_flag: bool = false


func _ready() -> void:
	# Don't drive time until the world is ready.
	set_process(true)


func start() -> void:
	running = true
	time_of_day_updated.emit(time_of_day)
	speed_changed.emit(time_scale)


func reset() -> void:
	day = 1
	month = 1
	day_of_month = 1
	time_of_day = 0.0
	current_phase = Phase.MORNING
	time_scale = DEFAULT_SPEED
	running = false
	year_ended_flag = false


func _process(delta: float) -> void:
	if not running:
		return

	time_of_day += (delta * time_scale) / DAY_REAL_SECONDS
	var rolled_over: bool = false
	var month_rolled_over: bool = false
	while time_of_day >= 1.0:
		time_of_day -= 1.0
		day += 1
		day_of_month += 1
		rolled_over = true
		if day_of_month > DAYS_PER_MONTH:
			day_of_month = 1
			month += 1
			month_rolled_over = true

	# Phase transition — compute from continuous tod
	var new_phase: int = clamp(int(time_of_day * PHASES_PER_DAY), 0, PHASES_PER_DAY - 1)
	if new_phase != current_phase:
		current_phase = new_phase
		phase_changed.emit(current_phase)

	# Emit tick + day + month signals
	time_of_day_updated.emit(time_of_day)
	if rolled_over:
		# After rollover, the new day's first phase is morning by
		# definition; emit phase change if we went from night→morning.
		if current_phase != new_phase:
			current_phase = new_phase
			phase_changed.emit(current_phase)
		day_advanced.emit(day)
		if day % DAYS_PER_WEEK == 0:
			payday.emit(day)
	if month_rolled_over:
		month_advanced.emit(month)
		rent_due.emit(month)

	# Year-end check — fires once when month crosses to 14.
	if month > MONTHS_PER_YEAR and not year_ended_flag:
		year_ended_flag = true
		running = false   # freeze time at the turn of the year
		year_ended.emit()


# =============================================================
# FAST-FORWARD
# =============================================================

func toggle_fast_forward() -> void:
	set_speed(DEFAULT_SPEED if time_scale > DEFAULT_SPEED else FAST_SPEED)


func set_fast_forward(enabled: bool) -> void:
	set_speed(FAST_SPEED if enabled else DEFAULT_SPEED)


func set_speed(speed: float) -> void:
	if is_equal_approx(time_scale, speed):
		return
	time_scale = speed
	speed_changed.emit(time_scale)


func is_fast_forward() -> bool:
	return time_scale > DEFAULT_SPEED + 0.01


func is_super_fast_forward() -> bool:
	return time_scale >= SUPER_FAST_SPEED - 0.01


# Shift+Space keybind in HUD — one press toggles 24×, next returns to 1×.
# Distinct from regular 6× fast-forward. The 13-month playthrough would
# be uncomfortably long at 1× or even 6× — super-FF is how you coast
# through the quiet months waiting for the world to shift.
func toggle_super_fast_forward() -> void:
	set_speed(DEFAULT_SPEED if is_super_fast_forward() else SUPER_FAST_SPEED)


# Explicit time-skip, used by inter-region travel and (future) rest
# actions. Properly fires day_advanced / phase_changed / month_advanced
# / year_ended along the way.
func skip_hours(hours: float) -> void:
	if hours <= 0.0 or year_ended_flag:
		return
	time_of_day += hours / 24.0
	var rolled_over: bool = false
	var month_rolled_over: bool = false
	while time_of_day >= 1.0:
		time_of_day -= 1.0
		day += 1
		day_of_month += 1
		rolled_over = true
		if day_of_month > DAYS_PER_MONTH:
			day_of_month = 1
			month += 1
			month_rolled_over = true

	var new_phase: int = clamp(int(time_of_day * PHASES_PER_DAY), 0, PHASES_PER_DAY - 1)
	if new_phase != current_phase:
		current_phase = new_phase
		phase_changed.emit(current_phase)

	time_of_day_updated.emit(time_of_day)
	if rolled_over:
		day_advanced.emit(day)
		if day % DAYS_PER_WEEK == 0:
			payday.emit(day)
	if month_rolled_over:
		month_advanced.emit(month)
		rent_due.emit(month)

	if month > MONTHS_PER_YEAR and not year_ended_flag:
		year_ended_flag = true
		running = false
		year_ended.emit()


# =============================================================
# QUERIES
# =============================================================

func phase_name() -> String:
	match current_phase:
		Phase.MORNING:   return "Morning"
		Phase.AFTERNOON: return "Afternoon"
		Phase.NIGHT:     return "Night"
	return "?"


func is_night() -> bool:
	return current_phase == Phase.NIGHT


func is_day() -> bool:
	return current_phase != Phase.NIGHT


## Clock string — tod 0.0 → 06:00, 1.0 → 06:00 next day.
func clock_string() -> String:
	var hour_total: float = time_of_day * 24.0 + 6.0
	var hours: int = int(hour_total) % 24
	var minutes: int = int((hour_total - floor(hour_total)) * 60.0)
	return "%02d:%02d" % [hours, minutes]


## Brightness 0..1 peaking near tod=0.25 (noon) and troughing near tod=0.75 (midnight).
## LandscapeGenerator uses this to blend day/night lighting.
func day_brightness() -> float:
	var phase_rad: float = (time_of_day - 0.25) * TAU
	return (cos(phase_rad) + 1.0) * 0.5


# =============================================================
# NARRATIVE PACING
# The 13-month arc has bands — the world ages around the player.
# Other systems call into these helpers rather than hardcoding.
# =============================================================

func pacing_band() -> String:
	if month <= 2:  return "Settling"
	if month <= 5:  return "Pressure"
	if month <= 9:  return "Escalation"
	if month <= 12: return "Climactic"
	return "Year's End"


func cameo_probability_multiplier() -> float:
	match pacing_band():
		"Settling":    return 0.75
		"Pressure":    return 1.00
		"Escalation":  return 1.25
		"Climactic":   return 1.40
		"Year's End":  return 1.60
	return 1.0


func patrol_count_multiplier() -> float:
	match pacing_band():
		"Settling":    return 0.90
		"Pressure":    return 1.00
		"Escalation":  return 1.15
		"Climactic":   return 1.30
		"Year's End":  return 1.50
	return 1.0


# Positive drift applied to public_tension each world cycle as the year
# hardens. The world tightens whether or not the player acts.
func tension_drift_per_cycle() -> int:
	match pacing_band():
		"Settling":    return 0
		"Pressure":    return 0
		"Escalation":  return 1
		"Climactic":   return 2
		"Year's End":  return 3
	return 0


# Multiplier on passive heat decay. 1.0 = standard (−1/cycle).
# Late-game, the world remembers harder.
func heat_decay_multiplier() -> float:
	match pacing_band():
		"Climactic":   return 0.5   # decay halved
		"Year's End":  return 0.25  # decay near-zero
	return 1.0


# Victory thresholds soften on the final month — the world bends
# toward resolution. Used by WorldDirector._check_systemic_collapse.
func year_end_softness() -> int:
	# Positive = victory slack. Tension wins at (100 - softness), senate
	# wins at (0 + softness), wealth wins at (100000 + softness * 5000).
	if month == MONTHS_PER_YEAR:
		return 10
	return 0
