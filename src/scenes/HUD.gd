extends CanvasLayer
class_name HUD

# =============================================================
# HUD: the diegetic overlay. Five panels:
#   - Top-left        : world-state readout (economy + cycle)
#   - Top-right       : NetFeed ticker (latest headline)
#   - Middle-right    : Senate panel (active bill + last result)
#   - Bottom-center   : interaction prompt
#   - Centered modal  : oligarch target-picker (leak scandal)
# Matches the brutalist/terminal tone of the docs viewer.
# =============================================================

signal oligarch_picked(oligarch_id: String, action_id: String)
signal politician_bribed(politician_id: String, direction: String)
signal travel_requested(region_name: String)
signal crowd_pickpocket_requested(crowd)
signal enforcer_flee_failed(position: Vector3)

const COL_BG       := Color(0.05, 0.05, 0.06, 0.88)
const COL_BG_MODAL := Color(0.02, 0.02, 0.03, 0.92)
const COL_FG       := Color(0.91, 0.89, 0.86)
const COL_DIM      := Color(0.60, 0.59, 0.55)
const COL_BORDER   := Color(0.15, 0.15, 0.18, 1.0)
const COL_ACCENT   := Color(1.00, 0.34, 0.13)
const COL_HOT      := Color(1.00, 0.16, 0.30)
const COL_COOL     := Color(0.30, 0.79, 0.79)
const COL_WARN     := Color(1.00, 0.80, 0.20)

const PANEL_PAD := 14

# panels
var _state_panel: Panel
var _state_text: RichTextLabel

var _netfeed_panel: Panel
var _netfeed_title: Label
var _netfeed_text: RichTextLabel

var _senate_panel: Panel
var _senate_text: RichTextLabel

var _prompt_panel: Panel
var _prompt_label: Label

var _modal_root: Control
var _modal_title: Label
var _modal_list: VBoxContainer
var _modal_action_id: String = ""

# Politicians panel (toggle with P)
var _pol_panel: Panel
var _pol_text: RichTextLabel
var _pol_visible: bool = false

# Cached for the Politicians panel — last proposed bill, cleared on resolve.
# Lets us show each senator's predicted stance before the vote lands.
var _active_bill: Dictionary = {}
var _last_vote_record: Array = []

# Victory modal — shown when WorldDirector.victory_achieved fires
var _victory_root: Control
var _victory_title_label: Label
var _victory_flavor_label: Label
var _victory_kind_label: Label

# Save world modal (F5 or from victory modal)
var _save_root: Control
var _save_name_input: LineEdit
var _save_desc_input: LineEdit
var _save_status_label: Label

# Load world modal (F9 or from victory modal)
var _load_root: Control
var _load_list: VBoxContainer
var _load_paste_input: TextEdit
var _load_status_label: Label

# Terminal menu (LEAK / SELL / LOBBY)
var _terminal_menu_root: Control

# Politician bribe modal
var _bribe_root: Control
var _bribe_list: VBoxContainer
var _bribe_title: Label
var _bribe_status: Label

# Job board panel (J toggle)
var _jobs_panel: Panel
var _jobs_text: RichTextLabel
var _jobs_visible: bool = false

# Gig board panel (G toggle — requires home computer, i.e. !homeless)
var _gig_panel: Panel
var _gig_title: Label
var _gig_text: RichTextLabel
var _gig_status: Label
var _gig_visible: bool = false

# Rent-due modal (fires on month rollover via PlayerManager.rent_due_prompt)
var _rent_root: Control
var _rent_title: Label
var _rent_body: Label
var _rent_pay_btn: Button
var _rent_skip_btn: Button
var _rent_pending_rent: int = 0
var _rent_pending_arrears: int = 0

# Shop modal (terminal menu → SHOP)
var _shop_root: Control
var _shop_status: Label

# Burner datashard reveal — when true, the senate panel shows the
# active bill's honest_rationale + scandal_hooks. Cleared on bill resolve.
var _hooks_revealed: bool = false

# End-of-run modal banner label (shared by victory + defeat paths)
var _endrun_banner: Label

# Travel modal (triggered by TransitZone.activated)
var _travel_root: Control
var _travel_list: VBoxContainer

# Crowd interact menu (TALK / PICKPOCKET)
var _crowd_menu_root: Control
var _crowd_menu_title: Label
var _crowd_menu_subtitle: Label
var _active_crowd = null

# Goal-choice modal (shown at run start)
var _goal_choice_root: Control

# Chronicle viewer modal (from end-of-run modal)
var _chronicle_root: Control
var _chronicle_text: RichTextLabel

# Cameo prompt + decision modals (Tier 4 arcs)
var _cameo_prompt_root: Control
var _cameo_prompt_title: Label
var _cameo_prompt_body: Label
var _cameo_prompt_accept_btn: Button
var _cameo_prompt_decline_btn: Button

var _cameo_decision_root: Control
var _cameo_decision_title: Label
var _cameo_decision_body: Label
var _cameo_decision_options_box: VBoxContainer

var _active_cameo_arc_id: String = ""

# Dialogue modal — chat with an NPC via LLMManager
var _dialogue_root: Control
var _dialogue_log: RichTextLabel
var _dialogue_input: LineEdit
var _dialogue_send_btn: Button
var _dialogue_commit_btn: Button
var _dialogue_status: Label
var _dialogue_npc = null
var _dialogue_in_flight: bool = false

# Enforcer encounter modal (triggered by a patrol's proximity signal)
var _encounter_root: Control
var _encounter_heading: Label
var _encounter_body: Label
var _encounter_bribe_btn: Button
var _encounter_flee_btn: Button
var _encounter_submit_btn: Button
var _active_encounter_patrol = null
var _encounter_computed_bribe_cost: int = 0
var _encounter_computed_flee_chance: float = 0.0


func _ready() -> void:
	layer = 10
	_build_state_panel()
	_build_netfeed_panel()
	_build_senate_panel()
	_build_politicians_panel()
	_build_prompt_panel()
	_build_modal()
	_build_victory_modal()
	_build_save_modal()
	_build_load_modal()
	_build_terminal_menu_modal()
	_build_bribe_modal()
	_build_shop_modal()
	_build_encounter_modal()
	_build_travel_modal()
	_build_crowd_menu_modal()
	_build_dialogue_modal()
	_build_cameo_prompt_modal()
	_build_cameo_decision_modal()
	_build_goal_choice_modal()
	_build_chronicle_modal()
	_build_jobs_panel()
	_build_gig_panel()
	_build_rent_modal()

	WorldDirector.world_state_changed.connect(_refresh_state)
	WorldDirector.netfeed_event_generated.connect(_on_netfeed_event)
	WorldDirector.playthrough_setup_complete.connect(_on_playthrough_ready)
	WorldDirector.victory_achieved.connect(_on_victory)

	# Senate hooks (autoload-safe)
	var senate = get_node_or_null("/root/SenateDirector")
	if senate:
		senate.bill_proposed.connect(_on_bill_proposed)
		senate.bill_resolved.connect(_on_bill_resolved)

	# PlayerManager hooks (credits + heat + hope + housing + defeat + rent + payday)
	var pm = get_node_or_null("/root/PlayerManager")
	if pm:
		pm.credits_changed.connect(_on_credits_or_heat_changed)
		pm.heat_changed.connect(_on_credits_or_heat_changed)
		pm.hope_changed.connect(_on_credits_or_heat_changed)
		pm.housing_status_changed.connect(_on_housing_changed)
		pm.defeat_triggered.connect(_on_defeat)
		pm.rent_due_prompt.connect(_on_rent_due_prompt)
		pm.payday_deposited.connect(_on_payday_deposited)
		pm.pending_wages_changed.connect(_on_pending_wages_changed)

	# GigBoard hooks — rejections + shift completions surface on NetFeed.
	var gig_board = get_node_or_null("/root/GigBoard")
	if gig_board:
		gig_board.gig_application_denied.connect(_on_gig_denied)
		gig_board.gig_shift_completed.connect(_on_gig_shift_completed)

	# LLM dialogue responses route back via llm_response_received.
	var llm = get_node_or_null("/root/LLMManager")
	if llm:
		llm.llm_response_received.connect(_on_llm_dialogue_response)

	# Job board hooks (jobs + cameo arcs render together)
	WorldDirector.job_posted.connect(_on_job_changed)
	WorldDirector.job_completed.connect(_on_job_changed)
	WorldDirector.job_expired.connect(_on_job_changed)

	var cameos = get_node_or_null("/root/CulturalCameos")
	if cameos:
		cameos.cameo_arc_started.connect(_on_job_changed)
		cameos.cameo_arc_completed.connect(_on_job_changed)
		cameos.cameo_arc_expired.connect(_on_job_changed)
		cameos.cameo_arc_prompt.connect(_on_cameo_arc_prompt)
		cameos.cameo_arc_decision.connect(_on_cameo_arc_decision)

	# TimeSystem hooks — refresh state panel on time/phase/speed changes.
	var ts = get_node_or_null("/root/TimeSystem")
	if ts:
		ts.time_of_day_updated.connect(_on_time_updated)
		ts.phase_changed.connect(_on_phase_changed)
		ts.day_advanced.connect(_on_day_advanced)
		ts.speed_changed.connect(_on_speed_changed)
		ts.month_advanced.connect(_on_month_advanced)

	_refresh_state()


# -------------------------------------------------------------
# Public API (called from Main)
# -------------------------------------------------------------
func show_prompt(text: String) -> void:
	_prompt_label.text = text
	_prompt_panel.visible = true


func hide_prompt() -> void:
	_prompt_panel.visible = false


func show_loading(text: String) -> void:
	_netfeed_title.text = "SYSTEM // BOOT"
	_netfeed_title.add_theme_color_override("font_color", COL_WARN)
	_netfeed_text.text = "[i][color=#%s]%s[/color][/i]" % [_hex(COL_DIM), text]


func show_oligarch_target_modal(action_id: String) -> void:
	_modal_action_id = action_id
	_modal_title.text = _action_label(action_id)

	for child in _modal_list.get_children():
		child.queue_free()

	var living := WorldDirector.get_living_oligarchs()
	if living.is_empty():
		var placeholder := Label.new()
		placeholder.text = "No living oligarchs. The Enclave is already headless."
		placeholder.add_theme_color_override("font_color", COL_DIM)
		_modal_list.add_child(placeholder)
	else:
		for o in living:
			var btn := Button.new()
			btn.text = "%s   (%s · %s)" % [
				o.oligarch_name,
				o.title,
				o.sector_of_influence,
			]
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.add_theme_color_override("font_color", COL_FG)
			btn.add_theme_color_override("font_hover_color", COL_ACCENT)
			btn.add_theme_color_override("font_focus_color", COL_ACCENT)
			btn.add_theme_font_size_override("font_size", 14)
			btn.pressed.connect(_on_modal_pick.bind(o.oligarch_id))
			_modal_list.add_child(btn)

	_modal_root.visible = true
	get_tree().paused = true


func hide_modal() -> void:
	_modal_root.visible = false
	get_tree().paused = false


# -------------------------------------------------------------
# State panel (top-left)
# -------------------------------------------------------------
func _build_state_panel() -> void:
	_state_panel = _make_panel(COL_BG)
	_state_panel.anchor_left = 0.0
	_state_panel.anchor_top = 0.0
	_state_panel.offset_left = 20
	_state_panel.offset_top = 20
	_state_panel.offset_right = 320
	_state_panel.offset_bottom = 360

	var title := _make_label("// WORLD STATE", COL_ACCENT, 11, true)
	title.offset_left = PANEL_PAD
	title.offset_top = PANEL_PAD - 2
	title.offset_right = 300 - PANEL_PAD
	title.offset_bottom = PANEL_PAD + 16
	_state_panel.add_child(title)

	_state_text = RichTextLabel.new()
	_state_text.bbcode_enabled = true
	_state_text.fit_content = true
	_state_text.scroll_active = false
	_state_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_state_text.anchor_left = 0.0
	_state_text.anchor_top = 0.0
	_state_text.anchor_right = 1.0
	_state_text.offset_left = PANEL_PAD
	_state_text.offset_top = PANEL_PAD + 24
	_state_text.offset_right = -PANEL_PAD
	_state_text.offset_bottom = 200
	_state_text.add_theme_color_override("default_color", COL_FG)
	_state_text.add_theme_font_size_override("normal_font_size", 13)
	_state_text.add_theme_font_size_override("bold_font_size", 13)
	_state_panel.add_child(_state_text)


func _refresh_state() -> void:
	var e: Dictionary = WorldDirector.global_economy
	var lines := PackedStringArray()
	lines.append(_econ_row("food_price",        e.get("food_price", 0),        "credits"))
	lines.append(_econ_row("tech_price",        e.get("tech_price", 0),        "credits"))
	lines.append(_econ_row("security_presence", e.get("security_presence", 0), "/ 100"))
	lines.append(_econ_row("public_tension",    e.get("public_tension", 0),    "/ 100"))
	lines.append(_econ_row("senate_alignment",  e.get("senate_alignment", 0),  "/ 100"))
	lines.append("")
	var ts = get_node_or_null("/root/TimeSystem")
	if ts:
		var phase_color: Color = COL_COOL if ts.is_night() else COL_WARN
		var speed_str: String = ""
		if ts.is_fast_forward():
			var speed_color: Color = COL_HOT if ts.is_super_fast_forward() else COL_ACCENT
			speed_str = "  [color=#%s]▶▶ %d×[/color]" % [_hex(speed_color), int(ts.time_scale)]

		# Month X / Day Y — the 13-month countdown is the room-tone.
		var month_color: Color = _color_for_month(ts.month)
		lines.append("[color=#%s]month[/color]           [color=#%s]%d[/color] [color=#%s]of %d[/color]   [color=#%s]day %d[/color]" % [
			_hex(COL_DIM),
			_hex(month_color),
			ts.month,
			_hex(COL_DIM),
			ts.MONTHS_PER_YEAR,
			_hex(COL_FG),
			ts.day_of_month,
		])
		lines.append("[color=#%s]clock[/color]           [color=#%s]%s[/color]  [color=#%s]%s[/color]%s" % [
			_hex(COL_DIM),
			_hex(COL_COOL),
			ts.clock_string(),
			_hex(phase_color),
			ts.phase_name().to_lower(),
			speed_str,
		])
		# Year progress bar — 12-tick.
		lines.append(_build_year_progress_bar(ts))
	else:
		lines.append("[color=#%s]day[/color]             [color=#%s]%d[/color]" % [
			_hex(COL_DIM),
			_hex(COL_COOL),
			WorldDirector.cycle,
		])

	var pm = get_node_or_null("/root/PlayerManager")
	if pm:
		lines.append("[color=#%s]credits[/color]         [color=#%s]$%s[/color]" % [
			_hex(COL_DIM),
			_hex(_color_for_credits(pm.credits)),
			str(pm.credits).rpad(6),
		])
		if int(pm.pending_wages) > 0:
			lines.append("[color=#%s]pending wages[/color]   [color=#%s]+$%s[/color] [color=#%s](next payday)[/color]" % [
				_hex(COL_DIM),
				_hex(COL_COOL),
				str(int(pm.pending_wages)).rpad(5),
				_hex(COL_DIM),
			])
		lines.append("[color=#%s]rent[/color]            [color=#%s]$%d/mo[/color]" % [
			_hex(COL_DIM),
			_hex(COL_DIM),
			int(pm.monthly_rent),
		])
		if int(pm.rent_arrears_months) > 0:
			lines.append("[color=#%s]arrears[/color]         [color=#%s]%d month(s) unpaid[/color]" % [
				_hex(COL_DIM),
				_hex(COL_HOT),
				int(pm.rent_arrears_months),
			])
		lines.append("[color=#%s]heat[/color]            [color=#%s]%s[/color] [color=#%s]/ 100[/color]" % [
			_hex(COL_DIM),
			_hex(_color_for_heat(pm.heat)),
			str(pm.heat).rpad(5),
			_hex(COL_DIM),
		])
		# Hope bar — 10-tick, color-coded. At 0, DESPAIR fires.
		var hope_int: int = int(pm.hope)
		var hope_bar: String = ""
		var hope_ticks: int = clampi(int(round(float(hope_int) / 10.0)), 0, 10)
		for i in range(10):
			hope_bar += "█" if i < hope_ticks else "░"
		lines.append("[color=#%s]hope[/color]            [color=#%s]%s[/color]  [color=#%s]%d[/color]" % [
			_hex(COL_DIM),
			_hex(_color_for_hope(hope_int)),
			hope_bar,
			_hex(COL_DIM),
			hope_int,
		])
		# Housing line — only shows when homeless (otherwise implicit).
		if pm.homeless:
			lines.append("[color=#%s]housing[/color]         [color=#%s]HOMELESS[/color] [color=#%s](+drift, no shelter)[/color]" % [
				_hex(COL_DIM),
				_hex(COL_HOT),
				_hex(COL_DIM),
			])

	_state_text.text = "\n".join(lines)


func _on_credits_or_heat_changed(_new: int, _delta: int, _reason: String) -> void:
	_refresh_state()


# Throttle: time_of_day fires every frame; only repaint when the minute
# digit would visibly change (≈every ~1/1440 of a day).
var _last_tod_bucket: int = -1
func _on_time_updated(tod: float) -> void:
	var bucket: int = int(tod * 48.0)  # 48 updates per day = every ~30s game time
	if bucket != _last_tod_bucket:
		_last_tod_bucket = bucket
		_refresh_state()


func _on_phase_changed(_p: int) -> void:
	_refresh_state()


func _on_day_advanced(_d: int) -> void:
	_refresh_state()


func _on_speed_changed(_s: float) -> void:
	_refresh_state()


func _on_month_advanced(_m: int) -> void:
	_refresh_state()


func _color_for_credits(value: int) -> Color:
	if value >= 1000: return COL_COOL
	if value >= 300:  return COL_FG
	if value >= 100:  return COL_WARN
	return COL_HOT


func _color_for_heat(value: int) -> Color:
	if value > 60: return COL_HOT
	if value > 30: return COL_WARN
	return COL_FG


func _color_for_hope(value: int) -> Color:
	if value <= 20:  return COL_HOT
	if value <= 50:  return COL_WARN
	return COL_FG


func _on_housing_changed(_homeless: bool) -> void:
	_refresh_state()


