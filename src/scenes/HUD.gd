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


func _ready() -> void:
	layer = 10
	_build_state_panel()
	_build_netfeed_panel()
	_build_senate_panel()
	_build_politicians_panel()
	_build_prompt_panel()
	_build_modal()
	_build_victory_modal()

	WorldDirector.world_state_changed.connect(_refresh_state)
	WorldDirector.netfeed_event_generated.connect(_on_netfeed_event)
	WorldDirector.playthrough_setup_complete.connect(_on_playthrough_ready)
	WorldDirector.victory_achieved.connect(_on_victory)

	# Senate hooks (autoload-safe)
	var senate = get_node_or_null("/root/SenateDirector")
	if senate:
		senate.bill_proposed.connect(_on_bill_proposed)
		senate.bill_resolved.connect(_on_bill_resolved)

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
	_state_panel.offset_bottom = 220

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
	lines.append("[color=#%s]cycle[/color]           [color=#%s]%d[/color]  [color=#%s]%s[/color]" % [
		_hex(COL_DIM),
		_hex(COL_COOL),
		WorldDirector.cycle,
		_hex(COL_DIM),
		"// ticking every 25s",
	])
	_state_text.text = "\n".join(lines)


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
	_active_bill = bill
	_last_vote_record = []
	var sponsor_id: String = str(bill.get("sponsor_id", ""))
	var sponsor_name := _resolve_politician_name(sponsor_id)
	var title: String = str(bill.get("title", "Untitled Bill"))
	var rationale: String = str(bill.get("stated_rationale", ""))
	var summary: String = str(bill.get("summary", ""))

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
	_senate_text.text = "\n".join(lines)

	if _pol_visible:
		_refresh_politicians()


func _on_bill_resolved(bill: Dictionary, result: String, vote_record: Array) -> void:
	_last_vote_record = vote_record
	_active_bill = {}

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
	_pol_panel.offset_top = 240
	_pol_panel.offset_right = 440
	_pol_panel.offset_bottom = 580
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

	# Victory modal swallows everything
	if _victory_root and _victory_root.visible:
		return

	# Oligarch-target modal: ESC closes it; otherwise fall through to nothing
	if _modal_root and _modal_root.visible:
		if event.keycode == KEY_ESCAPE:
			hide_modal()
			get_viewport().set_input_as_handled()
		return

	# P toggles the politicians roster
	if event.keycode == KEY_P:
		_toggle_politicians()
		get_viewport().set_input_as_handled()


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

	# Top banner — VICTORY
	var banner := _make_label("// VICTORY //", COL_ACCENT, 14, true)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.anchor_left = 0.0
	banner.anchor_top = 0.0
	banner.anchor_right = 1.0
	banner.offset_left = PANEL_PAD
	banner.offset_top = PANEL_PAD + 4
	banner.offset_right = -PANEL_PAD
	banner.offset_bottom = PANEL_PAD + 28
	panel.add_child(banner)

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

	# Buttons
	var restart := Button.new()
	restart.text = "RESTART PLAYTHROUGH"
	restart.anchor_left = 0.5
	restart.anchor_top = 1.0
	restart.anchor_right = 0.5
	restart.anchor_bottom = 1.0
	restart.offset_left = -200
	restart.offset_top = -64
	restart.offset_right = -20
	restart.offset_bottom = -20
	restart.add_theme_color_override("font_color", COL_ACCENT)
	restart.add_theme_color_override("font_hover_color", COL_FG)
	restart.pressed.connect(_restart_playthrough)
	panel.add_child(restart)

	var continue_btn := Button.new()
	continue_btn.text = "CONTINUE (sandbox)"
	continue_btn.anchor_left = 0.5
	continue_btn.anchor_top = 1.0
	continue_btn.anchor_right = 0.5
	continue_btn.anchor_bottom = 1.0
	continue_btn.offset_left = 20
	continue_btn.offset_top = -64
	continue_btn.offset_right = 200
	continue_btn.offset_bottom = -20
	continue_btn.add_theme_color_override("font_color", COL_DIM)
	continue_btn.add_theme_color_override("font_hover_color", COL_FG)
	continue_btn.pressed.connect(_dismiss_victory)
	panel.add_child(continue_btn)


func _on_victory(kind: String, title: String, flavor: String) -> void:
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


