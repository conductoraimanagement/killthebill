class_name RegionConfig

# =============================================================
# RegionConfig: per-region-type generation parameters + landmark
# recipes. Pure data. LandscapeGenerator reads RegionConfig.BASES
# on every generate() call to size the grid, pick palettes, choose
# prop kinds; it reads RegionConfig.LANDMARK_RECIPES to decide
# which InteractableTarget kinds to spawn in each region type.
#
# Biome seed adds further variation on top (see
# LandscapeGenerator._variant_offset).
#
# Entry schema (BASES per region type):
#   size               — Vector2(width, depth) in meters
#   cell               — grid cell size
#   building_density   — 0..1 fraction of cells that get a building
#   height_range       — Vector2i(min, max) story count
#   ground_color       — Color
#   building_palette   — Array[Color]
#   accent_color       — emissive accents + enforcer strap
#   fog_color          — Color
#   fog_density        — float
#   ambient_color      — Color
#   ambient_energy     — float
#   sun_energy         — float
#   sun_color          — Color
#   prop_kind          — ambient prop (barrel_fire, planter, etc.)
#   prop_count         — how many to scatter
# =============================================================

const BASES = {
	"URBAN_SLUM": {
		"size":            Vector2(160, 160),
		"cell":            7.5,
		"building_density": 0.58,
		"height_range":    Vector2i(2, 6),
		"ground_color":    Color(0.10, 0.09, 0.09),
		"building_palette": [
			Color(0.45, 0.25, 0.15),
			Color(0.30, 0.18, 0.14),
			Color(0.25, 0.25, 0.30),
			Color(0.38, 0.32, 0.28),
		],
		"accent_color":    Color(1.00, 0.40, 0.10),
		"fog_color":       Color(0.18, 0.13, 0.10),
		"fog_density":     0.015,
		"ambient_color":   Color(0.35, 0.32, 0.38),
		"ambient_energy":  0.40,
		"sun_energy":      0.65,
		"sun_color":       Color(1.00, 0.78, 0.55),
		"prop_kind":       "barrel_fire",
		"prop_count":      18,
	},
	"URBAN_ELITE": {
		"size":            Vector2(150, 150),
		"cell":            10.0,
		"building_density": 0.28,
		"height_range":    Vector2i(7, 14),
		"ground_color":    Color(0.82, 0.84, 0.88),
		"building_palette": [
			Color(0.14, 0.18, 0.28),
			Color(0.88, 0.90, 0.95),
			Color(0.55, 0.60, 0.68),
		],
		"accent_color":    Color(0.30, 0.79, 0.79),
		"fog_color":       Color(0.78, 0.84, 0.92),
		"fog_density":     0.003,
		"ambient_color":   Color(0.80, 0.85, 0.95),
		"ambient_energy":  0.85,
		"sun_energy":      1.10,
		"sun_color":       Color(1.00, 0.97, 0.92),
		"prop_kind":       "planter",
		"prop_count":      22,
	},
	"INDUSTRIAL": {
		"size":            Vector2(170, 170),
		"cell":            10.0,
		"building_density": 0.42,
		"height_range":    Vector2i(2, 7),
		"ground_color":    Color(0.12, 0.10, 0.08),
		"building_palette": [
			Color(0.40, 0.20, 0.10),
			Color(0.25, 0.25, 0.28),
			Color(0.16, 0.14, 0.12),
			Color(0.35, 0.30, 0.22),
		],
		"accent_color":    Color(1.00, 0.65, 0.15),
		"fog_color":       Color(0.20, 0.16, 0.12),
		"fog_density":     0.017,
		"ambient_color":   Color(0.50, 0.38, 0.22),
		"ambient_energy":  0.55,
		"sun_energy":      0.70,
		"sun_color":       Color(1.00, 0.72, 0.40),
		"prop_kind":       "smoke_stack",
		"prop_count":      8,
	},
	"AGRICULTURAL": {
		"size":            Vector2(180, 180),
		"cell":            9.0,
		"building_density": 0.22,
		"height_range":    Vector2i(1, 3),
		"ground_color":    Color(0.16, 0.14, 0.09),
		"building_palette": [
			Color(0.78, 0.82, 0.78),
			Color(0.42, 0.32, 0.20),
			Color(0.55, 0.55, 0.50),
		],
		"accent_color":    Color(0.35, 0.85, 0.45),
		"fog_color":       Color(0.24, 0.26, 0.18),
		"fog_density":     0.006,
		"ambient_color":   Color(0.55, 0.70, 0.50),
		"ambient_energy":  0.60,
		"sun_energy":      0.90,
		"sun_color":       Color(0.90, 1.00, 0.85),
		"prop_kind":       "grow_lamp",
		"prop_count":      28,
	},
	"ISLAND_RETREAT": {
		"size":            Vector2(110, 110),
		"cell":            9.0,
		"building_density": 0.14,
		"height_range":    Vector2i(2, 5),
		"ground_color":    Color(0.78, 0.70, 0.50),
		"building_palette": [
			Color(0.92, 0.90, 0.85),
			Color(0.70, 0.68, 0.62),
		],
		"accent_color":    Color(0.30, 0.78, 0.92),
		"fog_color":       Color(0.82, 0.88, 0.94),
		"fog_density":     0.002,
		"ambient_color":   Color(0.85, 0.92, 1.00),
		"ambient_energy":  1.00,
		"sun_energy":      1.20,
		"sun_color":       Color(1.00, 0.98, 0.88),
		"prop_kind":       "palm",
		"prop_count":      14,
	},
	"TRANSIT": {
		"size":            Vector2(200, 100),
		"cell":            8.0,
		"building_density": 0.24,
		"height_range":    Vector2i(2, 4),
		"ground_color":    Color(0.12, 0.12, 0.14),
		"building_palette": [
			Color(0.42, 0.42, 0.46),
			Color(0.56, 0.22, 0.22),
			Color(0.28, 0.28, 0.30),
		],
		"accent_color":    Color(1.00, 0.72, 0.18),
		"fog_color":       Color(0.20, 0.20, 0.22),
		"fog_density":     0.009,
		"ambient_color":   Color(0.50, 0.48, 0.44),
		"ambient_energy":  0.55,
		"sun_energy":      0.85,
		"sun_color":       Color(1.00, 0.90, 0.75),
		"prop_kind":       "warning_beacon",
		"prop_count":      10,
	},
}


# Per region-type landmark recipe. Determines which InteractableTarget
# kinds spawn here. Every type lists 1-3 sabotage targets whose sector
# is thematically appropriate.
const LANDMARK_RECIPES: Dictionary = {
	"URBAN_SLUM":     ["food_depot"],
	"URBAN_ELITE":    ["financial_center", "media_spire", "clearing_house", "training_cluster"],
	"INDUSTRIAL":     ["refinery", "power_relay"],
	"AGRICULTURAL":   ["hydro_vault", "grain_silo"],
	"ISLAND_RETREAT": ["private_dock"],
	"TRANSIT":        ["checkpoint_scanner"],
}