func _color_for_month(month: int) -> Color:
	# Early (cyan) → mid (fg) → late (warn) → final (hot red).
	if month >= 13: return COL_HOT
	if month >= 10: return COL_WARN
	if month >= 4:  return COL_FG
	return COL_COOL


func _build_year_progress_bar(ts) -> String:
	# 12-tick bar of the run. Color-code matches month.
	var total: int = int(ts.TOTAL_DAYS)
	var elapsed: int = int(ts.day - 1)  # day is 1-indexed
	var filled: int = clampi(int(round(float(elapsed) / float(total) * 12.0)), 0, 12)
	var months_left: int = int(ts.MONTHS_PER_YEAR) - int(ts.month) + 1
	var bar: String = ""
	for i in range(12):
		bar += "█" if i < filled else "░"
	var bar_color: Color = _color_for_month(int(ts.month))
	return "[color=#%s]progress[/color]        [color=#%s]%s[/color]   [color=#%s]%d months left[/color]" % [
		_hex(COL_DIM),
		_hex(bar_color),
		bar,
		_hex(COL_DIM),
		months_left,
	]


func _econ_row(key: String, value, unit: String) -> String:
	var color_hex := _color_for(key, value)
	return "[color=#%s]%s[/color]  [color=#%s]%s[/color] [color=#%s]%s[/color]" % [
		_hex(COL_DIM),
		key.rpad(18),
		color_hex,
		str(value).rpad(5),
		_hex(COL_DIM),
		unit,
	]


func _color_for(key: String, value) -> String:
	match key:
		"food_price":
			if value > 250: return _hex(COL_HOT)
			if value > 150: return _hex(COL_WARN)
			return _hex(COL_FG)
		"tech_price":
			if value > 800: return _hex(COL_HOT)
			if value > 600: return _hex(COL_WARN)
			return _hex(COL_FG)
		"security_presence":
			if value > 70: return _hex(COL_HOT)
			if value > 50: return _hex(COL_WARN)
			return _hex(COL_COOL)
		"public_tension":
			if value > 70: return _hex(COL_HOT)
			if value > 40: return _hex(COL_WARN)
			return _hex(COL_FG)
		"senate_alignment":
			if value > 70: return _hex(COL_HOT)
			if value < 30: return _hex(COL_COOL)
			return _hex(COL_FG)
	return _hex(COL_FG)


# -------------------------------------------------------------
# NetFeed panel (top-right)
# -------------------------------------------------------------
func _build_netfeed_panel() -> void:
	_netfeed_panel = _make_panel(COL_BG)
	_netfeed_panel.anchor_left = 1.0
	_netfeed_panel.anchor_top = 0.0
	_netfeed_panel.offset_left = -460
	_netfeed_panel.offset_top = 20
	_netfeed_panel.offset_right = -20
	_netfeed_panel.offset_bottom = 160

	_netfeed_title = _make_label("NETFEED // STANDBY", COL_HOT, 11, true)
	_netfeed_title.offset_left = PANEL_PAD
	_netfeed_title.offset_top = PANEL_PAD - 2
	_netfeed_title.offset_right = 440 - PANEL_PAD
	_netfeed_title.offset_bottom = PANEL_PAD + 16
	_netfeed_panel.add_child(_netfeed_title)

	_netfeed_text = RichTextLabel.new()
	_netfeed_text.bbcode_enabled = true
	_netfeed_text.fit_content = true
	_netfeed_text.scroll_active = false
	_netfeed_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_netfeed_text.anchor_left = 0.0
	_netfeed_text.anchor_top = 0.0
	_netfeed_text.anchor_right = 1.0
	_netfeed_text.offset_left = PANEL_PAD
	_netfeed_text.offset_top = PANEL_PAD + 24
	_netfeed_text.offset_right = -PANEL_PAD
	_netfeed_text.offset_bottom = 140
	_netfeed_text.add_theme_color_override("default_color", COL_FG)
	_netfeed_text.add_theme_font_size_override("normal_font_size", 14)
	_netfeed_text.text = "[i][color=#%s]> waiting for first broadcast...[/color][/i]" % _hex(COL_DIM)
	_netfeed_panel.add_child(_netfeed_text)


func _on_netfeed_event(event_data: Dictionary) -> void:
	var headline: String = str(event_data.get("headline", ""))
	if headline == "":
		return
	_netfeed_title.text = "NETFEED // LIVE"
	_netfeed_title.add_theme_color_override("font_color", COL_ACCENT)
	_netfeed_text.text = "[color=#%s]▸[/color] %s" % [_hex(COL_ACCENT), headline]


# -------------------------------------------------------------
# Senate panel (middle-right, stacked under NetFeed)
# -------------------------------------------------------------
func _build_senate_panel() -> void:
	_senate_panel = _make_panel(COL_BG)
	_senate_panel.anchor_left = 1.0
	_senate_panel.anchor_top = 0.0
	_senate_panel.offset_left = -460
	_senate_panel.offset_top = 180
	_senate_panel.offset_right = -20
	_senate_panel.offset_bottom = 400

	var title := _make_label("// SENATE DOCKET", COL_ACCENT, 11, true)
	title.offset_left = PANEL_PAD
	title.offset_top = PANEL_PAD - 2
	title.offset_right = 440 - PANEL_PAD
	title.offset_bottom = PANEL_PAD + 16
	_senate_panel.add_child(title)

	_senate_text = RichTextLabel.new()
	_senate_text.bbcode_enabled = true
	_senate_text.fit_content = true
	_senate_text.scroll_active = false
	_senate_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_senate_text.anchor_left = 0.0
	_senate_text.anchor_top = 0.0
	_senate_text.anchor_right = 1.0
	_senate_text.offset_left = PANEL_PAD
	_senate_text.offset_top = PANEL_PAD + 24
	_senate_text.offset_right = -PANEL_PAD
	_senate_text.offset_bottom = 220
	_senate_text.add_theme_color_override("default_color", COL_FG)
	_senate_text.add_theme_font_size_override("normal_font_size", 13)
	_senate_text.add_theme_font_size_override("italics_font_size", 13)
	_senate_text.text = "[i][color=#%s]> Senate idle. Chamber awaits first cycle.[/color][/i]" % _hex(COL_DIM)
	_senate_panel.add_child(_senate_text)


func _on_bill_proposed(bill: Dictionary) -> void:
	# Preserve hooks_revealed state when this runs as an in-place refresh
	# after a burner-datashard purchase (same bill). Reset it when a new
	# bill truly proposes (different bill_id).
	if not _active_bill.is_empty() and str(bill.get("bill_id", "")) != str(_active_bill.get("bill_id", "")):
		_hooks_revealed = false
	_active_bill = bill
	_last_vote_record = []
	var sponsor_id: String = str(bill.get("sponsor_id", ""))
	var sponsor_name := _resolve_politician_name(sponsor_id)
	var title: String = str(bill.get("title", "Untitled Bill"))
	var rationale: String = str(bill.get("stated_rationale", ""))
	var summary: String = str(bill.get("summary", ""))
	var honest: String = str(bill.get("honest_rationale", ""))
	var hooks: Array = bill.get("scandal_hooks", [])

	var lines := PackedStringArray()
	lines.append("[color=#%s]IN DEBATE[/color]   [color=#%s]%s[/color]" % [
		_hex(COL_WARN),
		_hex(COL_DIM),
		"sponsor: " + sponsor_name,
	])
	lines.append("[b][color=#%s]%s[/color][/b]" % [_hex(COL_FG), title])
	lines.append("[color=#%s]%s[/color]" % [_hex(COL_DIM), summary])
	if rationale != "":
		lines.append("[i][color=#%s]Stated: %s[/color][/i]" % [_hex(COL_COOL), rationale])
	if _hooks_revealed:
		if honest != "":
			lines.append("[color=#%s]Honest:[/color] [i][color=#%s]%s[/color][/i]" % [
				_hex(COL_HOT), _hex(COL_WARN), honest,
			])
		if hooks.size() > 0:
			for hook in hooks:
				lines.append("[color=#%s]  ⚠ %s[/color]" % [_hex(COL_HOT), str(hook)])
	_senate_text.text = "\n".join(lines)

	if _pol_visible:
		_refresh_politicians()


func _on_bill_resolved(bill: Dictionary, result: String, vote_record: Array) -> void:
	_last_vote_record = vote_record
	_active_bill = {}
	_hooks_revealed = false

	var margin: int = int(bill.get("margin", 0))
	var yes := 0
	var no := 0
	var abstain := 0
	for v in vote_record:
		match v.get("stance", ""):
			"YES": yes += 1
			"NO":  no += 1
			"ABSTAIN": abstain += 1

	var color_result := COL_HOT if result == "PASS" else COL_COOL
	var title: String = str(bill.get("title", "Untitled Bill"))

	var lines := PackedStringArray()
	lines.append("[color=#%s]%s[/color]   %d–%d–%d   [color=#%s]margin %+d[/color]" % [
		_hex(color_result),
		result,
		yes, no, abstain,
		_hex(COL_DIM),
		margin,
	])
	lines.append("[b][color=#%s]%s[/color][/b]" % [_hex(COL_FG), title])
	_senate_text.text = "\n".join(lines)

	if _pol_visible:
		_refresh_politicians()


# -------------------------------------------------------------
# Politicians panel (P to toggle)
# -------------------------------------------------------------
func _build_politicians_panel() -> void:
	_pol_panel = _make_panel(COL_BG)
	_pol_panel.anchor_left = 0.0
	_pol_panel.anchor_top = 0.0
	_pol_panel.offset_left = 20
	_pol_panel.offset_top = 380
	_pol_panel.offset_right = 440
	_pol_panel.offset_bottom = 720
	_pol_panel.visible = false

	var title := _make_label("// SENATE ROSTER  (press P to hide)", COL_ACCENT, 11, true)
	title.offset_left = PANEL_PAD
	title.offset_top = PANEL_PAD - 2
	title.offset_right = 420 - PANEL_PAD
	title.offset_bottom = PANEL_PAD + 16
	_pol_panel.add_child(title)

	_pol_text = RichTextLabel.new()
	_pol_text.bbcode_enabled = true
	_pol_text.fit_content = true
	_pol_text.scroll_active = false
	_pol_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pol_text.anchor_left = 0.0
	_pol_text.anchor_top = 0.0
	_pol_text.anchor_right = 1.0
	_pol_text.offset_left = PANEL_PAD
	_pol_text.offset_top = PANEL_PAD + 24
	_pol_text.offset_right = -PANEL_PAD
	_pol_text.offset_bottom = 340
	_pol_text.add_theme_color_override("default_color", COL_FG)
	_pol_text.add_theme_font_size_override("normal_font_size", 12)
	_pol_text.add_theme_font_size_override("bold_font_size", 12)
	_pol_text.add_theme_font_size_override("italics_font_size", 12)
	_pol_panel.add_child(_pol_text)


func _toggle_politicians() -> void:
	_pol_visible = not _pol_visible
	_pol_panel.visible = _pol_visible
	if _pol_visible:
		_refresh_politicians()


func _refresh_politicians() -> void:
	if WorldDirector.politicians.is_empty():
		_pol_text.text = "[i][color=#%s]> Senate roster not yet generated.[/color][/i]" % _hex(COL_DIM)
		return

	var lines := PackedStringArray()
	# Header describes what the right column means.
	var ctx_header: String
	if not _active_bill.is_empty():
		ctx_header = "[color=#%s]predicted stance on active bill →[/color]" % _hex(COL_DIM)
	elif not _last_vote_record.is_empty():
		ctx_header = "[color=#%s]· = last vote on resolved bill[/color]" % _hex(COL_DIM)
	else:
		ctx_header = "[color=#%s]chamber idle — no bill in docket[/color]" % _hex(COL_DIM)
	lines.append(ctx_header)
	lines.append("")

	for p in WorldDirector.politicians:
		lines.append(_politician_row(p))

	_pol_text.text = "\n".join(lines)


func _politician_row(p) -> String:
	var name_part: String = p.politician_name
	var compromised: bool = p.scandal_level > 50.0
	if compromised:
		name_part = "[color=#%s]⚠[/color] %s" % [_hex(COL_HOT), name_part]

	var faction_color := _color_for_faction(p.faction)
	var faction_short := _shorten_faction(p.faction)

	# 10-tick bar, 0..100 normalization of public_approval (-100..+100 → 0..100)
	var approval_norm: float = (p.public_approval + 100.0) / 2.0
	var bar := _bar(approval_norm, 10)
	var approval_color := _color_for_approval(p.public_approval)

	# Stance
	var stance_str: String = ""
	if not _active_bill.is_empty():
		var s = p.evaluate_bill(_active_bill, WorldDirector.global_economy, [])
		stance_str = _format_stance(s, "→")
	else:
		var actual := _actual_vote_for(p.politician_id)
		if actual != "":
			stance_str = _format_stance(actual, "·")

	return "[b]%s[/b]  [color=#%s]%s[/color]  [color=#%s]%s[/color]  %s" % [
		name_part,
		_hex(faction_color),
		faction_short,
		_hex(approval_color),
		bar,
		stance_str,
	]


func _actual_vote_for(politician_id: String) -> String:
	for v in _last_vote_record:
		if str(v.get("politician_id", "")) == politician_id:
			return str(v.get("stance", ""))
	return ""


func _bar(value: float, ticks: int) -> String:
	var filled: int = clampi(int(round(value / 100.0 * ticks)), 0, ticks)
	var out: String = ""
	for i in range(ticks):
		out += "█" if i < filled else "░"
	return out


func _format_stance(stance: String, prefix: String) -> String:
	match stance:
		"YES":
			return "[color=#%s]%s YES[/color]" % [_hex(COL_WARN), prefix]
		"NO":
			return "[color=#%s]%s NO[/color]" % [_hex(COL_COOL), prefix]
		"ABSTAIN":
			return "[color=#%s]%s ABSTAIN[/color]" % [_hex(COL_DIM), prefix]
		"ABSENT":
			return "[color=#%s]%s ABSENT[/color]" % [_hex(COL_DIM), prefix]
	return ""


func _color_for_faction(faction: String) -> Color:
	match faction:
		"CORPORATE_BLOC": return COL_HOT
		"POPULIST":       return COL_ACCENT
		"REFORM":         return COL_COOL
		"INDEPENDENT":    return COL_DIM
	return COL_DIM


func _shorten_faction(faction: String) -> String:
	match faction:
		"CORPORATE_BLOC": return "CORP_BLOC"
		"POPULIST":       return "POPULIST "
		"REFORM":         return "REFORM   "
		"INDEPENDENT":    return "INDEP    "
	return faction


func _color_for_approval(value: float) -> Color:
	if value > 40.0:  return COL_WARN
	if value > 0.0:   return COL_FG
	if value > -40.0: return COL_DIM
	return COL_HOT


# -------------------------------------------------------------
# Job board panel (J to toggle) — oligarch contracts + NPC fixer jobs
# -------------------------------------------------------------
func _build_jobs_panel() -> void:
	_jobs_panel = _make_panel(COL_BG)
	_jobs_panel.anchor_left = 1.0
	_jobs_panel.anchor_top = 0.0
	_jobs_panel.offset_left = -460
	_jobs_panel.offset_top = 420
	_jobs_panel.offset_right = -20
	_jobs_panel.offset_bottom = 720
	_jobs_panel.visible = false

	var title := _make_label("// JOB BOARD  (press J to hide)", COL_ACCENT, 11, true)
	title.offset_left = PANEL_PAD
	title.offset_top = PANEL_PAD - 2
	title.offset_right = 440 - PANEL_PAD
	title.offset_bottom = PANEL_PAD + 16
	_jobs_panel.add_child(title)

	_jobs_text = RichTextLabel.new()
	_jobs_text.bbcode_enabled = true
	_jobs_text.fit_content = true
	_jobs_text.scroll_active = false
	_jobs_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_jobs_text.anchor_left = 0.0
	_jobs_text.anchor_top = 0.0
	_jobs_text.anchor_right = 1.0
	_jobs_text.offset_left = PANEL_PAD
	_jobs_text.offset_top = PANEL_PAD + 24
	_jobs_text.offset_right = -PANEL_PAD
	_jobs_text.offset_bottom = 300
	_jobs_text.add_theme_color_override("default_color", COL_FG)
	_jobs_text.add_theme_font_size_override("normal_font_size", 12)
	_jobs_text.add_theme_font_size_override("bold_font_size", 12)
	_jobs_panel.add_child(_jobs_text)


func _toggle_jobs() -> void:
	_jobs_visible = not _jobs_visible
	_jobs_panel.visible = _jobs_visible
	if _jobs_visible:
		_refresh_jobs()


func _on_job_changed(_job) -> void:
	if _jobs_visible:
		_refresh_jobs()


func _refresh_jobs() -> void:
	var cameos = get_node_or_null("/root/CulturalCameos")
	var cameo_arcs: Array = cameos.active_arcs if cameos else []

	if WorldDirector.active_jobs.is_empty() and cameo_arcs.is_empty():
		_jobs_text.text = "[i][color=#%s]> no active jobs. wait for the next news cycle.[/color][/i]" % _hex(COL_DIM)
		return

	var lines := PackedStringArray()
	for j in WorldDirector.active_jobs:
		lines.append(_job_row(j))
		lines.append("")
	for arc in cameo_arcs:
		if bool(arc.get("completed", false)):
			continue
		lines.append(_cameo_arc_row(arc))
		lines.append("")
	_jobs_text.text = "\n".join(lines)


