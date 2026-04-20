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


# Run-start modal — explains the win conditions. The player no longer
# picks one; which condition fires is determined by their actions
# across the year. See docs/04-player/victory.md.
const WIN_CONDITIONS: Array[Dictionary] = [
	{
		"label": "DIRECT ACTION",
		"flavor": "Kill the oligarchs. The rarest, loudest path.",
		"color_key": "HOT",
	},
	{
		"label": "POLITICAL REVOLUTION",
		"flavor": "Push public_tension to 100. The masses storm.",
		"color_key": "ACCENT",
	},
	{
		"label": "POLITICAL REFORM",
		"flavor": "Drive senate_alignment to 0. Bribe, leak, organize.",
		"color_key": "COOL",
	},
	{
		"label": "SYSTEMIC COLLAPSE",
		"flavor": "Grind combined oligarch wealth below survival. The grind path.",
		"color_key": "WARN",
	},
]

# Main defeat surfaces. Shown in the run-start modal so players know
# what's at stake alongside the wins.
const DEFEAT_CONDITIONS: Array[Dictionary] = [
	{
		"label": "ARRESTED",
		"flavor": "Heat reaches 100. Enforcers find you at dawn.",
		"color_key": "HOT",
	},
	{
		"label": "DESPAIR",
		"flavor": "Hope drifts to 0. You stop leaving the apartment.",
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
