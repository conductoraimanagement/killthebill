extends Node
class_name CulturalCameos

# =============================================================
# CulturalCameos: the trigger engine for pop-culture intrusions.
#
# Each cameo is gated by world state + player profile. Evaluated
# once per news cycle. Tier 1 Whispers (NetFeed-only, no mechanical
# impact) are live today; Tier 2-4 are designed in
# docs/03-characters/cultural-cameos.md and awaited.
#
# Cameos that have fired once during the run won't fire again —
# rarity is preserved across the playthrough.
# =============================================================

signal cameo_triggered(cameo: Dictionary)
signal cameo_arc_started(arc: Dictionary)
signal cameo_arc_completed(arc: Dictionary)
signal cameo_arc_expired(arc: Dictionary)

# Multi-step arcs (Tier 4): these signals tell the HUD to open modals
# and await a player choice. HUD calls resolve_prompt / resolve_decision
# back on this autoload to advance the arc.
signal cameo_arc_prompt(arc: Dictionary, step: Dictionary)
signal cameo_arc_decision(arc: Dictionary, step: Dictionary)

# Cameo catalog (28 entries) lives in src/cameos/CameoCatalog.gd as a
# pure data class. This engine reads CameoCatalog.ALL to drive
# triggers, gates, and arc state machines.

var fired_ids: Array[String] = []

# Active higher-tier arcs currently running.
# Each entry: {cameo_id, definition, cycles_left, completed}
var active_arcs: Array[Dictionary] = []

# Only one Tier-3+ arc active at a time — the world can sustain one
# hijacking, not three.
const MAX_HIGH_TIER_ACTIVE := 1


func reset() -> void:
	fired_ids.clear()
	active_arcs.clear()


# Called by WorldDirector.trigger_news_cycle — one evaluation per
# phase boundary (3× per day), NOT per day.
func evaluate_triggers() -> void:
	# Probability scales with the month's pacing band (Settling .75×,
	# Pressure 1×, Escalation 1.25×, Climactic 1.4×, Year's End 1.6×).
	var pacing_mult: float = 1.0
	var ts := get_node_or_null("/root/TimeSystem")
	if ts:
		pacing_mult = float(ts.cameo_probability_multiplier())

	for cameo in CameoCatalog.ALL:
		var cameo_id: String = str(cameo.get("id", ""))
		if cameo_id in fired_ids:
			continue
		if not _is_gate_satisfied(cameo):
			continue
		var effective_prob: float = float(cameo.get("probability", 0.0)) * pacing_mult
		if randf() < effective_prob:
			_fire(cameo)


func _is_gate_satisfied(cameo: Dictionary) -> bool:
	var wd := get_node_or_null("/root/WorldDirector")
	if wd == null:
		return false
	if wd.cycle < int(cameo.get("min_cycle", 0)):
		return false

	# Cap Tier-3+ concurrent arcs. The world sustains one hijacking, not three.
	var tier: int = int(cameo.get("tier", 1))
	if tier >= 3 and _count_active_high_tier() >= MAX_HIGH_TIER_ACTIVE:
		return false

	var gate: Dictionary = cameo.get("gate", {})
	for key in gate.keys():
		var range_spec: Dictionary = gate[key]
		var value: float = _read_state_var(key)
		if range_spec.has("min") and value < float(range_spec["min"]):
			return false
		if range_spec.has("max") and value > float(range_spec["max"]):
			return false
	return true


func _read_state_var(key: String) -> float:
	var wd := get_node_or_null("/root/WorldDirector")
	var pm := get_node_or_null("/root/PlayerManager")
	match key:
		"public_tension":
			return float(wd.global_economy.get("public_tension", 0)) if wd else 0.0
		"senate_alignment":
			return float(wd.global_economy.get("senate_alignment", 50)) if wd else 50.0
		"food_price":
			return float(wd.global_economy.get("food_price", 0)) if wd else 0.0
		"security_presence":
			return float(wd.global_economy.get("security_presence", 0)) if wd else 0.0
		"player_heat":
			return float(pm.heat) if pm else 0.0
		"player_chaos_preference":
			return float(pm.player_chaos_preference) if pm else 0.0
		"player_idealism":
			return float(pm.player_idealism) if pm else 0.0
		"player_stealth_preference":
			return float(pm.player_stealth_preference) if pm else 0.0
		"player_ruthlessness":
			return float(pm.player_ruthlessness) if pm else 0.0
	return 0.0