func _cameo_arc_row(arc: Dictionary) -> String:
	var def: Dictionary = arc.definition
	var tier: int = int(def.get("tier", 2))
	var badge: String = "CAMEO T%d" % tier
	var cycles_left: int = int(arc.get("cycles_left", 0))
	var ttl_color: Color = COL_HOT if cycles_left <= 1 else COL_DIM

	# Multi-step arcs (Tier 4) show the CURRENT step's objective; legacy
	# single-step arcs fall back to def.objective.
	var objective_label: String = ""
	var waiting_note: String = ""
	var steps: Array = def.get("arc_steps", [])
	if steps.is_empty():
		var obj: Dictionary = def.get("objective", {})
		objective_label = str(obj.get("label", ""))
	else:
		var idx: int = int(arc.get("current_step_index", 0))
		if idx < steps.size():
			var step: Dictionary = steps[idx]
			match str(step.get("kind", "")):
				"action_objective":
					objective_label = str(step.get("objective", {}).get("label", ""))
				"accept_prompt":
					waiting_note = "awaiting decision: accept or decline"
				"binary_decision":
					waiting_note = "awaiting decision: the choice"

	var row: String = ""
	var badge_color: Color = Color(0.85, 0.35, 1.00)
	row += "[color=#%s]▸ %s[/color]  [color=#%s]%d cycles left[/color]\n" % [
		_hex(badge_color),
		badge,
		_hex(ttl_color),
		cycles_left,
	]
	row += "[b][color=#%s]%s[/color][/b]\n" % [_hex(COL_FG), str(def.get("name", ""))]
	row += "[color=#%s]%s[/color]\n" % [_hex(COL_DIM), str(def.get("intro_headline", ""))]
	if waiting_note != "":
		row += "  [color=#%s]⧗ %s[/color]" % [_hex(COL_WARN), waiting_note]
	elif objective_label != "":
		row += "  → [color=#%s]%s[/color]" % [_hex(COL_WARN), objective_label]
	return row


func _job_row(job: Dictionary) -> String:
	var src_type: String = str(job.get("source_type", ""))
	var badge: String
	var badge_color: Color
	if src_type == "resistance_cell":
		badge = "CELL"
		badge_color = COL_ACCENT       # rebel fire, not oligarch red
	elif src_type == "npc_fixer":
		badge = "FIXER"
		badge_color = COL_COOL
	else:
		badge = "JOB"
		badge_color = COL_DIM

	var cycles_left: int = int(job.get("expires_at_cycle", 0)) - WorldDirector.cycle
	var ttl_color := COL_HOT if cycles_left <= 1 else COL_DIM

	var row: String = ""
	row += "[color=#%s]▸ %s[/color]  [color=#%s]+$%d[/color]  [color=#%s]%d cycles left[/color]\n" % [
		_hex(badge_color),
		badge,
		_hex(COL_COOL),
		int(job.get("bounty", 0)),
		_hex(ttl_color),
		cycles_left,
	]
	row += "[b][color=#%s]%s[/color][/b]\n" % [_hex(COL_FG), str(job.get("source_name", "unknown"))]
	row += "[color=#%s]%s[/color]\n" % [_hex(COL_DIM), str(job.get("framing", ""))]
	row += "  → [color=#%s]%s[/color]" % [_hex(COL_WARN), str(job.get("target_label", ""))]
	return row


# -------------------------------------------------------------
# Gig board panel (G toggle) — the compliance side of income.
# Requires being at a computer (home apartment → unless homeless).
# Listings are filtered by the player's current region.
# Slots 1-6 apply to corresponding gigs.
# -------------------------------------------------------------
func _build_gig_panel() -> void:
	_gig_panel = _make_panel(COL_BG)
	_gig_panel.anchor_left = 1.0
	_gig_panel.anchor_top = 0.0
	_gig_panel.offset_left = -460
	_gig_panel.offset_top = 80
	_gig_panel.offset_right = -20
	_gig_panel.offset_bottom = 400
	_gig_panel.visible = false

	_gig_title = _make_label("// GIG BOARD  (G to hide)", COL_COOL, 11, true)
	_gig_title.offset_left = PANEL_PAD
	_gig_title.offset_top = PANEL_PAD - 2
	_gig_title.offset_right = 440 - PANEL_PAD
	_gig_title.offset_bottom = PANEL_PAD + 16
	_gig_panel.add_child(_gig_title)

	_gig_text = RichTextLabel.new()
	_gig_text.bbcode_enabled = true
	_gig_text.fit_content = true
	_gig_text.scroll_active = false
	_gig_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gig_text.anchor_left = 0.0
	_gig_text.anchor_top = 0.0
	_gig_text.anchor_right = 1.0
	_gig_text.offset_left = PANEL_PAD
	_gig_text.offset_top = PANEL_PAD + 24
	_gig_text.offset_right = -PANEL_PAD
	_gig_text.offset_bottom = -40
	_gig_text.anchor_bottom = 1.0
	_gig_text.add_theme_color_override("default_color", COL_FG)
	_gig_text.add_theme_font_size_override("normal_font_size", 12)
	_gig_text.add_theme_font_size_override("bold_font_size", 12)
	_gig_panel.add_child(_gig_text)

	_gig_status = _make_label("", COL_DIM, 11, true)
	_gig_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gig_status.anchor_left = 0.0
	_gig_status.anchor_right = 1.0
	_gig_status.anchor_top = 1.0
	_gig_status.anchor_bottom = 1.0
	_gig_status.offset_left = PANEL_PAD
	_gig_status.offset_top = -32
	_gig_status.offset_right = -PANEL_PAD
	_gig_status.offset_bottom = -8
	_gig_panel.add_child(_gig_status)


func _toggle_gig_panel() -> void:
	var pm = get_node_or_null("/root/PlayerManager")
	if pm and pm.homeless and not _gig_visible:
		# No home computer. Public terminals land in Commit B.
		_publish_netfeed_note("You need a computer. The one you had came with the apartment.")
		return
	_gig_visible = not _gig_visible
	_gig_panel.visible = _gig_visible
	if _gig_visible:
		_refresh_gig_panel()


func _refresh_gig_panel() -> void:
	if not _gig_panel or not _gig_panel.visible:
		return
	var gb = get_node_or_null("/root/GigBoard")
	var pm = get_node_or_null("/root/PlayerManager")
	var ts = get_node_or_null("/root/TimeSystem")
	if gb == null or pm == null:
		_gig_text.text = "[i]Gig board offline.[/i]"
		return

	var region_type: String = _current_region_type()
	var listings: Array = gb.listings_for_region(region_type)

	var pending: int = int(pm.pending_wages)
	var next_payday_in: int = 7
	if ts:
		next_payday_in = 7 - (int(ts.day) % 7)
		if next_payday_in == 0:
			next_payday_in = 7
	_gig_title.text = "// GIG BOARD  (G to hide)  —  pending $%d  ·  next payday in %d days" % [pending, next_payday_in]

	if listings.is_empty():
		_gig_text.text = "[i][color=#%s]> no gigs available in this region. travel to find work.[/color][/i]" % _hex(COL_DIM)
		return

	var lines := PackedStringArray()
	var slot: int = 1
	for g in listings:
		if slot > 6:
			break
		lines.append(_gig_row(slot, g))
		lines.append("")
		slot += 1
	_gig_text.text = "\n".join(lines)


func _gig_row(slot: int, g: Dictionary) -> String:
	var pay_range: Array = g.get("pay", [0, 0])
	var tip_range: Array = g.get("tip_variance", [0, 0])
	var tip_note: String = ""
	if int(tip_range[1]) > 0:
		tip_note = " (+ tip 0–$%d)" % int(tip_range[1])
	var hours: int = int(g.get("hours", 3))
	var row: String = ""
	row += "[color=#%s]▸ [%d][/color]  [color=#%s]$%d–$%d%s[/color]  [color=#%s]%dh shift[/color]\n" % [
		_hex(COL_WARN),
		slot,
		_hex(COL_COOL),
		int(pay_range[0]),
		int(pay_range[1]),
		tip_note,
		_hex(COL_DIM),
		hours,
	]
	row += "[b][color=#%s]%s[/color][/b]" % [_hex(COL_FG), str(g.get("title", ""))]
	return row


func _apply_gig_slot(slot_index: int) -> void:
	var gb = get_node_or_null("/root/GigBoard")
	var pm = get_node_or_null("/root/PlayerManager")
	if gb == null or pm == null:
		return
	if pm.homeless:
		_gig_status.text = "No computer access. Find a public terminal."
		return
	var region_type: String = _current_region_type()
	var listings: Array = gb.listings_for_region(region_type)
	if slot_index < 0 or slot_index >= listings.size():
		return
	var gig: Dictionary = listings[slot_index]
	var result: Dictionary = gb.apply_for_shift(str(gig.get("kind", "")))
	if bool(result.get("denied", false)):
		_gig_status.text = "Application denied."
		_gig_status.add_theme_color_override("font_color", COL_HOT)
	else:
		var pay: int = int(result.get("pay", 0))
		var humiliation: String = str(result.get("humiliation", ""))
		_gig_status.text = "Shift done. $%d accrues to payday. %s" % [pay, humiliation]
		_gig_status.add_theme_color_override("font_color", COL_COOL)
	_refresh_gig_panel()


func _current_region_type() -> String:
	if not has_node("/root/WorldDirector"):
		return ""
	var wd = get_node("/root/WorldDirector")
	for r in wd.regions:
		if str(r.get("name", "")) == str(wd.current_region):
			return str(r.get("type", ""))
	return ""


# -------------------------------------------------------------
# Rent-due modal (fires on PlayerManager.rent_due_prompt)
# -------------------------------------------------------------
func _build_rent_modal() -> void:
	_rent_root = Control.new()
	_rent_root.anchor_right = 1.0
	_rent_root.anchor_bottom = 1.0
	_rent_root.visible = false
	_rent_root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_rent_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_rent_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.7)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_rent_root.add_child(backdrop)

	var panel := _make_panel_raw(COL_BG_MODAL)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -320
	panel.offset_top = -160
	panel.offset_right = 320
	panel.offset_bottom = 160
	_rent_root.add_child(panel)

	_rent_title = _make_label("// RENT DUE", COL_WARN, 17, true)
	_rent_title.offset_left = PANEL_PAD + 4
	_rent_title.offset_top = PANEL_PAD
	_rent_title.offset_right = 640 - PANEL_PAD
	_rent_title.offset_bottom = PANEL_PAD + 26
	panel.add_child(_rent_title)

	_rent_body = _make_label("", COL_FG, 13, false)
	_rent_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rent_body.offset_left = PANEL_PAD + 4
	_rent_body.offset_top = PANEL_PAD + 36
	_rent_body.offset_right = 640 - PANEL_PAD
	_rent_body.offset_bottom = PANEL_PAD + 200
	panel.add_child(_rent_body)

	_rent_pay_btn = Button.new()
	_rent_pay_btn.text = "PAY"
	_rent_pay_btn.anchor_left = 0.0
	_rent_pay_btn.anchor_right = 0.5
	_rent_pay_btn.anchor_top = 1.0
	_rent_pay_btn.anchor_bottom = 1.0
	_rent_pay_btn.offset_left = PANEL_PAD + 4
	_rent_pay_btn.offset_top = -60
	_rent_pay_btn.offset_right = -8
	_rent_pay_btn.offset_bottom = -PANEL_PAD
	_rent_pay_btn.add_theme_color_override("font_color", COL_COOL)
	_rent_pay_btn.pressed.connect(_on_rent_pay)
	panel.add_child(_rent_pay_btn)

	_rent_skip_btn = Button.new()
	_rent_skip_btn.text = "SKIP"
	_rent_skip_btn.anchor_left = 0.5
	_rent_skip_btn.anchor_right = 1.0
	_rent_skip_btn.anchor_top = 1.0
	_rent_skip_btn.anchor_bottom = 1.0
	_rent_skip_btn.offset_left = 8
	_rent_skip_btn.offset_top = -60
	_rent_skip_btn.offset_right = -PANEL_PAD - 4
	_rent_skip_btn.offset_bottom = -PANEL_PAD
	_rent_skip_btn.add_theme_color_override("font_color", COL_HOT)
	_rent_skip_btn.pressed.connect(_on_rent_skip)
	panel.add_child(_rent_skip_btn)


func _on_rent_due_prompt(rent_amount: int, months_behind: int) -> void:
	_rent_pending_rent = rent_amount
	_rent_pending_arrears = months_behind
	var total: int = rent_amount * (months_behind + 1)
	var body_text := ""
	if months_behind == 0:
		body_text = "The landlord wants his check. This month's rent: $%d.\n\nPay now, or skip and eat the ding on your record." % rent_amount
	elif months_behind == 1:
		body_text = "Second notice. You're one month behind. Two months unpaid and the eviction squad comes.\n\nTotal owed now: $%d (%d months × $%d)." % [total, months_behind + 1, rent_amount]
	if months_behind > 0:
		_rent_title.text = "// RENT DUE  (month %d behind)" % months_behind
	else:
		_rent_title.text = "// RENT DUE"
	_rent_body.text = body_text
	_rent_pay_btn.text = "PAY  $%d" % total
	_rent_root.visible = true
	get_tree().paused = true


func _on_rent_pay() -> void:
	var pm = get_node_or_null("/root/PlayerManager")
	if pm == null:
		return
	if pm.pay_rent():
		_rent_root.visible = false
		get_tree().paused = false


func _on_rent_skip() -> void:
	var pm = get_node_or_null("/root/PlayerManager")
	if pm == null:
		return
	pm.skip_rent()
	_rent_root.visible = false
	get_tree().paused = false


# -------------------------------------------------------------
# Gig + payday NetFeed toasts
# -------------------------------------------------------------
func _on_gig_denied(_kind: String, reason: String) -> void:
	_publish_netfeed_note("Application reply: %s  (30 minutes gone)" % reason)


func _on_gig_shift_completed(_kind: String, pay: int, humiliation: String) -> void:
	_publish_netfeed_note("Shift done. $%d accrues to payday. %s" % [pay, humiliation])
	if _gig_visible:
		_refresh_gig_panel()


func _on_payday_deposited(amount: int, breakdown: Dictionary) -> void:
	var parts := PackedStringArray()
	for k in breakdown.keys():
		parts.append("%s $%d" % [str(k), int(breakdown[k])])
	var suffix: String = ""
	if parts.size() > 0:
		suffix = "  (" + ", ".join(parts) + ")"
	_publish_netfeed_note("PAYDAY: $%d deposited.%s" % [amount, suffix])


func _on_pending_wages_changed(_total: int) -> void:
	if _gig_visible:
		_refresh_gig_panel()


func _publish_netfeed_note(text: String) -> void:
	# Piggyback on the NetFeed panel — the existing ticker surfaces it.
	if not has_node("/root/WorldDirector"):
		return
	var wd = get_node("/root/WorldDirector")
	var event := {
		"type": "NEWS_TICKER",
		"headline": text,
		"timestamp": Time.get_unix_time_from_system(),
	}
	wd.netfeed_history.append(event)
	wd.netfeed_event_generated.emit(event)


# -------------------------------------------------------------
# Prompt panel
# -------------------------------------------------------------
func _build_prompt_panel() -> void:
	_prompt_panel = _make_panel(COL_BG)
	_prompt_panel.anchor_left = 0.5
	_prompt_panel.anchor_top = 1.0
	_prompt_panel.anchor_right = 0.5
	_prompt_panel.offset_left = -200
	_prompt_panel.offset_top = -90
	_prompt_panel.offset_right = 200
	_prompt_panel.offset_bottom = -40
	_prompt_panel.visible = false

	_prompt_label = _make_label("", COL_WARN, 15, true)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.anchor_left = 0.0
	_prompt_label.anchor_top = 0.0
	_prompt_label.anchor_right = 1.0
	_prompt_label.anchor_bottom = 1.0
	_prompt_panel.add_child(_prompt_label)


# -------------------------------------------------------------
# Modal (centered, pauses tree, leak-scandal picker)
# -------------------------------------------------------------
func _build_modal() -> void:
	_modal_root = Control.new()
	_modal_root.anchor_left = 0.0
	_modal_root.anchor_top = 0.0
	_modal_root.anchor_right = 1.0
	_modal_root.anchor_bottom = 1.0
	_modal_root.visible = false
	_modal_root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_modal_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_modal_root)

	# Backdrop
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.6)
	backdrop.anchor_left = 0.0
	backdrop.anchor_top = 0.0
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_root.add_child(backdrop)

	# Center panel
	var panel := _make_panel_raw(COL_BG_MODAL)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -300
	panel.offset_top = -220
	panel.offset_right = 300
	panel.offset_bottom = 220
	_modal_root.add_child(panel)

	_modal_title = _make_label("LEAK SCANDAL TO NETFEED", COL_ACCENT, 16, true)
	_modal_title.offset_left = PANEL_PAD + 4
	_modal_title.offset_top = PANEL_PAD
	_modal_title.offset_right = 600 - PANEL_PAD
	_modal_title.offset_bottom = PANEL_PAD + 24
	panel.add_child(_modal_title)

	var sub := _make_label("Pick a target. A dossier will hit the NetFeed.", COL_DIM, 12, false)
	sub.offset_left = PANEL_PAD + 4
	sub.offset_top = PANEL_PAD + 28
	sub.offset_right = 600 - PANEL_PAD
	sub.offset_bottom = PANEL_PAD + 48
	panel.add_child(sub)

	# Scroll container for the list
	var scroll := ScrollContainer.new()
	scroll.anchor_left = 0.0
	scroll.anchor_top = 0.0
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = PANEL_PAD
	scroll.offset_top = PANEL_PAD + 56
	scroll.offset_right = -PANEL_PAD
	scroll.offset_bottom = -60
	panel.add_child(scroll)

	_modal_list = VBoxContainer.new()
	_modal_list.anchor_left = 0.0
	_modal_list.anchor_top = 0.0
	_modal_list.anchor_right = 1.0
	_modal_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_modal_list)

	# Cancel button (bottom-right)
	var cancel := Button.new()
	cancel.text = "CANCEL (Esc)"
	cancel.anchor_left = 1.0
	cancel.anchor_top = 1.0
	cancel.anchor_right = 1.0
	cancel.anchor_bottom = 1.0
	cancel.offset_left = -160
	cancel.offset_top = -44
	cancel.offset_right = -PANEL_PAD
	cancel.offset_bottom = -PANEL_PAD
	cancel.add_theme_color_override("font_color", COL_DIM)
	cancel.add_theme_color_override("font_hover_color", COL_FG)
	cancel.pressed.connect(hide_modal)
	panel.add_child(cancel)


