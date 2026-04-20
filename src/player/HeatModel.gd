class_name HeatModel

# =============================================================
# HeatModel: identifiability-based heat cost computation.
#
# Pure functions and constants — no state, no signals, no node
# lookups. Callers pass everything through ctx. PlayerManager
# delegates from its compute_heat_cost() wrapper, which injects
# player_stealth_preference and defaults for region_type / witness
# sampling from the live game state.
#
# Keeping this as a static class means the math is testable in
# isolation and design-tweakable without touching the rest of
# PlayerManager. See docs/04-player/heat.md for the model and
# worked examples.
# =============================================================

const REGION_IDENTIFIABILITY: Dictionary = {
	"URBAN_ELITE":    1.5,   # camera density, Enforcer saturation, facial ID
	"TRANSIT":        1.3,   # checkpoint scanners, border sensors
	"ISLAND_RETREAT": 2.0,   # private security + tiny pop remembers everyone
	"INDUSTRIAL":     1.0,   # baseline — cameras exist but gaps matter
	"URBAN_SLUM":     0.7,   # patrols exist, coverage is threadbare
	"AGRICULTURAL":   0.5,   # remote; you blend into dirt and distance
}

const METHOD_IDENTIFIABILITY: Dictionary = {
	"sabotage":           1.0,
	"sabotage_quiet":     0.7,
	"hack":               1.2,   # digital trail outlives darkness
	"sell_scandal":       0.9,   # backroom deal, small paper trail
	"bribe_politician":   0.9,
	"leak":               0.8,   # released through anonymizers
	"pickpocket_success": 0.8,   # subtle — target felt something, wasn't sure
	"pickpocket_failure": 1.3,   # witness already called the patrol
	"assassination":      2.0,   # a body is found
}

const NIGHT_MULTIPLIER: float = 0.6
const STEALTH_REDUCTION_MAX: float = 0.5   # player_stealth_preference=1 → heat × 0.5
const WITNESS_CROWD_THRESHOLD: int = 6
const WITNESS_CROWD_MULTIPLIER: float = 1.3
const WITNESS_EMPTY_MULTIPLIER: float = 0.8


# Compute the identifiability-adjusted heat cost for an act.
#
# base_heat         — pre-multiplier cost (e.g. 3 for Food sabotage)
# player_stealth    — PlayerManager.player_stealth_preference 0..1
# ctx keys (all optional):
#   region_type     — string region type key; ignored if digital
#   is_night        — bool; ignored if digital
#   witness_count   — int; 0..N nearby witnesses
#   method          — key into METHOD_IDENTIFIABILITY
#   digital         — bool. Digital acts ignore region/time; the wire
#                     doesn't care about darkness. Stealth still counts.
static func compute_cost(base_heat: int, player_stealth: float, ctx: Dictionary = {}) -> int:
	if base_heat <= 0:
		return base_heat
	var digital: bool = bool(ctx.get("digital", false))

	var region_mod: float = 1.0
	if not digital:
		var region_type: String = str(ctx.get("region_type", ""))
		region_mod = float(REGION_IDENTIFIABILITY.get(region_type, 1.0))

	var time_mod: float = 1.0
	if not digital and bool(ctx.get("is_night", false)):
		time_mod = NIGHT_MULTIPLIER

	var stealth_mod: float = 1.0 - STEALTH_REDUCTION_MAX * clamp(player_stealth, 0.0, 1.0)

	var witness_count: int = int(ctx.get("witness_count", 0))
	var witness_mod: float = 1.0
	if witness_count >= WITNESS_CROWD_THRESHOLD:
		witness_mod = WITNESS_CROWD_MULTIPLIER
	elif witness_count == 0:
		witness_mod = WITNESS_EMPTY_MULTIPLIER

	var method_mod: float = float(METHOD_IDENTIFIABILITY.get(str(ctx.get("method", "")), 1.0))

	var final_heat: float = float(base_heat) * region_mod * time_mod * stealth_mod * witness_mod * method_mod
	return int(round(final_heat))