func _fire(cameo: Dictionary) -> void:
	fired_ids.append(str(cameo.get("id", "")))
	cameo_triggered.emit(cameo)

	var tier: int = int(cameo.get("tier", 1))
	if tier == 1:
		# Whisper — flavor-only NetFeed note and we're done.
		_netfeed(str(cameo.get("headline", "")))
	else:
		# Higher tier — start an active arc.
		# current_step_index drives multi-step arcs (Tier 4). Tier 2/3
		# cameos that have an "objective" key but no "arc_steps" use the
		# legacy single-step path; current_step_index stays at 0 for them.
		var arc: Dictionary = {
			"cameo_id": str(cameo.get("id", "")),
			"definition": cameo,
			"cycles_left": int(cameo.get("arc_duration_cycles", 3)),
			"current_step_index": 0,
			"waiting_for_player": false,
			"completed": false,
		}
		active_arcs.append(arc)
		_netfeed(str(cameo.get("intro_headline", "")))
		cameo_arc_started.emit(arc)
		_enter_current_step(arc)

	print("Cameo triggered: [%s] %s (tier %d)" % [
		str(cameo.get("archetype", "?")),
		str(cameo.get("name", "?")),
		tier,
	])


# For multi-step arcs (Tier 4), entering the current step either:
#  - opens a prompt modal (accept_prompt / binary_decision) via signal
#  - waits for a world action (action_objective — caught in check_action_match)
# Legacy single-step arcs have no arc_steps; this is a no-op for them.
func _enter_current_step(arc: Dictionary) -> void:
	var steps: Array = arc.definition.get("arc_steps", [])
	if steps.is_empty():
		return
	if int(arc.current_step_index) >= steps.size():
		return
	var step: Dictionary = steps[int(arc.current_step_index)]
	match str(step.get("kind", "")):
		"accept_prompt":
			arc["waiting_for_player"] = true
			cameo_arc_prompt.emit(arc, step)
		"binary_decision":
			arc["waiting_for_player"] = true
			cameo_arc_decision.emit(arc, step)
		"action_objective":
			arc["waiting_for_player"] = false


# -------------------------------------------------------------
# Higher-tier arcs — completion, per-cycle modifiers, expiry
# -------------------------------------------------------------

# Called by WorldDirector.run_world_cycle (once per day).
func tick_daily() -> void:
	var remaining: Array[Dictionary] = []
	for arc in active_arcs:
		if bool(arc.get("completed", false)):
			continue
		_apply_cycle_modifiers(arc)
		arc["cycles_left"] = int(arc.get("cycles_left", 0)) - 1
		if int(arc["cycles_left"]) <= 0:
			_expire_arc(arc)
		else:
			remaining.append(arc)
	active_arcs = remaining


# Called by WorldDirector ripples when the player takes a mapped action.
# kind: "sabotage_sector" | "leak_oligarch" | "leak_sector"
# target_ref: sector name or oligarch_id
func check_action_match(kind: String, target_ref: String) -> void:
	for arc in active_arcs:
		if bool(arc.get("completed", false)):
			continue

		var steps: Array = arc.definition.get("arc_steps", [])
		if steps.is_empty():
			# Legacy single-step path (Tier 2/3 with just "objective").
			var obj: Dictionary = arc.definition.get("objective", {})
			if str(obj.get("kind", "")) == kind and str(obj.get("target_ref", "")) == target_ref:
				_complete_arc(arc)
			continue

		# Multi-step path — only match if the *current* step is an
		# action_objective waiting for a world match.
		if bool(arc.get("waiting_for_player", false)):
			continue
		var idx: int = int(arc.current_step_index)
		if idx >= steps.size():
			continue
		var step: Dictionary = steps[idx]
		if str(step.get("kind", "")) != "action_objective":
			continue
		var step_obj: Dictionary = step.get("objective", {})
		if str(step_obj.get("kind", "")) == kind and str(step_obj.get("target_ref", "")) == target_ref:
			_advance_step_after_action(arc, step)

	# Prune completed.
	var remaining: Array[Dictionary] = []
	for a in active_arcs:
		if not bool(a.get("completed", false)):
			remaining.append(a)
	active_arcs = remaining