func _on_modal_pick(oligarch_id: String) -> void:
	var action := _modal_action_id
	hide_modal()
	oligarch_picked.emit(oligarch_id, action)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return

	# Save/load modals: ESC closes
	if _save_root and _save_root.visible:
		if event.keycode == KEY_ESCAPE:
			hide_save_modal()
			get_viewport().set_input_as_handled()
		return
	if _load_root and _load_root.visible:
		if event.keycode == KEY_ESCAPE:
			hide_load_modal()
			get_viewport().set_input_as_handled()
		return

	# Terminal menu: ESC closes
	if _terminal_menu_root and _terminal_menu_root.visible:
		if event.keycode == KEY_ESCAPE:
			hide_terminal_menu()
			get_viewport().set_input_as_handled()
		return

	# Bribe modal: ESC closes
	if _bribe_root and _bribe_root.visible:
		if event.keycode == KEY_ESCAPE:
			hide_bribe_modal()
			get_viewport().set_input_as_handled()
		return

	# Shop modal: ESC closes
	if _shop_root and _shop_root.visible:
		if event.keycode == KEY_ESCAPE:
			hide_shop_modal()
			get_viewport().set_input_as_handled()
		return

	# Travel modal: ESC closes
	if _travel_root and _travel_root.visible:
		if event.keycode == KEY_ESCAPE:
			hide_travel_modal()
			get_viewport().set_input_as_handled()
		return

	# Crowd-NPC menu: ESC closes
	if _crowd_menu_root and _crowd_menu_root.visible:
		if event.keycode == KEY_ESCAPE:
			hide_crowd_menu()
			get_viewport().set_input_as_handled()
		return

	# Dialogue modal: ESC closes — but lineedit ENTER is handled via
	# text_submitted, so no collision.
	if _dialogue_root and _dialogue_root.visible:
		if event.keycode == KEY_ESCAPE:
			hide_dialogue_modal()
			get_viewport().set_input_as_handled()
		return

	# Victory modal swallows everything except the save/load shortcuts,
	# but those have their own buttons on the panel, so just absorb.
	if _victory_root and _victory_root.visible:
		return

	# Enforcer encounter modal: pick BRIBE/FLEE/SUBMIT — no ESC out.
	if _encounter_root and _encounter_root.visible:
		return

	# Cameo prompt / decision modals: forced choice, no ESC out.
	if _cameo_prompt_root and _cameo_prompt_root.visible:
		return
	if _cameo_decision_root and _cameo_decision_root.visible:
		return

	# Goal-choice modal: forced at run start, no ESC.
	if _goal_choice_root and _goal_choice_root.visible:
		return

	# Chronicle modal: ESC closes.
	if _chronicle_root and _chronicle_root.visible:
		if event.keycode == KEY_ESCAPE:
			hide_chronicle_modal()
			get_viewport().set_input_as_handled()
		return

	# Oligarch-target modal: ESC closes it; otherwise fall through to nothing
	if _modal_root and _modal_root.visible:
		if event.keycode == KEY_ESCAPE:
			hide_modal()
			get_viewport().set_input_as_handled()
		return

	# Global keybinds when nothing is up
	match event.keycode:
		KEY_P:
			_toggle_politicians()
			get_viewport().set_input_as_handled()
		KEY_J:
			_toggle_jobs()
			get_viewport().set_input_as_handled()
		KEY_G:
			_toggle_gig_panel()
			get_viewport().set_input_as_handled()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			# Quick-apply gig by slot number while the gig panel is open.
			if _gig_visible:
				var slot: int = event.keycode - KEY_1   # 0..5
				_apply_gig_slot(slot)
				get_viewport().set_input_as_handled()
		KEY_SPACE:
			var ts = get_node_or_null("/root/TimeSystem")
			if ts:
				# Shift+Space → 24× super-fast; plain Space → 6× fast.
				if event.shift_pressed:
					ts.toggle_super_fast_forward()
				else:
					ts.toggle_fast_forward()
			get_viewport().set_input_as_handled()
		KEY_F5:
			show_save_modal()
			get_viewport().set_input_as_handled()
		KEY_F9:
			show_load_modal()
			get_viewport().set_input_as_handled()


# -------------------------------------------------------------
# Goal-choice modal — pick one victory path at run start
# -------------------------------------------------------------
func _build_goal_choice_modal() -> void:
	_goal_choice_root = Control.new()
	_goal_choice_root.anchor_right = 1.0
	_goal_choice_root.anchor_bottom = 1.0
	_goal_choice_root.visible = false
	_goal_choice_root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_goal_choice_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_goal_choice_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.02, 0.04, 0.96)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_goal_choice_root.add_child(backdrop)

	var panel := _make_panel_raw(COL_BG_MODAL)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -380
	panel.offset_top = -280
	panel.offset_right = 380
	panel.offset_bottom = 280
	_goal_choice_root.add_child(panel)

	var banner := _make_label("// 13 MONTHS", COL_ACCENT, 18, true)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.anchor_right = 1.0
	banner.offset_left = PANEL_PAD
	banner.offset_top = PANEL_PAD + 6
	banner.offset_right = -PANEL_PAD
	banner.offset_bottom = PANEL_PAD + 32
	panel.add_child(banner)

	var sub := _make_label("One goal. Pick it, or let the year decide.", COL_DIM, 12, false)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.anchor_right = 1.0
	sub.offset_left = PANEL_PAD
	sub.offset_top = PANEL_PAD + 38
	sub.offset_right = -PANEL_PAD
	sub.offset_bottom = PANEL_PAD + 56
	panel.add_child(sub)

	var options: Array = [
		{"path": "DIRECT_ACTION",        "label": "DIRECT ACTION",        "flavor": "Kill the oligarchs. The rarest, loudest path.",                      "color": COL_HOT},
		{"path": "POLITICAL_REVOLUTION", "label": "POLITICAL REVOLUTION", "flavor": "Push public_tension to 100. The masses storm.",                      "color": COL_ACCENT},
		{"path": "POLITICAL_REFORM",     "label": "POLITICAL REFORM",     "flavor": "Drive senate_alignment to 0. Bribe, leak, organize.",                "color": COL_COOL},
		{"path": "SYSTEMIC_COLLAPSE",    "label": "SYSTEMIC COLLAPSE",    "flavor": "Grind combined oligarch wealth below survival. The grind path.",    "color": COL_WARN},
		{"path": "ANY",                  "label": "LET THE YEAR DECIDE",  "flavor": "Any condition wins. Less committed, less narrative.",                "color": COL_DIM},
	]

	var y: int = PANEL_PAD + 72
	var btn_h: int = 64
	var gap: int = 8

	for opt in options:
		var box := VBoxContainer.new()
		box.anchor_right = 1.0
		box.offset_left = PANEL_PAD
		box.offset_top = y
		box.offset_right = -PANEL_PAD
		box.offset_bottom = y + btn_h
		box.add_theme_constant_override("separation", 0)
		panel.add_child(box)

		var btn := Button.new()
		btn.text = str(opt.label)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_color_override("font_color", opt.color)
		btn.add_theme_color_override("font_hover_color", COL_FG)
		btn.add_theme_font_size_override("font_size", 15)
		btn.pressed.connect(_on_goal_picked.bind(str(opt.path)))
		box.add_child(btn)

		var flavor := Label.new()
		flavor.text = "   " + str(opt.flavor)
		flavor.add_theme_color_override("font_color", COL_DIM)
		flavor.add_theme_font_size_override("font_size", 11)
		flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(flavor)

		y += btn_h + gap


func show_goal_choice_modal() -> void:
	_goal_choice_root.visible = true
	# Don't pause the tree — let the world finish generating in the
	# background while the player decides. The modal will just absorb
	# input.


func hide_goal_choice_modal() -> void:
	_goal_choice_root.visible = false


func _on_goal_picked(path: String) -> void:
	var pm = get_node_or_null("/root/PlayerManager")
	if pm:
		pm.chosen_victory_path = path
	hide_goal_choice_modal()


# -------------------------------------------------------------
# Chronicle modal — 13-month narrative log, shown from end-of-run
# -------------------------------------------------------------
func _build_chronicle_modal() -> void:
	_chronicle_root = Control.new()
	_chronicle_root.anchor_right = 1.0
	_chronicle_root.anchor_bottom = 1.0
	_chronicle_root.visible = false
	_chronicle_root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_chronicle_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_chronicle_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.01, 0.01, 0.02, 0.96)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_chronicle_root.add_child(backdrop)

	var panel := _make_panel_raw(COL_BG_MODAL)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -460
	panel.offset_top = -360
	panel.offset_right = 460
	panel.offset_bottom = 360
	_chronicle_root.add_child(panel)

	var title := _make_label("// THE CHRONICLE", COL_ACCENT, 15, true)
	title.offset_left = PANEL_PAD + 4
	title.offset_top = PANEL_PAD
	title.offset_right = 920 - PANEL_PAD
	title.offset_bottom = PANEL_PAD + 22
	panel.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.offset_left = PANEL_PAD
	scroll.offset_top = PANEL_PAD + 30
	scroll.offset_right = -PANEL_PAD
	scroll.offset_bottom = -60
	panel.add_child(scroll)

	_chronicle_text = RichTextLabel.new()
	_chronicle_text.bbcode_enabled = false
	_chronicle_text.fit_content = true
	_chronicle_text.scroll_active = false
	_chronicle_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chronicle_text.anchor_right = 1.0
	_chronicle_text.add_theme_color_override("default_color", COL_FG)
	_chronicle_text.add_theme_font_size_override("normal_font_size", 12)
	scroll.add_child(_chronicle_text)

	var close := Button.new()
	close.text = "CLOSE (Esc)"
	close.anchor_left = 0.0
	close.anchor_top = 1.0
	close.anchor_right = 0.0
	close.anchor_bottom = 1.0
	close.offset_left = PANEL_PAD
	close.offset_top = -44
	close.offset_right = 160
	close.offset_bottom = -PANEL_PAD
	close.add_theme_color_override("font_color", COL_DIM)
	close.add_theme_color_override("font_hover_color", COL_FG)
	close.pressed.connect(hide_chronicle_modal)
	panel.add_child(close)

	var copy := Button.new()
	copy.text = "COPY TO CLIPBOARD"
	copy.anchor_left = 1.0
	copy.anchor_top = 1.0
	copy.anchor_right = 1.0
	copy.anchor_bottom = 1.0
	copy.offset_left = -240
	copy.offset_top = -44
	copy.offset_right = -PANEL_PAD
	copy.offset_bottom = -PANEL_PAD
	copy.add_theme_color_override("font_color", COL_COOL)
	copy.add_theme_color_override("font_hover_color", COL_FG)
	copy.pressed.connect(_on_chronicle_copy)
	panel.add_child(copy)


func show_chronicle_modal() -> void:
	var chronicle = get_node_or_null("/root/Chronicle")
	if chronicle:
		_chronicle_text.text = chronicle.to_text()
	else:
		_chronicle_text.text = "Chronicle unavailable."
	_chronicle_root.visible = true
	get_tree().paused = true


func hide_chronicle_modal() -> void:
	_chronicle_root.visible = false
	# If the end-of-run flow is active (kind label non-empty), bring
	# the victory/defeat modal back up so the player can still pick
	# RESTART / CONTINUE / etc.
	var kind_label_text: String = str(_victory_kind_label.text) if _victory_kind_label else ""
	if kind_label_text != "":
		_victory_root.visible = true
		get_tree().paused = true
	else:
		get_tree().paused = false


func _on_chronicle_copy() -> void:
	var chronicle = get_node_or_null("/root/Chronicle")
	if chronicle:
		DisplayServer.clipboard_set(chronicle.to_text())


# -------------------------------------------------------------
# Victory modal (fired by WorldDirector.victory_achieved)
# -------------------------------------------------------------
func _build_victory_modal() -> void:
	_victory_root = Control.new()
	_victory_root.anchor_left = 0.0
	_victory_root.anchor_top = 0.0
	_victory_root.anchor_right = 1.0
	_victory_root.anchor_bottom = 1.0
	_victory_root.visible = false
	_victory_root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_victory_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_victory_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.01, 0.01, 0.02, 0.92)
	backdrop.anchor_left = 0.0
	backdrop.anchor_top = 0.0
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_victory_root.add_child(backdrop)

	var panel := _make_panel_raw(COL_BG_MODAL)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -360
	panel.offset_top = -220
	panel.offset_right = 360
	panel.offset_bottom = 220
	_victory_root.add_child(panel)

	# Top banner — VICTORY (or DEFEAT, styled in _on_defeat)
	_endrun_banner = _make_label("// VICTORY //", COL_ACCENT, 14, true)
	_endrun_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_endrun_banner.anchor_left = 0.0
	_endrun_banner.anchor_top = 0.0
	_endrun_banner.anchor_right = 1.0
	_endrun_banner.offset_left = PANEL_PAD
	_endrun_banner.offset_top = PANEL_PAD + 4
	_endrun_banner.offset_right = -PANEL_PAD
	_endrun_banner.offset_bottom = PANEL_PAD + 28
	panel.add_child(_endrun_banner)

	# Kind (small, e.g. "DIRECT_ACTION")
	_victory_kind_label = _make_label("", COL_DIM, 11, true)
	_victory_kind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_victory_kind_label.anchor_left = 0.0
	_victory_kind_label.anchor_top = 0.0
	_victory_kind_label.anchor_right = 1.0
	_victory_kind_label.offset_left = PANEL_PAD
	_victory_kind_label.offset_top = PANEL_PAD + 36
	_victory_kind_label.offset_right = -PANEL_PAD
	_victory_kind_label.offset_bottom = PANEL_PAD + 52
	panel.add_child(_victory_kind_label)

	# Title (big)
	_victory_title_label = _make_label("", COL_FG, 34, true)
	_victory_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_victory_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_victory_title_label.anchor_left = 0.0
	_victory_title_label.anchor_top = 0.0
	_victory_title_label.anchor_right = 1.0
	_victory_title_label.offset_left = PANEL_PAD
	_victory_title_label.offset_top = PANEL_PAD + 70
	_victory_title_label.offset_right = -PANEL_PAD
	_victory_title_label.offset_bottom = PANEL_PAD + 150
	panel.add_child(_victory_title_label)

	# Flavor
	_victory_flavor_label = _make_label("", COL_DIM, 14, false)
	_victory_flavor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_victory_flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_victory_flavor_label.anchor_left = 0.0
	_victory_flavor_label.anchor_top = 0.0
	_victory_flavor_label.anchor_right = 1.0
	_victory_flavor_label.offset_left = PANEL_PAD + 20
	_victory_flavor_label.offset_top = PANEL_PAD + 170
	_victory_flavor_label.offset_right = -PANEL_PAD - 20
	_victory_flavor_label.offset_bottom = PANEL_PAD + 250
	panel.add_child(_victory_flavor_label)

	# Buttons — top row: save / load / chronicle; bottom row: restart / continue
	var save_btn := _make_modal_button("SAVE WORLD", COL_COOL, -340, -180, -88)
	save_btn.pressed.connect(_on_victory_save)
	panel.add_child(save_btn)

	var load_btn := _make_modal_button("LOAD WORLD…", COL_COOL, -170, -10, -88)
	load_btn.pressed.connect(_on_victory_load)
	panel.add_child(load_btn)

	var chronicle_btn := _make_modal_button("VIEW CHRONICLE", COL_WARN, 10, 340, -88)
	chronicle_btn.pressed.connect(_on_victory_chronicle)
	panel.add_child(chronicle_btn)

	var restart := _make_modal_button("RESTART", COL_ACCENT, -170, -10, -44)
	restart.pressed.connect(_restart_playthrough)
	panel.add_child(restart)

	var continue_btn := _make_modal_button("CONTINUE (sandbox)", COL_DIM, 10, 340, -44)
	continue_btn.pressed.connect(_dismiss_victory)
	panel.add_child(continue_btn)


func _make_modal_button(text: String, color: Color, left: float, right: float, top_offset: float = -44) -> Button:
	var b := Button.new()
	b.text = text
	b.anchor_left = 0.5
	b.anchor_top = 1.0
	b.anchor_right = 0.5
	b.anchor_bottom = 1.0
	b.offset_left = left
	b.offset_top = top_offset
	b.offset_right = right
	b.offset_bottom = top_offset + 28
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", COL_FG)
	return b


func _on_victory_chronicle() -> void:
	# Hide victory modal briefly, show chronicle; closing chronicle
	# returns here (tree stays paused).
	_victory_root.visible = false
	show_chronicle_modal()


func _on_victory_save() -> void:
	_victory_root.visible = false
	show_save_modal()


func _on_victory_load() -> void:
	_victory_root.visible = false
	show_load_modal()


func _on_victory(kind: String, title: String, flavor: String) -> void:
	_endrun_banner.text = "// VICTORY //"
	_endrun_banner.add_theme_color_override("font_color", COL_ACCENT)
	_victory_title_label.add_theme_color_override("font_color", COL_FG)
	_victory_kind_label.text = kind
	_victory_title_label.text = title
	_victory_flavor_label.text = flavor
	_victory_root.visible = true
	get_tree().paused = true


func _on_defeat(kind: String, title: String, flavor: String) -> void:
	_endrun_banner.text = "// DEFEAT //"
	_endrun_banner.add_theme_color_override("font_color", COL_HOT)
	_victory_title_label.add_theme_color_override("font_color", COL_HOT)
	_victory_kind_label.text = kind
	_victory_title_label.text = title
	_victory_flavor_label.text = flavor
	_victory_root.visible = true
	get_tree().paused = true


func _dismiss_victory() -> void:
	_victory_root.visible = false
	get_tree().paused = false


func _restart_playthrough() -> void:
	_victory_root.visible = false
	get_tree().paused = false
	# Full scene reload — simplest reset. All singletons persist; they
	# re-initialize their state via WorldDirector.initialize_playthrough()
	# on the new Main._ready().
	get_tree().reload_current_scene()


