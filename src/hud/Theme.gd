class_name HudTheme

# =============================================================
# HudTheme: shared UI constants and style helpers.
#
# Single source of truth for the HUD's palette and panel chrome.
# Panels and modals extracted out of HUD.gd reference these
# constants directly, keeping every surface visually consistent
# without each module redefining colors.
#
# Helpers are `static` — no instance state, call from anywhere.
# HUD.gd still exposes thin _hex / _make_panel / _make_label
# wrappers that delegate here, so existing HUD code doesn't
# need a rename pass. New code should prefer HudTheme.foo()
# directly.
# =============================================================

# --- palette ---
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


static func make_panel_raw(bg: Color) -> Panel:
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


# Build + attach to a parent in one call. Useful inside a panel/modal
# script where `self` is the owning Control.
static func make_panel(parent: Node, bg: Color) -> Panel:
	var p := make_panel_raw(bg)
	parent.add_child(p)
	return p


static func make_label(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	return l


static func hex(c: Color) -> String:
	return c.to_html(false)
