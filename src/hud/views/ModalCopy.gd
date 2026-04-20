class_name ModalCopy

# =============================================================
# ModalCopy: static copy + option catalogs for HUD modals.
#
# Modals that present a fixed menu of choices (not generated per
# run) keep their option lists here. HUD owns the Button widgets,
# signal wiring, and lifecycle; ModalCopy holds the text.
#
# The `color_key` field refers to HudTheme.COL_* constants — the
# consuming HUD code resolves the actual Color from the key. This
# keeps ModalCopy free of Godot-type imports.
# =============================================================


# Goal-choice modal — shown at run start. Five victory paths.
# See docs/04-player/victory.md for the mechanics each triggers.
const GOAL_OPTIONS: Array[Dictionary] = [
	{
		"path": "DIRECT_ACTION",
		"label": "DIRECT ACTION",
		"flavor": "Kill the oligarchs. The rarest, loudest path.",
		"color_key": "HOT",
	},
	{
		"path": "POLITICAL_REVOLUTION",
		"label": "POLITICAL REVOLUTION",
		"flavor": "Push public_tension to 100. The masses storm.",
		"color_key": "ACCENT",
	},
	{
		"path": "POLITICAL_REFORM",
		"label": "POLITICAL REFORM",
		"flavor": "Drive senate_alignment to 0. Bribe, leak, organize.",
		"color_key": "COOL",
	},
	{
		"path": "SYSTEMIC_COLLAPSE",
		"label": "SYSTEMIC COLLAPSE",
		"flavor": "Grind combined oligarch wealth below survival. The grind path.",
		"color_key": "WARN",
	},
	{
		"path": "ANY",
		"label": "LET THE YEAR DECIDE",
		"flavor": "Any condition wins. Less committed, less narrative.",
		"color_key": "DIM",
	},
]


static func resolve_color(color_key: String) -> Color:
	match color_key:
		"BG":       return HudTheme.COL_BG
		"BG_MODAL": return HudTheme.COL_BG_MODAL
		"FG":       return HudTheme.COL_FG
		"DIM":      return HudTheme.COL_DIM
		"BORDER":   return HudTheme.COL_BORDER
		"ACCENT":   return HudTheme.COL_ACCENT
		"HOT":      return HudTheme.COL_HOT
		"COOL":     return HudTheme.COL_COOL
		"WARN":     return HudTheme.COL_WARN
	return HudTheme.COL_FG