# -------------------------------------------------------------
# Terminal menu (DatashardTerminal activation) —
# LEAK / SELL / LOBBY / CANCEL
# -------------------------------------------------------------
func _build_terminal_menu_modal() -> void:
	_terminal_menu_root = Control.new()
	_terminal_menu_root.anchor_right = 1.0
	_terminal_menu_root.anchor_bottom = 1.0
	_terminal_menu_root.visible = false
	_terminal_menu_root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_terminal_menu_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_terminal_menu_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_terminal_menu_root.add_child(backdrop)

	var panel := _make_panel_raw(COL_BG_MODAL)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -240
	panel.offset_top = -260
	panel.offset_right = 240
	panel.offset_bottom = 260
	_terminal_menu_root.add_child(panel)

	var title := _make_label("// DATASHARD TERMINAL", COL_COOL, 15, true)
	title.offset_left = PANEL_PAD + 4
	title.offset_top = PANEL_PAD
	title.offset_right = 480 - PANEL_PAD
	title.offset_bottom = PANEL_PAD + 22
	panel.add_child(title)

	var sub := _make_label("Pick a move.", COL_DIM, 11, false)
	sub.offset_left = PANEL_PAD + 4
	sub.offset_top = PANEL_PAD + 28
	sub.offset_right = 480 - PANEL_PAD
	sub.offset_bottom = PANEL_PAD + 46
	panel.add_child(sub)

	var y := PANEL_PAD + 58
	var btn_h := 42
	var gap := 8

	var leak_btn := _make_menu_button(panel, "LEAK SCANDAL TO NETFEED",
		"Public hit. Tension rises, senate nudges populist. No payout.",
		COL_ACCENT, y, btn_h)
	leak_btn.pressed.connect(_on_terminal_leak)
	y += btn_h + gap

	var sell_btn := _make_menu_button(panel, "SELL SCANDAL TO MEDIA",
		"Corrupt option. Pays credits; Media suppresses. Senate drifts Enclave.",
		COL_WARN, y, btn_h)
	sell_btn.pressed.connect(_on_terminal_sell)
	y += btn_h + gap

	var hack_btn := _make_menu_button(panel, "HACK THE GRID",
		"Big payout. Tech oligarch hunts you. +8 heat.",
		COL_HOT, y, btn_h)
	hack_btn.pressed.connect(_on_terminal_hack)
	y += btn_h + gap

	var lobby_btn := _make_menu_button(panel, "LOBBY A POLITICIAN",
		"Bribe a senator to flip their vote on the active bill.",
		COL_COOL, y, btn_h)
	lobby_btn.pressed.connect(_on_terminal_lobby)
	y += btn_h + gap

	var shop_btn := _make_menu_button(panel, "SHOP",
		"Forged IDs (−heat), Burner Datashard (reveals bill's hidden hooks).",
		COL_COOL, y, btn_h)
	shop_btn.pressed.connect(_on_terminal_shop)
	y += btn_h + gap

	var cancel := Button.new()
	cancel.text = "CANCEL (Esc)"
	cancel.anchor_right = 1.0
	cancel.offset_left = PANEL_PAD + 4
	cancel.offset_top = y + 6
	cancel.offset_right = -PANEL_PAD - 4
	cancel.offset_bottom = y + 6 + btn_h
	cancel.add_theme_color_override("font_color", COL_DIM)
	cancel.add_theme_color_override("font_hover_color", COL_FG)
	cancel.pressed.connect(hide_terminal_menu)
	panel.add_child(cancel)


func _make_menu_button(panel: Panel, text: String, subtitle: String, color: Color, y: int, h: int) -> Button:
	var btn := Button.new()
	btn.text = "%s\n   %s" % [text, subtitle]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.anchor_right = 1.0
	btn.offset_left = PANEL_PAD + 4
	btn.offset_top = y
	btn.offset_right = -PANEL_PAD - 4
	btn.offset_bottom = y + h
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_hover_color", COL_FG)
	panel.add_child(btn)
	return btn


func show_terminal_menu() -> void:
	_terminal_menu_root.visible = true
	get_tree().paused = true


func hide_terminal_menu() -> void:
	_terminal_menu_root.visible = false
	get_tree().paused = false


func _on_terminal_leak() -> void:
	_terminal_menu_root.visible = false
	# Keep the tree paused — show_oligarch_target_modal pauses again.
	get_tree().paused = false
	show_oligarch_target_modal("leak_scandal")


func _on_terminal_sell() -> void:
	_terminal_menu_root.visible = false
	get_tree().paused = false
	show_oligarch_target_modal("sell_scandal")


func _on_terminal_lobby() -> void:
	_terminal_menu_root.visible = false
	get_tree().paused = false
	show_bribe_modal()


func _on_terminal_hack() -> void:
	_terminal_menu_root.visible = false
	get_tree().paused = false
	# The hack action is route-able through trigger_event with no target.
	WorldDirector.trigger_event("hack_grid", "")


func _on_terminal_shop() -> void:
	_terminal_menu_root.visible = false
	get_tree().paused = false
	show_shop_modal()


# -------------------------------------------------------------
# Shop modal — forged IDs + burner datashard
# -------------------------------------------------------------
const SHOP_FORGED_IDS_COST := 500
const SHOP_FORGED_IDS_HEAT_REDUCTION := 25
const SHOP_BURNER_COST := 1500

func _build_shop_modal() -> void:
	_shop_root = Control.new()
	_shop_root.anchor_right = 1.0
	_shop_root.anchor_bottom = 1.0
	_shop_root.visible = false
	_shop_root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_shop_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shop_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.6)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_shop_root.add_child(backdrop)

	var panel := _make_panel_raw(COL_BG_MODAL)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -280
	panel.offset_top = -200
	panel.offset_right = 280
	panel.offset_bottom = 200
	_shop_root.add_child(panel)

	var title := _make_label("// BLACK-MARKET SHOP", COL_COOL, 15, true)
	title.offset_left = PANEL_PAD + 4
	title.offset_top = PANEL_PAD
	title.offset_right = 560 - PANEL_PAD
	title.offset_bottom = PANEL_PAD + 22
	panel.add_child(title)

	var sub := _make_label("Two items on the rack tonight.", COL_DIM, 11, false)
	sub.offset_left = PANEL_PAD + 4
	sub.offset_top = PANEL_PAD + 28
	sub.offset_right = 560 - PANEL_PAD
	sub.offset_bottom = PANEL_PAD + 46
	panel.add_child(sub)

	# Forged IDs item
	_make_shop_row(panel, 60,
		"Forged IDs",
		"Knocks heat down %d on purchase. Standing inventory." % SHOP_FORGED_IDS_HEAT_REDUCTION,
		SHOP_FORGED_IDS_COST,
		_on_buy_forged_ids)

	# Burner Datashard
	_make_shop_row(panel, 150,
		"Burner Datashard",
		"Decrypts the current bill's honest rationale and scandal hooks. Works only while a bill is in debate.",
		SHOP_BURNER_COST,
		_on_buy_burner)

	# Secure Housing (only meaningful if homeless — see _on_buy_housing).
	# Deposit = one month's rolled rent from PlayerManager ($700–$2000).
	var housing_cost: int = 700
	if has_node("/root/PlayerManager"):
		housing_cost = int(get_node("/root/PlayerManager").housing_deposit_cost())
	_make_shop_row(panel, 240,
		"Secure Housing (if homeless)",
		"Buy back a walls-and-a-door deal. Landlord takes one month's rent up front, +8 hope, ends the homeless state.",
		housing_cost,
		_on_buy_housing)

	_shop_status = _make_label("", COL_DIM, 11, true)
	_shop_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shop_status.anchor_right = 1.0
	_shop_status.offset_left = PANEL_PAD + 4
	_shop_status.offset_top = -72
	_shop_status.offset_right = -PANEL_PAD - 4
	_shop_status.offset_bottom = -46
	_shop_status.anchor_top = 1.0
	_shop_status.anchor_bottom = 1.0
	panel.add_child(_shop_status)

	var cancel := Button.new()
	cancel.text = "CLOSE (Esc)"
	cancel.anchor_left = 0.0
	cancel.anchor_top = 1.0
	cancel.anchor_right = 0.0
	cancel.anchor_bottom = 1.0
	cancel.offset_left = PANEL_PAD
	cancel.offset_top = -44
	cancel.offset_right = 140
	cancel.offset_bottom = -PANEL_PAD
	cancel.add_theme_color_override("font_color", COL_DIM)
	cancel.add_theme_color_override("font_hover_color", COL_FG)
	cancel.pressed.connect(hide_shop_modal)
	panel.add_child(cancel)


func _make_shop_row(panel: Panel, top: int, name: String, desc: String, cost: int, on_buy: Callable) -> void:
	var nm := _make_label(name, COL_FG, 14, true)
	nm.offset_left = PANEL_PAD + 8
	nm.offset_top = PANEL_PAD + top
	nm.offset_right = 360
	nm.offset_bottom = PANEL_PAD + top + 20
	panel.add_child(nm)

	var ds := _make_label(desc, COL_DIM, 11, false)
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ds.offset_left = PANEL_PAD + 8
	ds.offset_top = PANEL_PAD + top + 20
	ds.offset_right = 360
	ds.offset_bottom = PANEL_PAD + top + 70
	panel.add_child(ds)

	var buy := Button.new()
	buy.text = "BUY — %d cr" % cost
	buy.anchor_right = 1.0
	buy.offset_left = -PANEL_PAD - 160
	buy.offset_top = PANEL_PAD + top + 12
	buy.offset_right = -PANEL_PAD - 4
	buy.offset_bottom = PANEL_PAD + top + 52
	buy.add_theme_color_override("font_color", COL_COOL)
	buy.add_theme_color_override("font_hover_color", COL_FG)
	buy.pressed.connect(on_buy)
	panel.add_child(buy)


func show_shop_modal() -> void:
	_shop_status.text = ""
	_shop_status.add_theme_color_override("font_color", COL_DIM)
	_shop_root.visible = true
	get_tree().paused = true


func hide_shop_modal() -> void:
	_shop_root.visible = false
	get_tree().paused = false


func _on_buy_forged_ids() -> void:
	var pm = get_node_or_null("/root/PlayerManager")
	if pm == null:
		return
	if not pm.can_afford(SHOP_FORGED_IDS_COST):
		_shop_status.text = "Not enough credits."
		_shop_status.add_theme_color_override("font_color", COL_HOT)
		return
	pm.spend_credits(SHOP_FORGED_IDS_COST, "forged IDs")
	pm.add_heat(-SHOP_FORGED_IDS_HEAT_REDUCTION, "forged IDs")
	_shop_status.text = "Paid %d cr. Heat down %d." % [SHOP_FORGED_IDS_COST, SHOP_FORGED_IDS_HEAT_REDUCTION]
	_shop_status.add_theme_color_override("font_color", COL_COOL)


func _on_buy_burner() -> void:
	var pm = get_node_or_null("/root/PlayerManager")
	if pm == null:
		return
	if _active_bill.is_empty():
		_shop_status.text = "No bill in debate. Burner has nothing to decrypt."
		_shop_status.add_theme_color_override("font_color", COL_HOT)
		return
	if not pm.can_afford(SHOP_BURNER_COST):
		_shop_status.text = "Not enough credits."
		_shop_status.add_theme_color_override("font_color", COL_HOT)
		return
	pm.spend_credits(SHOP_BURNER_COST, "burner datashard")
	_hooks_revealed = true
	# Re-render the senate panel so the new section shows up.
	_on_bill_proposed(_active_bill)
	_shop_status.text = "Burner hot. Senate panel now shows the honest rationale."
	_shop_status.add_theme_color_override("font_color", COL_COOL)


func _on_buy_housing() -> void:
	var pm = get_node_or_null("/root/PlayerManager")
	if pm == null:
		return
	if not pm.homeless:
		_shop_status.text = "You've got a roof already. Nothing to buy."
		_shop_status.add_theme_color_override("font_color", COL_DIM)
		return
	if pm.secure_housing():
		_shop_status.text = "Deposit paid. Welcome back inside."
		_shop_status.add_theme_color_override("font_color", COL_COOL)
	else:
		_shop_status.text = "Not enough credits for a deposit."
		_shop_status.add_theme_color_override("font_color", COL_HOT)


# -------------------------------------------------------------
# Crowd-NPC interact menu — TALK / PICKPOCKET / CANCEL
# -------------------------------------------------------------
func _build_crowd_menu_modal() -> void:
	_crowd_menu_root = Control.new()
	_crowd_menu_root.anchor_right = 1.0
	_crowd_menu_root.anchor_bottom = 1.0
	_crowd_menu_root.visible = false
	_crowd_menu_root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_crowd_menu_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_crowd_menu_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_crowd_menu_root.add_child(backdrop)

	var panel := _make_panel_raw(COL_BG_MODAL)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -220
	panel.offset_top = -140
	panel.offset_right = 220
	panel.offset_bottom = 140
	_crowd_menu_root.add_child(panel)

	_crowd_menu_title = _make_label("// CITIZEN", COL_COOL, 15, true)
	_crowd_menu_title.offset_left = PANEL_PAD + 4
	_crowd_menu_title.offset_top = PANEL_PAD
	_crowd_menu_title.offset_right = 440 - PANEL_PAD
	_crowd_menu_title.offset_bottom = PANEL_PAD + 22
	panel.add_child(_crowd_menu_title)

	_crowd_menu_subtitle = _make_label("", COL_DIM, 11, false)
	_crowd_menu_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_crowd_menu_subtitle.offset_left = PANEL_PAD + 4
	_crowd_menu_subtitle.offset_top = PANEL_PAD + 28
	_crowd_menu_subtitle.offset_right = 440 - PANEL_PAD - 4
	_crowd_menu_subtitle.offset_bottom = PANEL_PAD + 60
	panel.add_child(_crowd_menu_subtitle)

	var y := PANEL_PAD + 72
	var btn_h := 40
	var gap := 8

	var talk_btn := _make_menu_button(panel, "TALK",
		"Open a conversation. They may help — or walk away.",
		COL_COOL, y, btn_h)
	talk_btn.pressed.connect(_on_crowd_menu_talk)
	y += btn_h + gap

	var pickpocket_btn := _make_menu_button(panel, "PICKPOCKET",
		"Stealth-roll lift. Small payout, small heat. Higher risk at high conformity.",
		COL_WARN, y, btn_h)
	pickpocket_btn.pressed.connect(_on_crowd_menu_pickpocket)
	y += btn_h + gap

	var cancel := Button.new()
	cancel.text = "CANCEL (Esc)"
	cancel.anchor_right = 1.0
	cancel.offset_left = PANEL_PAD + 4
	cancel.offset_top = y + 6
	cancel.offset_right = -PANEL_PAD - 4
	cancel.offset_bottom = y + 6 + btn_h
	cancel.add_theme_color_override("font_color", COL_DIM)
	cancel.add_theme_color_override("font_hover_color", COL_FG)
	cancel.pressed.connect(hide_crowd_menu)
	panel.add_child(cancel)


func show_crowd_interact_menu(crowd) -> void:
	_active_crowd = crowd
	if crowd.npc_data:
		var d = crowd.npc_data
		_crowd_menu_title.text = "// %s" % d.npc_name.to_upper()
		_crowd_menu_subtitle.text = "%s · trust %d/100 · mood: %s" % [
			d.get_behavioral_profile(),
			int(d.trust),
			d.current_mood,
		]
	else:
		_crowd_menu_title.text = "// CITIZEN"
		_crowd_menu_subtitle.text = ""
	_crowd_menu_root.visible = true
	get_tree().paused = true


func hide_crowd_menu() -> void:
	_crowd_menu_root.visible = false
	get_tree().paused = false
	_active_crowd = null


func _on_crowd_menu_talk() -> void:
	var crowd = _active_crowd
	_crowd_menu_root.visible = false
	# Dialogue modal will pause again; keep paused through the transition.
	if crowd:
		show_dialogue_modal(crowd)


func _on_crowd_menu_pickpocket() -> void:
	var crowd = _active_crowd
	hide_crowd_menu()
	if crowd:
		crowd_pickpocket_requested.emit(crowd)


# -------------------------------------------------------------
# Cameo prompt modal (Tier-4 accept_prompt step)
# -------------------------------------------------------------
func _build_cameo_prompt_modal() -> void:
	_cameo_prompt_root = Control.new()
	_cameo_prompt_root.anchor_right = 1.0
	_cameo_prompt_root.anchor_bottom = 1.0
	_cameo_prompt_root.visible = false
	_cameo_prompt_root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_cameo_prompt_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_cameo_prompt_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.01, 0.06, 0.82)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_cameo_prompt_root.add_child(backdrop)

	var panel := _make_panel_raw(COL_BG_MODAL)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -340
	panel.offset_top = -200
	panel.offset_right = 340
	panel.offset_bottom = 200
	_cameo_prompt_root.add_child(panel)

	var banner := _make_label("// CAMEO — INVITATION", Color(0.85, 0.35, 1.00), 13, true)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.anchor_right = 1.0
	banner.offset_left = PANEL_PAD
	banner.offset_top = PANEL_PAD + 4
	banner.offset_right = -PANEL_PAD
	banner.offset_bottom = PANEL_PAD + 26
	panel.add_child(banner)

	_cameo_prompt_title = _make_label("", COL_FG, 22, true)
	_cameo_prompt_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cameo_prompt_title.anchor_right = 1.0
	_cameo_prompt_title.offset_left = PANEL_PAD
	_cameo_prompt_title.offset_top = PANEL_PAD + 34
	_cameo_prompt_title.offset_right = -PANEL_PAD
	_cameo_prompt_title.offset_bottom = PANEL_PAD + 72
	panel.add_child(_cameo_prompt_title)

	_cameo_prompt_body = _make_label("", COL_DIM, 14, false)
	_cameo_prompt_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cameo_prompt_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cameo_prompt_body.anchor_right = 1.0
	_cameo_prompt_body.offset_left = PANEL_PAD + 20
	_cameo_prompt_body.offset_top = PANEL_PAD + 80
	_cameo_prompt_body.offset_right = -PANEL_PAD - 20
	_cameo_prompt_body.offset_bottom = PANEL_PAD + 220
	panel.add_child(_cameo_prompt_body)

	_cameo_prompt_accept_btn = Button.new()
	_cameo_prompt_accept_btn.anchor_left = 0.5
	_cameo_prompt_accept_btn.anchor_top = 1.0
	_cameo_prompt_accept_btn.anchor_right = 0.5
	_cameo_prompt_accept_btn.anchor_bottom = 1.0
	_cameo_prompt_accept_btn.offset_left = 10
	_cameo_prompt_accept_btn.offset_top = -44
	_cameo_prompt_accept_btn.offset_right = 300
	_cameo_prompt_accept_btn.offset_bottom = -14
	_cameo_prompt_accept_btn.add_theme_color_override("font_color", COL_ACCENT)
	_cameo_prompt_accept_btn.add_theme_color_override("font_hover_color", COL_FG)
	_cameo_prompt_accept_btn.pressed.connect(_on_cameo_prompt_accept)
	panel.add_child(_cameo_prompt_accept_btn)

	_cameo_prompt_decline_btn = Button.new()
	_cameo_prompt_decline_btn.anchor_left = 0.5
	_cameo_prompt_decline_btn.anchor_top = 1.0
	_cameo_prompt_decline_btn.anchor_right = 0.5
	_cameo_prompt_decline_btn.anchor_bottom = 1.0
	_cameo_prompt_decline_btn.offset_left = -300
	_cameo_prompt_decline_btn.offset_top = -44
	_cameo_prompt_decline_btn.offset_right = -10
	_cameo_prompt_decline_btn.offset_bottom = -14
	_cameo_prompt_decline_btn.add_theme_color_override("font_color", COL_DIM)
	_cameo_prompt_decline_btn.add_theme_color_override("font_hover_color", COL_FG)
	_cameo_prompt_decline_btn.pressed.connect(_on_cameo_prompt_decline)
	panel.add_child(_cameo_prompt_decline_btn)