# Advance a multi-step arc after an action_objective matched.
func _advance_step_after_action(arc: Dictionary, step: Dictionary) -> void:
	_netfeed(str(step.get("on_completion_headline", "")))
	arc["current_step_index"] = int(arc.current_step_index) + 1
	if int(arc.current_step_index) >= arc.definition.arc_steps.size():
		# Ran past the last step — arc resolves naturally.
		arc["completed"] = true
		cameo_arc_completed.emit(arc)
	else:
		_enter_current_step(arc)


# Called by HUD after the player resolves an accept_prompt step.
func resolve_prompt(cameo_id: String, accepted: bool) -> void:
	var arc: Dictionary = _find_active_arc(cameo_id)
	if arc.is_empty():
		return
	var idx: int = int(arc.current_step_index)
	var steps: Array = arc.definition.arc_steps
	if idx >= steps.size():
		return
	var step: Dictionary = steps[idx]
	arc["waiting_for_player"] = false

	if accepted:
		_netfeed(str(step.get("on_accept_headline", "")))
		arc["current_step_index"] = idx + 1
		if int(arc.current_step_index) >= steps.size():
			arc["completed"] = true
			cameo_arc_completed.emit(arc)
		else:
			_enter_current_step(arc)
	else:
		_netfeed(str(step.get("on_decline_headline", "")))
		arc["completed"] = true
		cameo_arc_completed.emit(arc)

	_prune_completed_arcs()


# Called by HUD after the player resolves a binary_decision step.
# option_index: 0 or 1.
func resolve_decision(cameo_id: String, option_index: int) -> void:
	var arc: Dictionary = _find_active_arc(cameo_id)
	if arc.is_empty():
		return
	var idx: int = int(arc.current_step_index)
	var steps: Array = arc.definition.arc_steps
	if idx >= steps.size():
		return
	var step: Dictionary = steps[idx]
	var options: Array = step.get("options", [])
	if option_index < 0 or option_index >= options.size():
		return

	var opt: Dictionary = options[option_index]
	var effects: Dictionary = opt.get("effects", {})
	_apply_decision_effects(effects)
	_netfeed(str(effects.get("headline", "")))

	arc["waiting_for_player"] = false
	arc["completed"] = true
	cameo_arc_completed.emit(arc)
	_prune_completed_arcs()


func _apply_decision_effects(effects: Dictionary) -> void:
	_apply_effects(effects, "cameo decision")


