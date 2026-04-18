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

enum ClassSeed { WHITE_COLLAR, BLUE_COLLAR }

const HEAT_MAX := 100

var current_class: ClassSeed = ClassSeed.BLUE_COLLAR

# Player State
var credits: int = 0
var intel_level: int = 0
var social_capital: int = 0
var heat: int = 0

# Playstyle trackers (read by cultural cameos to gate archetype rolls).
# See docs/03-characters/cultural-cameos.md — "player profile tracking".
var player_ruthlessness: float = 0.0
var player_idealism: float = 0.0
var player_stealth_preference: float = 0.0
var player_chaos_preference: float = 0.0


func _ready():
	print("PlayerManager initialized.")


func initialize_run(seed: ClassSeed = ClassSeed.BLUE_COLLAR) -> void:
	current_class = seed
	heat = 0
	player_ruthlessness = 0.0
	player_idealism = 0.0
	player_stealth_preference = 0.0
	player_chaos_preference = 0.0

	match current_class:
		ClassSeed.WHITE_COLLAR:
			_setup_white_collar()
		ClassSeed.BLUE_COLLAR:
			_setup_blue_collar()

	credits_changed.emit(credits, credits, "run start: %s" % _class_label())
	heat_changed.emit(heat, 0, "run start")

	print("Run initialized as: %s  (credits=%d, intel=%d, social=%d)" % [
		_class_label(), credits, intel_level, social_capital,
	])


func _setup_white_collar() -> void:
	credits = 5000
	intel_level = 100
	social_capital = -50
	# TODO: Initialize Compliance AI Hunter


func _setup_blue_collar() -> void:
	credits = 100
	intel_level = 10
	social_capital = 80
	# TODO: Initialize Resource Squeeze Timer


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


func cool_heat(amount: int = 1) -> void:
	add_heat(-amount, "passive decay")


# =============================================================
# PLAYSTYLE TRACKERS (incremented by actions; read by cameos)
# =============================================================

func bump_playstyle(chaos: float = 0.0, ruthlessness: float = 0.0, idealism: float = 0.0, stealth: float = 0.0) -> void:
	player_chaos_preference = clamp(player_chaos_preference + chaos, 0.0, 1.0)
	player_ruthlessness = clamp(player_ruthlessness + ruthlessness, 0.0, 1.0)
	player_idealism = clamp(player_idealism + idealism, 0.0, 1.0)
	player_stealth_preference = clamp(player_stealth_preference + stealth, 0.0, 1.0)