func _on_cameo_arc_prompt(arc: Dictionary, step: Dictionary) -> void:
	_active_cameo_arc_id = str(arc.get("cameo_id", ""))
	_cameo_prompt_title.text = str(step.get("prompt_title", "// CAMEO"))
	_cameo_prompt_body.text = str(step.get("prompt_body", ""))
	_cameo_prompt_accept_btn.text = str(step.get("accept_label", "ACCEPT"))
	_cameo_prompt_decline_btn.text = str(step.get("decline_label", "DECLINE"))
	_cameo_prompt_root.visible = true
	get_tree().paused = true


func _on_cameo_prompt_accept() -> void:
	var cameos = get_node_or_null("/root/CulturalCameos")
	_cameo_prompt_root.visible = false
	get_tree().paused = false
	if cameos:
		cameos.resolve_prompt(_active_cameo_arc_id, true)
	_active_cameo_arc_id = ""


func _on_cameo_prompt_decline() -> void:
	var cameos = get_node_or_null("/root/CulturalCameos")
	_cameo_prompt_root.visible = false
	get_tree().paused = false
	if cameos:
		cameos.resolve_prompt(_active_cameo_arc_id, false)
	_active_cameo_arc_id = ""


# -------------------------------------------------------------
# Cameo decision modal (Tier-4 binary_decision step)
# -------------------------------------------------------------
func _build_cameo_decision_modal() -> void:
	_cameo_decision_root = Control.new()
	_cameo_decision_root.anchor_right = 1.0
	_cameo_decision_root.anchor_bottom = 1.0
	_cameo_decision_root.visible = false
	_cameo_decision_root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_cameo_decision_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_cameo_decision_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.03, 0.01, 0.04, 0.88)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_cameo_decision_root.add_child(backdrop)

	var panel := _make_panel_raw(COL_BG_MODAL)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -380
	panel.offset_top = -280
	panel.offset_right = 380
	panel.offset_bottom = 280
	_cameo_decision_root.add_child(panel)

	var banner := _make_label("// CAMEO — THE CHOICE", Color(0.85, 0.35, 1.00), 13, true)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.anchor_right = 1.0
	banner.offset_left = PANEL_PAD
	banner.offset_top = PANEL_PAD + 4
	banner.offset_right = -PANEL_PAD
	banner.offset_bottom = PANEL_PAD + 26
	panel.add_child(banner)

	_cameo_decision_title = _make_label("", COL_FG, 22, true)
	_cameo_decision_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cameo_decision_title.anchor_right = 1.0
	_cameo_decision_title.offset_left = PANEL_PAD
	_cameo_decision_title.offset_top = PANEL_PAD + 34
	_cameo_decision_title.offset_right = -PANEL_PAD
	_cameo_decision_title.offset_bottom = PANEL_PAD + 74
	panel.add_child(_cameo_decision_title)

	_cameo_decision_body = _make_label("", COL_DIM, 13, false)
	_cameo_decision_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cameo_decision_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cameo_decision_body.anchor_right = 1.0
	_cameo_decision_body.offset_left = PANEL_PAD + 20
	_cameo_decision_body.offset_top = PANEL_PAD + 82
	_cameo_decision_body.offset_right = -PANEL_PAD - 20
	_cameo_decision_body.offset_bottom = PANEL_PAD + 170
	panel.add_child(_cameo_decision_body)

	_cameo_decision_options_box = VBoxContainer.new()
	_cameo_decision_options_box.anchor_right = 1.0
	_cameo_decision_options_box.offset_left = PANEL_PAD + 20
	_cameo_decision_options_box.offset_top = PANEL_PAD + 180
	_cameo_decision_options_box.offset_right = -PANEL_PAD - 20
	_cameo_decision_options_box.offset_bottom = -PANEL_PAD
	_cameo_decision_options_box.add_theme_constant_override("separation", 10)
	panel.add_child(_cameo_decision_options_box)


func _on_cameo_arc_decision(arc: Dictionary, step: Dictionary) -> void:
	_active_cameo_arc_id = str(arc.get("cameo_id", ""))
	_cameo_decision_title.text = str(step.get("prompt_title", "// THE CHOICE"))
	_cameo_decision_body.text = str(step.get("prompt_body", ""))

	# Rebuild option buttons
	for child in _cameo_decision_options_box.get_children():
		child.queue_free()

	var options: Array = step.get("options", [])
	for i in range(options.size()):
		var opt: Dictionary = options[i]
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)

		var btn := Button.new()
		btn.text = str(opt.get("label", "OPTION"))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_color_override("font_color", COL_WARN if i == 0 else COL_COOL)
		btn.add_theme_color_override("font_hover_color", COL_FG)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_cameo_decision_pick.bind(i))
		box.add_child(btn)

		var flavor := Label.new()
		flavor.text = "   " + str(opt.get("flavor", ""))
		flavor.add_theme_color_override("font_color", COL_DIM)
		flavor.add_theme_font_size_override("font_size", 11)
		flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(flavor)

		_cameo_decision_options_box.add_child(box)

	_cameo_decision_root.visible = true
	get_tree().paused = true


func _on_cameo_decision_pick(option_index: int) -> void:
	var cameos = get_node_or_null("/root/CulturalCameos")
	_cameo_decision_root.visible = false
	get_tree().paused = false
	if cameos:
		cameos.resolve_decision(_active_cameo_arc_id, option_index)
	_active_cameo_arc_id = ""


# -------------------------------------------------------------
# Dialogue modal — text chat with an NPC via LLMManager
# -------------------------------------------------------------
func _build_dialogue_modal() -> void:
	_dialogue_root = Control.new()
	_dialogue_root.anchor_right = 1.0
	_dialogue_root.anchor_bottom = 1.0
	_dialogue_root.visible = false
	_dialogue_root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_dialogue_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dialogue_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.68)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_dialogue_root.add_child(backdrop)

	var panel := _make_panel_raw(COL_BG_MODAL)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -380
	panel.offset_top = -260
	panel.offset_right = 380
	panel.offset_bottom = 260
	_dialogue_root.add_child(panel)

	_dialogue_status = _make_label("// DIALOGUE", COL_COOL, 13, true)
	_dialogue_status.offset_left = PANEL_PAD + 4
	_dialogue_status.offset_top = PANEL_PAD
	_dialogue_status.offset_right = 760 - PANEL_PAD
	_dialogue_status.offset_bottom = PANEL_PAD + 22
	panel.add_child(_dialogue_status)

	# Scrolling dialogue log
	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.offset_left = PANEL_PAD
	scroll.offset_top = PANEL_PAD + 30
	scroll.offset_right = -PANEL_PAD
	scroll.offset_bottom = -100
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	_dialogue_log = RichTextLabel.new()
	_dialogue_log.bbcode_enabled = true
	_dialogue_log.fit_content = true
	_dialogue_log.scroll_active = false
	_dialogue_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_log.anchor_right = 1.0
	_dialogue_log.add_theme_color_override("default_color", COL_FG)
	_dialogue_log.add_theme_font_size_override("normal_font_size", 13)
	_dialogue_log.add_theme_font_size_override("bold_font_size", 13)
	_dialogue_log.add_theme_font_size_override("italics_font_size", 13)
	scroll.add_child(_dialogue_log)

	# Input row at the bottom
	_dialogue_input = LineEdit.new()
	_dialogue_input.placeholder_text = "Say something..."
	_dialogue_input.anchor_right = 1.0
	_dialogue_input.anchor_top = 1.0
	_dialogue_input.anchor_bottom = 1.0
	_dialogue_input.offset_left = PANEL_PAD
	_dialogue_input.offset_top = -90
	_dialogue_input.offset_right = -PANEL_PAD - 230
	_dialogue_input.offset_bottom = -50
	_dialogue_input.text_submitted.connect(_on_dialogue_submit)
	panel.add_child(_dialogue_input)

	_dialogue_send_btn = Button.new()
	_dialogue_send_btn.text = "SEND"
	_dialogue_send_btn.anchor_right = 1.0
	_dialogue_send_btn.anchor_top = 1.0
	_dialogue_send_btn.anchor_bottom = 1.0
	_dialogue_send_btn.offset_left = -PANEL_PAD - 220
	_dialogue_send_btn.offset_top = -90
	_dialogue_send_btn.offset_right = -PANEL_PAD
	_dialogue_send_btn.offset_bottom = -50
	_dialogue_send_btn.add_theme_color_override("font_color", COL_ACCENT)
	_dialogue_send_btn.add_theme_color_override("font_hover_color", COL_FG)
	_dialogue_send_btn.pressed.connect(_on_dialogue_send_pressed)
	panel.add_child(_dialogue_send_btn)

	var close := Button.new()
	close.text = "CLOSE (Esc)"
	close.anchor_left = 0.0
	close.anchor_top = 1.0
	close.anchor_right = 0.0
	close.anchor_bottom = 1.0
	close.offset_left = PANEL_PAD
	close.offset_top = -42
	close.offset_right = 140
	close.offset_bottom = -PANEL_PAD
	close.add_theme_color_override("font_color", COL_DIM)
	close.add_theme_color_override("font_hover_color", COL_FG)
	close.pressed.connect(hide_dialogue_modal)
	panel.add_child(close)

	# COMMIT button — courting. Available when trust ≥ 60 and NPC isn't
	# already a partner. Unlocks polyamorous commitment; existing
	# partners may discover, with trait-driven consequences.
	_dialogue_commit_btn = Button.new()
	_dialogue_commit_btn.text = "COMMIT (need trust ≥ 60)"
	_dialogue_commit_btn.anchor_left = 0.0
	_dialogue_commit_btn.anchor_top = 1.0
	_dialogue_commit_btn.anchor_right = 0.0
	_dialogue_commit_btn.anchor_bottom = 1.0
	_dialogue_commit_btn.offset_left = 150
	_dialogue_commit_btn.offset_top = -42
	_dialogue_commit_btn.offset_right = 340
	_dialogue_commit_btn.offset_bottom = -PANEL_PAD
	_dialogue_commit_btn.add_theme_color_override("font_color", COL_WARN)
	_dialogue_commit_btn.add_theme_color_override("font_hover_color", COL_FG)
	_dialogue_commit_btn.pressed.connect(_on_dialogue_commit)
	panel.add_child(_dialogue_commit_btn)


func show_dialogue_modal(crowd) -> void:
	_dialogue_npc = crowd
	_dialogue_in_flight = false
	_dialogue_input.text = ""
	_dialogue_input.editable = true
	_dialogue_send_btn.disabled = false
	_dialogue_log.text = ""
	if crowd and crowd.npc_data:
		var d = crowd.npc_data
		var header: String = "// %s — %s (trust %d/100)" % [
			d.npc_name.to_upper(),
			d.get_behavioral_profile(),
			int(d.trust),
		]
		var pm = get_node_or_null("/root/PlayerManager")
		if pm and pm.is_romantic_partner(d.npc_id):
			header += "   ♥"
		_dialogue_status.text = header
		# Opening line from the NPC — just a narrator cue.
		_append_dialogue("[i][color=#%s]%s glances up at you.[/color][/i]" % [
			_hex(COL_DIM), d.npc_name,
		])
		_refresh_commit_button()
	_dialogue_root.visible = true
	get_tree().paused = true
	_dialogue_input.grab_focus()


func _refresh_commit_button() -> void:
	if _dialogue_npc == null or _dialogue_npc.npc_data == null:
		_dialogue_commit_btn.visible = false
		return
	var d = _dialogue_npc.npc_data
	var pm = get_node_or_null("/root/PlayerManager")
	if pm and pm.is_romantic_partner(d.npc_id):
		_dialogue_commit_btn.text = "PARTNER ♥"
		_dialogue_commit_btn.disabled = true
		_dialogue_commit_btn.visible = true
	elif d.trust >= 60.0:
		_dialogue_commit_btn.text = "COURT %s" % d.npc_name.split(" ")[0]
		_dialogue_commit_btn.disabled = false
		_dialogue_commit_btn.visible = true
	else:
		_dialogue_commit_btn.text = "COMMIT (need trust ≥ 60)"
		_dialogue_commit_btn.disabled = true
		_dialogue_commit_btn.visible = true


func _on_dialogue_commit() -> void:
	if _dialogue_npc == null or _dialogue_npc.npc_data == null:
		return
	var d = _dialogue_npc.npc_data
	if d.trust < 60.0:
		return
	var pm = get_node_or_null("/root/PlayerManager")
	if pm == null:
		return
	if pm.is_romantic_partner(d.npc_id):
		return

	d.relationship_type = 4  # Romantic
	pm.add_romantic_partner(d.npc_id)
	pm.add_hope(10.0, "new relationship with %s" % d.npc_name)

	_append_dialogue("[color=#%s]%s nods, eyes bright. 'Okay. Okay.'[/color]" % [
		_hex(COL_WARN), d.npc_name,
	])
	var others: int = pm.romantic_partner_ids.size() - 1
	if others > 0:
		_append_dialogue("[i][color=#%s]You carry %d other names. Sooner or later, someone compares notes.[/color][/i]" % [
			_hex(COL_DIM), others,
		])
	_refresh_commit_button()


func hide_dialogue_modal() -> void:
	_dialogue_root.visible = false
	get_tree().paused = false
	_dialogue_npc = null


func _on_dialogue_submit(text: String) -> void:
	_send_dialogue(text)


func _on_dialogue_send_pressed() -> void:
	_send_dialogue(_dialogue_input.text)


func _send_dialogue(text: String) -> void:
	if _dialogue_in_flight:
		return
	var stripped: String = text.strip_edges()
	if stripped == "" or _dialogue_npc == null or _dialogue_npc.npc_data == null:
		return
	var llm = get_node_or_null("/root/LLMManager")
	if llm == null:
		return

	_append_dialogue("[color=#%s]you:[/color] %s" % [_hex(COL_WARN), stripped])
	_dialogue_input.text = ""
	_dialogue_in_flight = true
	_dialogue_send_btn.disabled = true
	_dialogue_input.editable = false
	llm.request_npc_action(_dialogue_npc.npc_data, stripped)


func _on_llm_dialogue_response(data: Dictionary) -> void:
	# Only consume responses when our modal is awaiting one.
	if not _dialogue_in_flight or _dialogue_npc == null or _dialogue_npc.npc_data == null:
		return
	_dialogue_in_flight = false
	_dialogue_send_btn.disabled = false
	_dialogue_input.editable = true
	_dialogue_input.grab_focus()

	var dialogue_text: String = str(data.get("dialogue", ""))
	var goal: String = str(data.get("assigned_goal", "idle"))
	var success: bool = bool(data.get("success", false))

	var name_str: String = _dialogue_npc.npc_data.npc_name
	_append_dialogue("[color=#%s]%s:[/color] %s" % [
		_hex(COL_COOL), name_str, dialogue_text,
	])

	# Apply assigned_goal side-effects to the NPCData.
	var d = _dialogue_npc.npc_data
	match goal:
		"assist":
			if success:
				d.trust = min(100.0, d.trust + 5.0)
				d.opinion_of_player = min(1.0, d.opinion_of_player + 0.05)
				_append_dialogue("[i][color=#%s](trust +5)[/color][/i]" % _hex(COL_WARN))
		"flee":
			if success:
				d.knowledge_of_player = min(1.0, d.knowledge_of_player + 0.2)
				_append_dialogue("[i][color=#%s]%s walks off.[/color][/i]" % [
					_hex(COL_DIM), name_str,
				])
				# Close after a beat so the player can read the last line.
				await get_tree().create_timer(0.8).timeout
				hide_dialogue_modal()
				if _dialogue_npc and _dialogue_npc.has_method("flee"):
					_dialogue_npc.flee()
		"attack":
			# Hostility not yet wired into combat — record it on the NPC.
			d.opinion_of_player = max(-1.0, d.opinion_of_player - 0.2)
			_append_dialogue("[i][color=#%s](they'll remember this)[/color][/i]" % _hex(COL_HOT))

	# Refresh the status line with updated trust
	_dialogue_status.text = "// %s — %s (trust %d/100)" % [
		name_str.to_upper(),
		d.get_behavioral_profile(),
		int(d.trust),
	]


func _append_dialogue(bbcode_line: String) -> void:
	if _dialogue_log.text != "":
		_dialogue_log.text += "\n"
	_dialogue_log.text += bbcode_line


