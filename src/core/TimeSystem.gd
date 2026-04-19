extends Node
class_name TimeSystem

# =============================================================
# TimeSystem: the game's temporal backbone.
#
# 1 day = 5 real-time minutes (configurable). Each day has 3
# phases (morning/afternoon/night), each 1/3 of the day, aligned
# to the NetFeed cycle. The full world simulation ticks once per
# day (oligarchs act, Senate resolves, job board expires),
# NetFeed refreshes three times per day (one per phase).
#
# Fast-forward scales delta; a HUD toggle bumps to 6× so idle
# stretches don't drag. get_tree().paused naturally stops time
# when a modal is open since this node inherits process mode.
#
# Clock display maps tod (0.0-1.0) to a 24h clock starting at
# dawn: tod 0.0 → 06:00, tod 0.5 → 18:00, tod 1.0 → 06:00 next.
# =============================================================

signal day_advanced(day: int)
signal phase_changed(phase: int)       # 0=morning, 1=afternoon, 2=night
signal time_of_day_updated(tod: float) # 0..1 inside current day
signal speed_changed(speed: float)

const DAY_REAL_SECONDS: float = 300.0  # 5 minutes per day
const PHASES_PER_DAY: int = 3
const FAST_SPEED: float = 6.0
const DEFAULT_SPEED: float = 1.0

enum Phase { MORNING, AFTERNOON, NIGHT }

var day: int = 1
var time_of_day: float = 0.0
var current_phase: int = Phase.MORNING
var time_scale: float = DEFAULT_SPEED
var running: bool = false     # flipped true by WorldDirector after playthrough setup


func _ready() -> void:
	# Don't drive time until the world is ready.
	set_process(true)


func start() -> void:
	running = true
	time_of_day_updated.emit(time_of_day)
	speed_changed.emit(time_scale)


func reset() -> void:
	day = 1
	time_of_day = 0.0
	current_phase = Phase.MORNING
	time_scale = DEFAULT_SPEED
	running = false


func _process(delta: float) -> void:
	if not running:
		return

	time_of_day += (delta * time_scale) / DAY_REAL_SECONDS
	var rolled_over: bool = false
	while time_of_day >= 1.0:
		time_of_day -= 1.0
		day += 1
		rolled_over = true

	# Phase transition — compute from continuous tod
	var new_phase: int = clamp(int(time_of_day * PHASES_PER_DAY), 0, PHASES_PER_DAY - 1)
	if new_phase != current_phase:
		current_phase = new_phase
		phase_changed.emit(current_phase)

	# Emit tick + day signals
	time_of_day_updated.emit(time_of_day)
	if rolled_over:
		# After rollover, the new day's first phase is morning by
		# definition; emit phase change if we went from night→morning.
		if current_phase != new_phase:
			current_phase = new_phase
			phase_changed.emit(current_phase)
		day_advanced.emit(day)


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