# Unified effect applier — used by both the legacy single-step reward
# and the multi-step binary_decision options. Supported keys:
#   credits                — PlayerManager.add_credits
#   heat_delta             — PlayerManager.add_heat (positive or negative)
#   chaos_bump             — PlayerManager.bump_playstyle (chaos)
#   ruthless_bump          — PlayerManager.bump_playstyle (ruthlessness)
#   idealism_bump          — PlayerManager.bump_playstyle (idealism)
#   stealth_bump           — PlayerManager.bump_playstyle (stealth)
#   tension_delta          — WorldDirector.global_economy.public_tension
#   senate_alignment_delta — WorldDirector.global_economy.senate_alignment
#   security_delta         — WorldDirector.global_economy.security_presence
func _apply_effects(effects: Dictionary, reason: String) -> void:
	var pm := get_node_or_null("/root/PlayerManager")
	var wd := get_node_or_null("/root/WorldDirector")

	if pm:
		# Credits stay as an effect the applier understands, but cameo
		# reward dicts no longer populate it by default. Cameos pay in
		# world-shift, not coins. See docs/03-characters/cultural-cameos.md.
		if effects.has("credits"):
			pm.add_credits(int(effects.credits), reason)
		if effects.has("heat_delta"):
			pm.add_heat(int(effects.heat_delta), reason)
		if effects.has("hope_delta"):
			pm.add_hope(float(effects.hope_delta), reason)
		if effects.has("chaos_bump"):
			pm.bump_playstyle(float(effects.chaos_bump), 0.0, 0.0, 0.0)
		if effects.has("ruthless_bump"):
			pm.bump_playstyle(0.0, float(effects.ruthless_bump), 0.0, 0.0)
		if effects.has("idealism_bump"):
			pm.bump_playstyle(0.0, 0.0, float(effects.idealism_bump), 0.0)
		if effects.has("stealth_bump"):
			pm.bump_playstyle(0.0, 0.0, 0.0, float(effects.stealth_bump))
		# Narrative payoff: Indexed Debt jubilee wipes player's rent
		# arrears and clears the Finance-oligarch debt attribution.
		# Specific to indexed_debt_arc completion.
		if effects.has("debt_jubilee") and bool(effects.debt_jubilee):
			pm.rent_arrears_months = 0
			pm.debt_held_by_oligarch_id = ""

	if wd:
		if effects.has("tension_delta"):
			wd.global_economy["public_tension"] = clamp(
				int(wd.global_economy.get("public_tension", 0)) + int(effects.tension_delta),
				0, 100)
		if effects.has("senate_alignment_delta"):
			wd.global_economy["senate_alignment"] = clamp(
				int(wd.global_economy.get("senate_alignment", 50)) + int(effects.senate_alignment_delta),
				0, 100)
		if effects.has("security_delta"):
			wd.global_economy["security_presence"] = clamp(
				int(wd.global_economy.get("security_presence", 50)) + int(effects.security_delta),
				0, 100)


func _find_active_arc(cameo_id: String) -> Dictionary:
	for arc in active_arcs:
		if str(arc.get("cameo_id", "")) == cameo_id and not bool(arc.get("completed", false)):
			return arc
	return {}


func _prune_completed_arcs() -> void:
	var remaining: Array[Dictionary] = []
	for a in active_arcs:
		if not bool(a.get("completed", false)):
			remaining.append(a)
	active_arcs = remaining


func _complete_arc(arc: Dictionary) -> void:
	arc["completed"] = true
	var def: Dictionary = arc.definition
	var reward: Dictionary = def.get("reward", {})
	_apply_effects(reward, "cameo: %s" % str(def.get("name", "")))
	# Baseline +3 hope for seeing an arc through, unless the reward
	# explicitly set its own hope_delta.
	if not reward.has("hope_delta"):
		var pm := get_node_or_null("/root/PlayerManager")
		if pm:
			pm.add_hope(3.0, "arc resolved: %s" % str(def.get("name", "")))
	_netfeed(str(def.get("completion_headline", "")))
	cameo_arc_completed.emit(arc)


func _expire_arc(arc: Dictionary) -> void:
	var def: Dictionary = arc.definition
	_netfeed(str(def.get("timeout_headline", "")))
	cameo_arc_expired.emit(arc)


func _apply_cycle_modifiers(arc: Dictionary) -> void:
	var mods: Dictionary = arc.definition.get("while_active_modifiers", {})
	if mods.is_empty():
		return
	var wd := get_node_or_null("/root/WorldDirector")
	if wd == null:
		return
	for key in mods.keys():
		var delta: int = int(mods[key])
		if wd.global_economy.has(key):
			wd.global_economy[key] = clamp(
				int(wd.global_economy[key]) + delta, 0, 100)


func _count_active_high_tier() -> int:
	var n: int = 0
	for arc in active_arcs:
		if bool(arc.get("completed", false)):
			continue
		if int(arc.definition.get("tier", 1)) >= 3:
			n += 1
	return n


func _netfeed(headline: String) -> void:
	if headline == "":
		return
	var wd := get_node_or_null("/root/WorldDirector")
	if wd == null:
		return
	var event := {
		"type": "NEWS_TICKER",
		"headline": headline,
		"timestamp": Time.get_unix_time_from_system(),
	}
	wd.netfeed_history.append(event)
	wd.netfeed_event_generated.emit(event)