# -------------------------------------------------------------
# Travel modal — pick a region to travel to via a TransitZone
# -------------------------------------------------------------
func _build_travel_modal() -> void:
	_travel_root = Control.new()
	_travel_root.anchor_right = 1.0
	_travel_root.anchor_bottom = 1.0
	_travel_root.visible = false
	_travel_root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_travel_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_travel_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.6)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_travel_root.add_child(backdrop)

	var panel := _make_panel_raw(COL_BG_MODAL)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -340
	panel.offset_top = -260
	panel.offset_right = 340
	panel.offset_bottom = 260
	_travel_root.add_child(panel)

	var title := _make_label("// TRAVEL — SELECT DESTINATION", COL_ACCENT, 15, true)
	title.offset_left = PANEL_PAD + 4
	title.offset_top = PANEL_PAD
	title.offset_right = 680 - PANEL_PAD
	title.offset_bottom = PANEL_PAD + 22
	panel.add_child(title)

	var sub := _make_label("Your current region is marked. Travel takes you to a fresh landscape — same world state, new streets.", COL_DIM, 11, false)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.offset_left = PANEL_PAD + 4
	sub.offset_top = PANEL_PAD + 28
	sub.offset_right = 680 - PANEL_PAD - 4
	sub.offset_bottom = PANEL_PAD + 60
	panel.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.offset_left = PANEL_PAD
	scroll.offset_top = PANEL_PAD + 66
	scroll.offset_right = -PANEL_PAD
	scroll.offset_bottom = -60
	panel.add_child(scroll)

	_travel_list = VBoxContainer.new()
	_travel_list.anchor_right = 1.0
	_travel_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_travel_list)

	var cancel := Button.new()
	cancel.text = "CANCEL (Esc)"
	cancel.anchor_left = 0.0
	cancel.anchor_top = 1.0
	cancel.anchor_right = 0.0
	cancel.anchor_bottom = 1.0
	cancel.offset_left = PANEL_PAD
	cancel.offset_top = -44
	cancel.offset_right = 140
	cancel.offset_bottom = -PANEL_PAD
	cancel.add_theme_color_override("font_color", COL_DIM)
	cancel.add_theme_color_override("font_hover_color", COL_FG)
	cancel.pressed.connect(hide_travel_modal)
	panel.add_child(cancel)


func show_travel_modal() -> void:
	_refresh_travel_list()
	_travel_root.visible = true
	get_tree().paused = true


func hide_travel_modal() -> void:
	_travel_root.visible = false
	get_tree().paused = false


func _refresh_travel_list() -> void:
	for child in _travel_list.get_children():
		child.queue_free()

	var region_gen = get_node_or_null("/root/RegionGenerator")
	if region_gen == null:
		var err := Label.new()
		err.text = "RegionGenerator not loaded."
		err.add_theme_color_override("font_color", COL_HOT)
		_travel_list.add_child(err)
		return

	var current: String = WorldDirector.current_region
	for region in region_gen.regions:
		if not bool(region.get("unlocked", false)):
			continue
		_travel_list.add_child(_build_travel_row(region, current))


func _build_travel_row(region: Dictionary, current: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)

	var name_row := Label.new()
	var is_current: bool = str(region.get("name", "")) == current
	var marker: String = "[CURRENT]  " if is_current else ""
	name_row.text = "%s%s" % [marker, str(region.get("name", "?"))]
	name_row.add_theme_color_override("font_color", COL_WARN if is_current else COL_FG)
	name_row.add_theme_font_size_override("font_size", 14)
	info.add_child(name_row)

	var meta := Label.new()
	meta.text = "type: %s   biome: %s   tension: %+d   security: %+d" % [
		str(region.get("type", "?")),
		str(region.get("visual_biome", "?")),
		int(region.get("tension_modifier", 0)),
		int(region.get("security_modifier", 0)),
	]
	meta.add_theme_color_override("font_color", COL_DIM)
	meta.add_theme_font_size_override("font_size", 10)
	info.add_child(meta)

	var desc: String = str(region.get("short_description", ""))
	if desc != "":
		var dlabel := Label.new()
		dlabel.text = desc
		dlabel.add_theme_color_override("font_color", COL_COOL)
		dlabel.add_theme_font_size_override("font_size", 11)
		dlabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(dlabel)

	row.add_child(info)

	if not is_current:
		var travel_btn := Button.new()
		travel_btn.text = "TRAVEL"
		travel_btn.add_theme_color_override("font_color", COL_ACCENT)
		travel_btn.add_theme_color_override("font_hover_color", COL_FG)
		travel_btn.pressed.connect(_on_travel_pick.bind(str(region.get("name", ""))))
		row.add_child(travel_btn)
	else:
		var here := Label.new()
		here.text = "(here)"
		here.add_theme_color_override("font_color", COL_DIM)
		here.add_theme_font_size_override("font_size", 11)
		row.add_child(here)

	return row


func _on_travel_pick(region_name: String) -> void:
	hide_travel_modal()
	travel_requested.emit(region_name)


# -------------------------------------------------------------
# Enforcer encounter modal — a patrol flagged you. Three options:
# BRIBE (not accepted at heat > 80), FLEE (stealth roll), SUBMIT (→ defeat).
# -------------------------------------------------------------
const BRIBE_BASE_RATE := 200  # credits per 20 heat, min 200
const BRIBE_HEAT_CAP := 80    # above this, enforcer won't accept a bribe
const BRIBE_HEAT_REDUCTION := 20  # bribed enforcer lets heat cool slightly
const FLEE_SUCCESS_HEAT_REDUCTION := 10
const FLEE_FAIL_HEAT_PENALTY := 25

func _build_encounter_modal() -> void:
	_encounter_root = Control.new()
	_encounter_root.anchor_right = 1.0
	_encounter_root.anchor_bottom = 1.0
	_encounter_root.visible = false
	_encounter_root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_encounter_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_encounter_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.10, 0.02, 0.02, 0.72)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_encounter_root.add_child(backdrop)

	var panel := _make_panel_raw(COL_BG_MODAL)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -280
	panel.offset_top = -200
	panel.offset_right = 280
	panel.offset_bottom = 200
	_encounter_root.add_child(panel)

	var banner := _make_label("// ENFORCER CHECKPOINT //", COL_HOT, 13, true)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.anchor_left = 0.0
	banner.anchor_top = 0.0
	banner.anchor_right = 1.0
	banner.offset_left = PANEL_PAD
	banner.offset_top = PANEL_PAD + 4
	banner.offset_right = -PANEL_PAD
	banner.offset_bottom = PANEL_PAD + 26
	panel.add_child(banner)

	_encounter_heading = _make_label("Halt.", COL_FG, 20, true)
	_encounter_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_encounter_heading.anchor_left = 0.0
	_encounter_heading.anchor_top = 0.0
	_encounter_heading.anchor_right = 1.0
	_encounter_heading.offset_left = PANEL_PAD
	_encounter_heading.offset_top = PANEL_PAD + 36
	_encounter_heading.offset_right = -PANEL_PAD
	_encounter_heading.offset_bottom = PANEL_PAD + 64
	panel.add_child(_encounter_heading)

	_encounter_body = _make_label("", COL_DIM, 12, false)
	_encounter_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_encounter_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_encounter_body.anchor_left = 0.0
	_encounter_body.anchor_top = 0.0
	_encounter_body.anchor_right = 1.0
	_encounter_body.offset_left = PANEL_PAD + 20
	_encounter_body.offset_top = PANEL_PAD + 70
	_encounter_body.offset_right = -PANEL_PAD - 20
	_encounter_body.offset_bottom = PANEL_PAD + 130
	panel.add_child(_encounter_body)

	var btn_top: int = PANEL_PAD + 145
	var btn_w: int = 520
	var btn_h: int = 36

	_encounter_bribe_btn = Button.new()
	_encounter_bribe_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_encounter_bribe_btn.anchor_right = 1.0
	_encounter_bribe_btn.offset_left = PANEL_PAD
	_encounter_bribe_btn.offset_top = btn_top
	_encounter_bribe_btn.offset_right = -PANEL_PAD
	_encounter_bribe_btn.offset_bottom = btn_top + btn_h
	_encounter_bribe_btn.add_theme_color_override("font_color", COL_WARN)
	_encounter_bribe_btn.add_theme_color_override("font_hover_color", COL_FG)
	_encounter_bribe_btn.pressed.connect(_on_encounter_bribe)
	panel.add_child(_encounter_bribe_btn)

	btn_top += btn_h + 6

	_encounter_flee_btn = Button.new()
	_encounter_flee_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_encounter_flee_btn.anchor_right = 1.0
	_encounter_flee_btn.offset_left = PANEL_PAD
	_encounter_flee_btn.offset_top = btn_top
	_encounter_flee_btn.offset_right = -PANEL_PAD
	_encounter_flee_btn.offset_bottom = btn_top + btn_h
	_encounter_flee_btn.add_theme_color_override("font_color", COL_COOL)
	_encounter_flee_btn.add_theme_color_override("font_hover_color", COL_FG)
	_encounter_flee_btn.pressed.connect(_on_encounter_flee)
	panel.add_child(_encounter_flee_btn)

	btn_top += btn_h + 6

	_encounter_submit_btn = Button.new()
	_encounter_submit_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_encounter_submit_btn.text = "SUBMIT — run ends, arrest flavor"
	_encounter_submit_btn.anchor_right = 1.0
	_encounter_submit_btn.offset_left = PANEL_PAD
	_encounter_submit_btn.offset_top = btn_top
	_encounter_submit_btn.offset_right = -PANEL_PAD
	_encounter_submit_btn.offset_bottom = btn_top + btn_h
	_encounter_submit_btn.add_theme_color_override("font_color", COL_HOT)
	_encounter_submit_btn.add_theme_color_override("font_hover_color", COL_FG)
	_encounter_submit_btn.pressed.connect(_on_encounter_submit)
	panel.add_child(_encounter_submit_btn)


func show_enforcer_encounter(patrol) -> void:
	_active_encounter_patrol = patrol

	var pm = get_node_or_null("/root/PlayerManager")
	var heat: int = int(pm.heat) if pm else 0
	var stealth: float = float(pm.player_stealth_preference) if pm else 0.0

	_encounter_computed_bribe_cost = _compute_bribe_cost(heat)
	_encounter_computed_flee_chance = _compute_flee_chance(stealth)

	_encounter_heading.text = "Halt."
	_encounter_body.text = "An Enforcer flags you down. Your heat reads %d/100. Their squad is listening in." % heat

	# BRIBE — disabled if heat too high or not enough credits
	if heat > BRIBE_HEAT_CAP:
		_encounter_bribe_btn.text = "BRIBE — they won't take it tonight"
		_encounter_bribe_btn.disabled = true
	elif pm and not pm.can_afford(_encounter_computed_bribe_cost):
		_encounter_bribe_btn.text = "BRIBE — %d cr (you can't afford)" % _encounter_computed_bribe_cost
		_encounter_bribe_btn.disabled = true
	else:
		_encounter_bribe_btn.text = "BRIBE — %d cr (waved through)" % _encounter_computed_bribe_cost
		_encounter_bribe_btn.disabled = false

	# FLEE
	_encounter_flee_btn.text = "FLEE — %d%% escape (stealth-weighted)" % int(_encounter_computed_flee_chance * 100.0)
	_encounter_flee_btn.disabled = false

	_encounter_root.visible = true
	get_tree().paused = true


func _compute_bribe_cost(heat: int) -> int:
	return max(200, int(heat * BRIBE_BASE_RATE / 20.0))


func _compute_flee_chance(stealth: float) -> float:
	return clamp(0.30 + stealth * 0.55, 0.10, 0.90)


func _close_encounter_and_resolve_patrol() -> void:
	if _active_encounter_patrol and is_instance_valid(_active_encounter_patrol):
		_active_encounter_patrol.resolve()
	_active_encounter_patrol = null
	_encounter_root.visible = false
	get_tree().paused = false


func _on_encounter_bribe() -> void:
	var pm = get_node_or_null("/root/PlayerManager")
	if pm == null:
		return
	if not pm.spend_credits(_encounter_computed_bribe_cost, "enforcer bribe"):
		return
	pm.add_heat(-BRIBE_HEAT_REDUCTION, "enforcer waved through")
	_publish_feed_note("An Enforcer patrol was 'resolved' at a checkpoint near the Sinks. No incident report filed.")
	_close_encounter_and_resolve_patrol()


func _on_encounter_flee() -> void:
	var pm = get_node_or_null("/root/PlayerManager")
	if pm == null:
		return
	var roll: float = randf()
	var failed_position: Vector3 = Vector3.ZERO
	if _active_encounter_patrol and is_instance_valid(_active_encounter_patrol):
		failed_position = _active_encounter_patrol.global_position

	if roll < _encounter_computed_flee_chance:
		pm.add_heat(-FLEE_SUCCESS_HEAT_REDUCTION, "flee: clean break")
		_publish_feed_note("A fugitive slipped an Enforcer patrol cordon near the checkpoint. Descriptions conflict.")
	else:
		pm.add_heat(FLEE_FAIL_HEAT_PENALTY, "flee: ID'd")
		_publish_feed_note("Enforcer body-cam footage captures a flagged person-of-interest attempting evasion. ID confirmed.")
		# Signal to Main → LandscapeGenerator.raise_alert with reinforcements.
		enforcer_flee_failed.emit(failed_position)
	_close_encounter_and_resolve_patrol()


func _on_encounter_submit() -> void:
	var pm = get_node_or_null("/root/PlayerManager")
	if pm == null:
		return
	# Despawn the patrol BEFORE firing defeat so the landscape is clean
	# if the player picks CONTINUE on the defeat modal.
	if _active_encounter_patrol and is_instance_valid(_active_encounter_patrol):
		_active_encounter_patrol.resolve()
	_active_encounter_patrol = null
	_encounter_root.visible = false

	# Force a defeat with surrender flavor, bypassing heat-cap-only path.
	pm.fire_defeat(
		"SURRENDERED",
		"SURRENDERED",
		"You walked up with hands visible. The shackles came out. The Enclave breathes easier tonight."
	)


func _publish_feed_note(text: String) -> void:
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


# -------------------------------------------------------------
# Politician bribe modal
# -------------------------------------------------------------
func _build_bribe_modal() -> void:
	_bribe_root = Control.new()
	_bribe_root.anchor_right = 1.0
	_bribe_root.anchor_bottom = 1.0
	_bribe_root.visible = false
	_bribe_root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_bribe_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bribe_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.6)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_bribe_root.add_child(backdrop)

	var panel := _make_panel_raw(COL_BG_MODAL)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -380
	panel.offset_top = -260
	panel.offset_right = 380
	panel.offset_bottom = 260
	_bribe_root.add_child(panel)

	_bribe_title = _make_label("// LOBBY SENATOR", COL_ACCENT, 15, true)
	_bribe_title.offset_left = PANEL_PAD + 4
	_bribe_title.offset_top = PANEL_PAD
	_bribe_title.offset_right = 760 - PANEL_PAD
	_bribe_title.offset_bottom = PANEL_PAD + 22
	panel.add_child(_bribe_title)

	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.offset_left = PANEL_PAD
	scroll.offset_top = PANEL_PAD + 32
	scroll.offset_right = -PANEL_PAD
	scroll.offset_bottom = -80
	panel.add_child(scroll)

	_bribe_list = VBoxContainer.new()
	_bribe_list.anchor_right = 1.0
	_bribe_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_bribe_list)

	_bribe_status = _make_label("", COL_DIM, 11, true)
	_bribe_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bribe_status.anchor_right = 1.0
	_bribe_status.offset_left = PANEL_PAD + 4
	_bribe_status.offset_top = -72
	_bribe_status.offset_right = -PANEL_PAD - 4
	_bribe_status.offset_bottom = -46
	_bribe_status.anchor_top = 1.0
	_bribe_status.anchor_bottom = 1.0
	panel.add_child(_bribe_status)

	var cancel := Button.new()
	cancel.text = "CANCEL (Esc)"
	cancel.anchor_left = 0.0
	cancel.anchor_top = 1.0
	cancel.anchor_right = 0.0
	cancel.anchor_bottom = 1.0
	cancel.offset_left = PANEL_PAD
	cancel.offset_top = -44
	cancel.offset_right = 140
	cancel.offset_bottom = -PANEL_PAD
	cancel.add_theme_color_override("font_color", COL_DIM)
	cancel.add_theme_color_override("font_hover_color", COL_FG)
	cancel.pressed.connect(hide_bribe_modal)
	panel.add_child(cancel)


func show_bribe_modal() -> void:
	_refresh_bribe_list()
	_bribe_root.visible = true
	get_tree().paused = true


func hide_bribe_modal() -> void:
	_bribe_root.visible = false
	get_tree().paused = false


func _refresh_bribe_list() -> void:
	for child in _bribe_list.get_children():
		child.queue_free()

	if _active_bill.is_empty():
		_bribe_title.text = "// LOBBY SENATOR"
		var note := Label.new()
		note.text = "No bill currently in debate. A bribe now will apply to the NEXT bill the Senate proposes."
		note.add_theme_color_override("font_color", COL_DIM)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_bribe_list.add_child(note)
	else:
		_bribe_title.text = "// LOBBY SENATOR — on: %s" % str(_active_bill.get("title", ""))

	_bribe_status.text = ""

	for p in WorldDirector.politicians:
		if not p.alive:
			continue
		_bribe_list.add_child(_build_bribe_row(p))


func _build_bribe_row(p) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	# Left: name + faction + predicted stance + already-bribed indicator
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)

	var nm := Label.new()
	var warn_mark := ""
	if p.scandal_level > 50.0:
		warn_mark = "[SCANDAL] "
	nm.text = "%s%s   (%s, %s)" % [warn_mark, p.politician_name, p.faction, p.get_behavioral_profile()]
	nm.add_theme_color_override("font_color", COL_FG)
	nm.add_theme_font_size_override("font_size", 13)
	info.add_child(nm)

	var meta := Label.new()
	var predicted := ""
	if not _active_bill.is_empty():
		predicted = p.evaluate_bill(_active_bill, WorldDirector.global_economy, [])
	var bribe_note := ""
	if p.pending_bribe_direction > 0:
		bribe_note = "  [bribed: YES]"
	elif p.pending_bribe_direction < 0:
		bribe_note = "  [bribed: NO]"
	var effective_cost: int = WorldDirector.effective_bribe_cost(p)
	var base_cost: int = p.get_bribe_cost()
	var cost_display: String = str(effective_cost)
	if effective_cost != base_cost:
		# Heat surcharge in play — flag it so the player sees why it's high.
		cost_display = "%d (heat surcharge)" % effective_cost
	meta.text = "predicted: %s%s   cost: %s" % [
		predicted if predicted != "" else "—",
		bribe_note,
		cost_display,
	]
	meta.add_theme_color_override("font_color", COL_DIM)
	meta.add_theme_font_size_override("font_size", 11)
	info.add_child(meta)

	row.add_child(info)

	# Right: two buttons
	var yes_btn := Button.new()
	yes_btn.text = "→ YES"
	yes_btn.add_theme_color_override("font_color", COL_WARN)
	yes_btn.add_theme_color_override("font_hover_color", COL_FG)
	yes_btn.pressed.connect(_on_bribe_pick.bind(p.politician_id, "YES"))
	row.add_child(yes_btn)

	var no_btn := Button.new()
	no_btn.text = "→ NO"
	no_btn.add_theme_color_override("font_color", COL_COOL)
	no_btn.add_theme_color_override("font_hover_color", COL_FG)
	no_btn.pressed.connect(_on_bribe_pick.bind(p.politician_id, "NO"))
	row.add_child(no_btn)

	# Disable if player can't afford (effective cost, post-heat multiplier)
	var pm = get_node_or_null("/root/PlayerManager")
	if pm and not pm.can_afford(effective_cost):
		yes_btn.disabled = true
		no_btn.disabled = true

	return row


func _on_bribe_pick(politician_id: String, direction: String) -> void:
	politician_bribed.emit(politician_id, direction)
	# Let Main apply the ripple, then refresh the modal so the user sees the update.
	call_deferred("_refresh_bribe_list")
	var pm = get_node_or_null("/root/PlayerManager")
	if pm:
		_bribe_status.text = "Paid. Credits remaining: %d" % pm.credits
		_bribe_status.add_theme_color_override("font_color", COL_COOL)


# -------------------------------------------------------------
# Save modal (F5 / victory modal → SAVE button)
# -------------------------------------------------------------
func _build_save_modal() -> void:
	_save_root = Control.new()
	_save_root.anchor_left = 0.0
	_save_root.anchor_top = 0.0
	_save_root.anchor_right = 1.0
	_save_root.anchor_bottom = 1.0
	_save_root.visible = false
	_save_root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_save_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_save_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.6)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_save_root.add_child(backdrop)

	var panel := _make_panel_raw(COL_BG_MODAL)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -240
	panel.offset_top = -150
	panel.offset_right = 240
	panel.offset_bottom = 150
	_save_root.add_child(panel)

	var title := _make_label("// SAVE WORLD", COL_ACCENT, 15, true)
	title.offset_left = PANEL_PAD + 4
	title.offset_top = PANEL_PAD
	title.offset_right = 480 - PANEL_PAD
	title.offset_bottom = PANEL_PAD + 20
	panel.add_child(title)

	var sub := _make_label("A world config captures regions, oligarchs, politicians, and citizens. Shareable.", COL_DIM, 11, false)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.offset_left = PANEL_PAD + 4
	sub.offset_top = PANEL_PAD + 24
	sub.offset_right = 480 - PANEL_PAD - 4
	sub.offset_bottom = PANEL_PAD + 58
	panel.add_child(sub)

	var name_label := _make_label("NAME", COL_COOL, 11, true)
	name_label.offset_left = PANEL_PAD + 4
	name_label.offset_top = PANEL_PAD + 66
	name_label.offset_right = 200
	name_label.offset_bottom = PANEL_PAD + 82
	panel.add_child(name_label)

	_save_name_input = LineEdit.new()
	_save_name_input.placeholder_text = "world name"
	_save_name_input.anchor_left = 0.0
	_save_name_input.anchor_right = 1.0
	_save_name_input.offset_left = PANEL_PAD + 4
	_save_name_input.offset_top = PANEL_PAD + 84
	_save_name_input.offset_right = -PANEL_PAD - 4
	_save_name_input.offset_bottom = PANEL_PAD + 116
	panel.add_child(_save_name_input)

	var desc_label := _make_label("DESCRIPTION (optional)", COL_COOL, 11, true)
	desc_label.offset_left = PANEL_PAD + 4
	desc_label.offset_top = PANEL_PAD + 122
	desc_label.offset_right = 260
	desc_label.offset_bottom = PANEL_PAD + 138
	panel.add_child(desc_label)

	_save_desc_input = LineEdit.new()
	_save_desc_input.placeholder_text = "why is this world worth keeping?"
	_save_desc_input.anchor_left = 0.0
	_save_desc_input.anchor_right = 1.0
	_save_desc_input.offset_left = PANEL_PAD + 4
	_save_desc_input.offset_top = PANEL_PAD + 140
	_save_desc_input.offset_right = -PANEL_PAD - 4
	_save_desc_input.offset_bottom = PANEL_PAD + 172
	panel.add_child(_save_desc_input)

	_save_status_label = _make_label("", COL_DIM, 11, true)
	_save_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_save_status_label.anchor_right = 1.0
	_save_status_label.offset_left = PANEL_PAD + 4
	_save_status_label.offset_top = PANEL_PAD + 180
	_save_status_label.offset_right = -PANEL_PAD - 4
	_save_status_label.offset_bottom = PANEL_PAD + 230
	panel.add_child(_save_status_label)

	var save_btn := Button.new()
	save_btn.text = "SAVE"
	save_btn.anchor_left = 1.0
	save_btn.anchor_top = 1.0
	save_btn.anchor_right = 1.0
	save_btn.anchor_bottom = 1.0
	save_btn.offset_left = -110
	save_btn.offset_top = -44
	save_btn.offset_right = -PANEL_PAD
	save_btn.offset_bottom = -PANEL_PAD
	save_btn.add_theme_color_override("font_color", COL_ACCENT)
	save_btn.add_theme_color_override("font_hover_color", COL_FG)
	save_btn.pressed.connect(_on_save_confirmed)
	panel.add_child(save_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "CANCEL (Esc)"
	cancel_btn.anchor_left = 0.0
	cancel_btn.anchor_top = 1.0
	cancel_btn.anchor_right = 0.0
	cancel_btn.anchor_bottom = 1.0
	cancel_btn.offset_left = PANEL_PAD
	cancel_btn.offset_top = -44
	cancel_btn.offset_right = 140
	cancel_btn.offset_bottom = -PANEL_PAD
	cancel_btn.add_theme_color_override("font_color", COL_DIM)
	cancel_btn.add_theme_color_override("font_hover_color", COL_FG)
	cancel_btn.pressed.connect(hide_save_modal)
	panel.add_child(cancel_btn)


func show_save_modal() -> void:
	var cfg_mgr = get_node_or_null("/root/WorldConfigManager")
	if cfg_mgr:
		_save_name_input.text = cfg_mgr.suggest_name()
	else:
		_save_name_input.text = "Untitled World"
	_save_desc_input.text = ""
	_save_status_label.text = ""
	_save_status_label.add_theme_color_override("font_color", COL_DIM)
	_save_root.visible = true
	get_tree().paused = true
	_save_name_input.grab_focus()


func hide_save_modal() -> void:
	_save_root.visible = false
	get_tree().paused = false


func _on_save_confirmed() -> void:
	var cfg_mgr = get_node_or_null("/root/WorldConfigManager")
	if cfg_mgr == null:
		_save_status_label.text = "WorldConfigManager not loaded."
		_save_status_label.add_theme_color_override("font_color", COL_HOT)
		return
	var nm: String = _save_name_input.text.strip_edges()
	if nm == "":
		_save_status_label.text = "Name required."
		_save_status_label.add_theme_color_override("font_color", COL_HOT)
		return
	var filepath: String = cfg_mgr.save_current(nm, _save_desc_input.text.strip_edges())
	if filepath == "":
		_save_status_label.text = "Save failed. Check console."
		_save_status_label.add_theme_color_override("font_color", COL_HOT)
		return
	var global: String = ProjectSettings.globalize_path(filepath)
	_save_status_label.text = "Saved. File: %s" % global
	_save_status_label.add_theme_color_override("font_color", COL_COOL)


# -------------------------------------------------------------
# Load modal (F9 / victory modal → LOAD button)
# -------------------------------------------------------------
func _build_load_modal() -> void:
	_load_root = Control.new()
	_load_root.anchor_right = 1.0
	_load_root.anchor_bottom = 1.0
	_load_root.visible = false
	_load_root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_load_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_load_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.6)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_load_root.add_child(backdrop)

	var panel := _make_panel_raw(COL_BG_MODAL)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -360
	panel.offset_top = -260
	panel.offset_right = 360
	panel.offset_bottom = 260
	_load_root.add_child(panel)

	var title := _make_label("// LOAD WORLD", COL_ACCENT, 15, true)
	title.offset_left = PANEL_PAD + 4
	title.offset_top = PANEL_PAD
	title.offset_right = 720 - PANEL_PAD
	title.offset_bottom = PANEL_PAD + 20
	panel.add_child(title)

	var sub := _make_label("Saved configs on this machine — or paste JSON someone shared with you.", COL_DIM, 11, false)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.offset_left = PANEL_PAD + 4
	sub.offset_top = PANEL_PAD + 24
	sub.offset_right = 720 - PANEL_PAD - 4
	sub.offset_bottom = PANEL_PAD + 42
	panel.add_child(sub)

	# Section 1: saved list (top half of panel)
	var saved_label := _make_label("SAVED WORLDS", COL_COOL, 11, true)
	saved_label.offset_left = PANEL_PAD + 4
	saved_label.offset_top = PANEL_PAD + 52
	saved_label.offset_right = 300
	saved_label.offset_bottom = PANEL_PAD + 68
	panel.add_child(saved_label)

	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.offset_left = PANEL_PAD
	scroll.offset_top = PANEL_PAD + 72
	scroll.offset_right = -PANEL_PAD
	scroll.offset_bottom = PANEL_PAD + 262
	panel.add_child(scroll)

	_load_list = VBoxContainer.new()
	_load_list.anchor_right = 1.0
	_load_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_load_list)

	# Section 2: paste-to-import (bottom half)
	var paste_label := _make_label("PASTE JSON", COL_COOL, 11, true)
	paste_label.offset_left = PANEL_PAD + 4
	paste_label.offset_top = PANEL_PAD + 272
	paste_label.offset_right = 300
	paste_label.offset_bottom = PANEL_PAD + 288
	panel.add_child(paste_label)

	_load_paste_input = TextEdit.new()
	_load_paste_input.placeholder_text = "paste a shared world config JSON here"
	_load_paste_input.anchor_right = 1.0
	_load_paste_input.offset_left = PANEL_PAD
	_load_paste_input.offset_top = PANEL_PAD + 292
	_load_paste_input.offset_right = -PANEL_PAD - 140
	_load_paste_input.offset_bottom = PANEL_PAD + 420
	panel.add_child(_load_paste_input)

	var import_btn := Button.new()
	import_btn.text = "IMPORT"
	import_btn.anchor_left = 1.0
	import_btn.anchor_right = 1.0
	import_btn.offset_left = -130
	import_btn.offset_top = PANEL_PAD + 292
	import_btn.offset_right = -PANEL_PAD
	import_btn.offset_bottom = PANEL_PAD + 334
	import_btn.add_theme_color_override("font_color", COL_ACCENT)
	import_btn.add_theme_color_override("font_hover_color", COL_FG)
	import_btn.pressed.connect(_on_paste_import)
	panel.add_child(import_btn)

	_load_status_label = _make_label("", COL_DIM, 11, true)
	_load_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_load_status_label.anchor_right = 1.0
	_load_status_label.offset_left = PANEL_PAD + 4
	_load_status_label.offset_top = PANEL_PAD + 426
	_load_status_label.offset_right = -PANEL_PAD - 4
	_load_status_label.offset_bottom = PANEL_PAD + 460
	panel.add_child(_load_status_label)

	var cancel_btn := Button.new()
	cancel_btn.text = "CANCEL (Esc)"
	cancel_btn.anchor_left = 0.0
	cancel_btn.anchor_top = 1.0
	cancel_btn.anchor_right = 0.0
	cancel_btn.anchor_bottom = 1.0
	cancel_btn.offset_left = PANEL_PAD
	cancel_btn.offset_top = -44
	cancel_btn.offset_right = 140
	cancel_btn.offset_bottom = -PANEL_PAD
	cancel_btn.add_theme_color_override("font_color", COL_DIM)
	cancel_btn.add_theme_color_override("font_hover_color", COL_FG)
	cancel_btn.pressed.connect(hide_load_modal)
	panel.add_child(cancel_btn)


func show_load_modal() -> void:
	_refresh_load_list()
	_load_paste_input.text = ""
	_load_status_label.text = ""
	_load_status_label.add_theme_color_override("font_color", COL_DIM)
	_load_root.visible = true
	get_tree().paused = true


func hide_load_modal() -> void:
	_load_root.visible = false
	get_tree().paused = false


func _refresh_load_list() -> void:
	for child in _load_list.get_children():
		child.queue_free()

	var cfg_mgr = get_node_or_null("/root/WorldConfigManager")
	if cfg_mgr == null:
		var err := Label.new()
		err.text = "WorldConfigManager not loaded."
		err.add_theme_color_override("font_color", COL_HOT)
		_load_list.add_child(err)
		return

	var saved: Array = cfg_mgr.list_saved()
	if saved.is_empty():
		var empty := Label.new()
		empty.text = "No saved worlds yet. Press F5 mid-game to save one."
		empty.add_theme_color_override("font_color", COL_DIM)
		_load_list.add_child(empty)
		return

	for entry in saved:
		_load_list.add_child(_build_load_row(entry))


func _build_load_row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	var nm := Label.new()
	nm.text = str(entry.get("name", "(unnamed)"))
	nm.add_theme_color_override("font_color", COL_FG)
	nm.add_theme_font_size_override("font_size", 14)
	info.add_child(nm)

	var meta := Label.new()
	var region_count: int = int(entry.get("region_count", 0))
	var oligarch_count: int = int(entry.get("oligarch_count", 0))
	var politician_count: int = int(entry.get("politician_count", 0))
	meta.text = "%d regions · %d oligarchs · %d politicians · %s" % [
		region_count, oligarch_count, politician_count,
		str(entry.get("created_at", "")),
	]
	meta.add_theme_color_override("font_color", COL_DIM)
	meta.add_theme_font_size_override("font_size", 10)
	info.add_child(meta)

	if entry.get("description", "") != "":
		var desc := Label.new()
		desc.text = str(entry.get("description", ""))
		desc.add_theme_color_override("font_color", COL_COOL)
		desc.add_theme_font_size_override("font_size", 11)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(desc)

	row.add_child(info)

	var filepath: String = str(entry.get("filepath", ""))

	var load_btn := Button.new()
	load_btn.text = "LOAD"
	load_btn.add_theme_color_override("font_color", COL_ACCENT)
	load_btn.pressed.connect(_on_load_pick.bind(filepath))
	row.add_child(load_btn)

	var copy_btn := Button.new()
	copy_btn.text = "COPY"
	copy_btn.add_theme_color_override("font_color", COL_COOL)
	copy_btn.pressed.connect(_on_copy_json.bind(filepath))
	row.add_child(copy_btn)

	var del_btn := Button.new()
	del_btn.text = "DELETE"
	del_btn.add_theme_color_override("font_color", COL_HOT)
	del_btn.pressed.connect(_on_delete_config.bind(filepath))
	row.add_child(del_btn)

	return row


func _on_load_pick(filepath: String) -> void:
	var cfg_mgr = get_node_or_null("/root/WorldConfigManager")
	if cfg_mgr == null:
		return
	var config: Dictionary = cfg_mgr.load_from_file(filepath)
	if config.is_empty():
		_load_status_label.text = "Could not load file. Check console."
		_load_status_label.add_theme_color_override("font_color", COL_HOT)
		return
	# Unpause before reload so the new scene starts fresh.
	get_tree().paused = false
	cfg_mgr.apply_and_restart(config)


func _on_copy_json(filepath: String) -> void:
	if not FileAccess.file_exists(filepath):
		return
	var f := FileAccess.open(filepath, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	DisplayServer.clipboard_set(text)
	_load_status_label.text = "JSON copied to clipboard — paste it anywhere to share."
	_load_status_label.add_theme_color_override("font_color", COL_COOL)


func _on_delete_config(filepath: String) -> void:
	var cfg_mgr = get_node_or_null("/root/WorldConfigManager")
	if cfg_mgr == null:
		return
	if cfg_mgr.delete_config(filepath):
		_load_status_label.text = "Deleted."
		_load_status_label.add_theme_color_override("font_color", COL_DIM)
		_refresh_load_list()
	else:
		_load_status_label.text = "Could not delete file."
		_load_status_label.add_theme_color_override("font_color", COL_HOT)


func _on_paste_import() -> void:
	var cfg_mgr = get_node_or_null("/root/WorldConfigManager")
	if cfg_mgr == null:
		return
	var text := _load_paste_input.text.strip_edges()
	if text == "":
		_load_status_label.text = "Paste a JSON world config first."
		_load_status_label.add_theme_color_override("font_color", COL_HOT)
		return
	var config: Dictionary = cfg_mgr.load_from_string(text)
	if config.is_empty():
		_load_status_label.text = "Invalid config. Check the JSON."
		_load_status_label.add_theme_color_override("font_color", COL_HOT)
		return
	get_tree().paused = false
	cfg_mgr.apply_and_restart(config)


# -------------------------------------------------------------
# Playthrough ready
# -------------------------------------------------------------
func _on_playthrough_ready() -> void:
	_netfeed_title.text = "NETFEED // STANDBY"
	_netfeed_title.add_theme_color_override("font_color", COL_HOT)
	_netfeed_text.text = "[i][color=#%s]> broadcast channel open. awaiting signal...[/color][/i]" % _hex(COL_DIM)


# -------------------------------------------------------------
# Helpers
# -------------------------------------------------------------
func _make_panel(bg: Color) -> Panel:
	var p := _make_panel_raw(bg)
	add_child(p)
	return p


func _make_panel_raw(bg: Color) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = COL_BORDER
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	p.add_theme_stylebox_override("panel", sb)
	return p


func _make_label(text: String, color: Color, size: int, _mono: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	return l


func _hex(c: Color) -> String:
	return c.to_html(false)


func _action_label(action_id: String) -> String:
	match action_id:
		"leak_scandal":
			return "LEAK SCANDAL TO NETFEED"
		"sell_scandal":
			return "SELL SCANDAL TO MEDIA OLIGARCH"
		"assassinate_oligarch":
			return "MARK FOR ASSASSINATION"
	return action_id.to_upper()


func _resolve_politician_name(politician_id: String) -> String:
	if politician_id == "":
		return "unknown"
	for p in WorldDirector.politicians:
		if p.politician_id == politician_id:
			return "%s (%s)" % [p.politician_name, p.faction]
	return politician_id


