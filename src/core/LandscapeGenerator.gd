extends Node3D
class_name LandscapeGenerator

# =============================================================
# LandscapeGenerator: builds a region's 3D space from its data.
#
# Given a region dict (type, name, biome seed, etc.), procedurally
# assembles:
#   - a navmesh-baked ground plane
#   - a street-grid layout with per-type density
#   - multi-storey buildings (stacked boxes) in a per-type palette
#   - emissive ambient props (barrel fires, planters, etc.)
#   - per-biome fog + ambient light
#
# Deterministic: seed = hash(region.name + region.visual_biome).
# Same region → same layout every load, so shared world configs
# reproduce geometry identically across machines.
#
# Emits landscape_ready with:
#   - player_spawn: Vector3 (safe open cell near center)
#   - landmark_spawns: Dict{kind → Vector3} for Main to place
#     interactables on the terrain (food depot, datashard terminal)
# =============================================================

signal landscape_ready(generator)

const METERS_PER_STORY := 3.0
const STREET_EVERY_N := 4     # every 4th grid row/column stays clear for streets

# Per-region-type base config. Biome seed adds variation (see _variant_offset).
const REGION_CONFIGS := {
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

var region: Dictionary = {}
var config: Dictionary = {}
var player_spawn: Vector3 = Vector3.ZERO
var landmark_spawns: Dictionary = {}

var _nav_region: NavigationRegion3D
var _rng: RandomNumberGenerator
var _occupied: Array = []    # 2D array of bool, size [grid_w][grid_h]
var _grid_w: int = 0
var _grid_h: int = 0
var _cell: float = 7.5
var _size: Vector2 = Vector2.ZERO

# Refs kept so day/night interpolation can mutate them at runtime.
var _sun: DirectionalLight3D
var _env: Environment

# Night target colors — blended against config values by day_brightness.
const _NIGHT_SUN_COLOR    := Color(0.30, 0.38, 0.62)
const _NIGHT_AMBIENT      := Color(0.12, 0.14, 0.22)
const _NIGHT_FOG          := Color(0.04, 0.05, 0.09)
const _NIGHT_BG           := Color(0.01, 0.01, 0.03)


func generate(region_data: Dictionary) -> void:
	region = region_data
	var type_key: String = str(region.get("type", "URBAN_SLUM"))
	config = REGION_CONFIGS.get(type_key, REGION_CONFIGS["URBAN_SLUM"]).duplicate(true)
	_apply_biome_variant(str(region.get("visual_biome", "")))

	_rng = RandomNumberGenerator.new()
	_rng.seed = hash(str(region.get("name", "")) + str(region.get("visual_biome", "")))

	_size = config["size"]
	_cell = float(config["cell"])
	_grid_w = int(_size.x / _cell)
	_grid_h = int(_size.y / _cell)

	_occupied.clear()
	for x in range(_grid_w):
		var row: Array = []
		for z in range(_grid_h):
			row.append(false)
		_occupied.append(row)

	_build_nav_region()
	_build_environment()
	_build_ground()
	_place_buildings()
	_place_landmarks()
	_choose_player_spawn()
	_build_ambient()
	_bake_nav()

	landscape_ready.emit(self)


# -------------------------------------------------------------
# Biome variant — lightweight layout/palette nudge from the seed
# -------------------------------------------------------------
func _apply_biome_variant(biome: String) -> void:
	# Nudge density / height / palette so the 6 biomes per region
	# type read as distinct without defining 36 full configs.
	match biome:
		"container_favela":
			config["building_density"] = 0.66
			config["height_range"] = Vector2i(2, 5)
		"tunnel_warren":
			config["height_range"] = Vector2i(1, 3)
			config["building_density"] = 0.72
		"neon_rain":
			config["fog_color"] = Color(0.12, 0.14, 0.22)
			config["accent_color"] = Color(1.0, 0.16, 0.60)
		"concrete_decay":
			config["building_palette"] = [Color(0.30, 0.30, 0.32), Color(0.22, 0.22, 0.25)]
		"glass_spire":
			config["height_range"] = Vector2i(10, 18)
			config["building_density"] = 0.22
		"garden_terrace":
			config["accent_color"] = Color(0.45, 0.85, 0.55)
		"molten_core":
			config["accent_color"] = Color(1.00, 0.25, 0.10)
			config["fog_color"] = Color(0.22, 0.12, 0.08)
		"dome_farm":
			config["building_palette"] = [Color(0.78, 0.92, 0.85), Color(0.55, 0.75, 0.60)]
		"open_steppe":
			config["building_density"] = 0.10
			config["prop_count"] = 40
		"volcanic_bunker":
			config["ground_color"] = Color(0.12, 0.08, 0.08)
		"arctic_retreat":
			config["ground_color"] = Color(0.88, 0.92, 0.97)
			config["fog_color"] = Color(0.88, 0.92, 0.97)
			config["sun_color"] = Color(0.90, 0.95, 1.00)
		"border_wall":
			config["building_density"] = 0.34
			config["accent_color"] = Color(1.00, 0.18, 0.18)
		_:
			pass


# -------------------------------------------------------------
# Nav region + ground
# -------------------------------------------------------------
func _build_nav_region() -> void:
	_nav_region = NavigationRegion3D.new()
	_nav_region.name = "NavigationRegion3D"
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_height = 2.0
	_nav_region.navigation_mesh = nav_mesh
	add_child(_nav_region)


func _build_environment() -> void:
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-55, 45, 0)
	_sun.light_energy = float(config["sun_energy"])
	_sun.light_color = config["sun_color"]
	_sun.shadow_enabled = true
	add_child(_sun)

	var world_env := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = config["fog_color"] * 0.5
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = config["ambient_color"]
	_env.ambient_light_energy = float(config["ambient_energy"])
	_env.fog_enabled = true
	_env.fog_light_color = config["fog_color"]
	_env.fog_density = float(config["fog_density"])
	world_env.environment = _env
	add_child(world_env)


# Called by Main each time TimeSystem.time_of_day_updated fires.
# Blend sun + ambient + fog between the biome's day config and a
# shared night target by TimeSystem.day_brightness (cosine curve).
func on_time_of_day_updated(tod: float) -> void:
	if _sun == null or _env == null:
		return
	var b: float = _compute_brightness(tod)
	var n: float = 1.0 - b  # night weight

	_sun.light_color = (config["sun_color"] as Color).lerp(_NIGHT_SUN_COLOR, n)
	_sun.light_energy = lerp(0.15, float(config["sun_energy"]), b)
	# Sweep the sun from low east (-10°) at dawn through high (-75°) at noon
	# back to low west. At night, drop below horizon so shadow-caster has no effect.
	var pitch: float
	if b > 0.05:
		# Sun arcs through the day. tod 0..0.5 represents 06:00..18:00.
		var arc_t: float = clamp(tod * 2.0, 0.0, 1.0) if tod <= 0.5 else 1.0 - clamp((tod - 0.5) * 2.0, 0.0, 1.0)
		pitch = lerp(-10.0, -75.0, arc_t)
	else:
		pitch = 20.0  # below horizon-ish; shadows read as moonlight
	_sun.rotation_degrees.x = pitch

	_env.ambient_light_color = (config["ambient_color"] as Color).lerp(_NIGHT_AMBIENT, n)
	_env.ambient_light_energy = lerp(0.18, float(config["ambient_energy"]), b)
	_env.fog_light_color = (config["fog_color"] as Color).lerp(_NIGHT_FOG, n)
	_env.background_color = ((config["fog_color"] as Color) * 0.5).lerp(_NIGHT_BG, n)
	# Fog thickens slightly at night — makes it feel heavier.
	var day_fog: float = float(config["fog_density"])
	_env.fog_density = lerp(day_fog * 1.4, day_fog, b)


# TimeSystem.day_brightness duplicated here so LandscapeGenerator
# works even if TimeSystem is absent (e.g. isolated tests).
func _compute_brightness(tod: float) -> float:
	var phase_rad: float = (tod - 0.25) * TAU
	return (cos(phase_rad) + 1.0) * 0.5


func _build_ground() -> void:
	var floor_body := StaticBody3D.new()
	_nav_region.add_child(floor_body)

	var box := BoxMesh.new()
	box.size = Vector3(_size.x, 1.0, _size.y)
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = config["ground_color"]
	mat.roughness = 0.9
	mesh.material_override = mat
	floor_body.add_child(mesh)

	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box.size
	shape.shape = bs
	floor_body.add_child(shape)

	floor_body.position = Vector3(0, -0.5, 0)


# -------------------------------------------------------------
# Buildings
# -------------------------------------------------------------
func _place_buildings() -> void:
	var palette: Array = config["building_palette"]
	var density: float = float(config["building_density"])
	var h_range: Vector2i = config["height_range"]

	# Shared material pool — one StandardMaterial3D per palette color, reused.
	var materials: Array = []
	for c in palette:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.85
		materials.append(m)

	for gx in range(_grid_w):
		for gz in range(_grid_h):
			# Streets: clear rows/cols every N to keep paths open
			if gx % STREET_EVERY_N == 0 or gz % STREET_EVERY_N == 0:
				continue
			if _rng.randf() > density:
				continue
			_occupied[gx][gz] = true
			_spawn_building(gx, gz, h_range, materials)


func _spawn_building(gx: int, gz: int, h_range: Vector2i, materials: Array) -> void:
	var pos := _cell_center(gx, gz)
	# Slightly jitter within the cell to break grid uniformity
	var jitter := Vector3(
		_rng.randf_range(-_cell * 0.12, _cell * 0.12),
		0,
		_rng.randf_range(-_cell * 0.12, _cell * 0.12)
	)
	var building_pos := pos + jitter

	var stories: int = _rng.randi_range(h_range.x, h_range.y)
	var total_height: float = stories * METERS_PER_STORY
	var body := StaticBody3D.new()
	_nav_region.add_child(body)

	# Lower wide base
	var base_w: float = _cell * _rng.randf_range(0.55, 0.82)
	var base_h: float = total_height * _rng.randf_range(0.55, 0.95)
	var base_box := BoxMesh.new()
	base_box.size = Vector3(base_w, base_h, base_w)
	var base_mesh := MeshInstance3D.new()
	base_mesh.mesh = base_box
	base_mesh.material_override = materials[_rng.randi() % materials.size()]
	base_mesh.position = Vector3(0, base_h / 2.0, 0)
	body.add_child(base_mesh)

	var base_shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = base_box.size
	base_shape.shape = bs
	base_shape.position = base_mesh.position
	body.add_child(base_shape)

	# Optional narrower upper stack for multi-storey feel
	if total_height - base_h > 2.0 and _rng.randf() < 0.7:
		var upper_h: float = total_height - base_h
		var upper_w: float = base_w * _rng.randf_range(0.55, 0.85)
		var upper_box := BoxMesh.new()
		upper_box.size = Vector3(upper_w, upper_h, upper_w)
		var upper_mesh := MeshInstance3D.new()
		upper_mesh.mesh = upper_box
		upper_mesh.material_override = materials[_rng.randi() % materials.size()]
		upper_mesh.position = Vector3(0, base_h + upper_h / 2.0, 0)
		body.add_child(upper_mesh)

		var upper_shape := CollisionShape3D.new()
		var us := BoxShape3D.new()
		us.size = upper_box.size
		upper_shape.shape = us
		upper_shape.position = upper_mesh.position
		body.add_child(upper_shape)

	body.position = building_pos


# -------------------------------------------------------------
# Landmark spawns (reserve two empty cells for the interactables)
# -------------------------------------------------------------
func _place_landmarks() -> void:
	landmark_spawns = {}
	var kinds: Array = ["food_depot", "datashard_terminal"]
	for kind in kinds:
		var pos: Vector3 = _reserve_empty_cell()
		landmark_spawns[kind] = pos


func _reserve_empty_cell() -> Vector3:
	# Prefer cells in the outer ring so the player has room in the middle.
	for _try in range(200):
		var gx: int = _rng.randi_range(1, _grid_w - 2)
		var gz: int = _rng.randi_range(1, _grid_h - 2)
		if _occupied[gx][gz]:
			continue
		if gx % STREET_EVERY_N == 0 or gz % STREET_EVERY_N == 0:
			# Streets are valid spawn locations (open)
			_occupied[gx][gz] = true
			return _cell_center(gx, gz)
		# Empty non-street cell
		_occupied[gx][gz] = true
		return _cell_center(gx, gz)
	return Vector3.ZERO


# -------------------------------------------------------------
# Player spawn — pick an empty cell near the center
# -------------------------------------------------------------
func _choose_player_spawn() -> void:
	var mid_x: int = _grid_w / 2
	var mid_z: int = _grid_h / 2
	# Radiating search outward from center
	for radius in range(0, max(_grid_w, _grid_h) / 2):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				var gx: int = mid_x + dx
				var gz: int = mid_z + dz
				if gx < 0 or gx >= _grid_w or gz < 0 or gz >= _grid_h:
					continue
				if not _occupied[gx][gz]:
					_occupied[gx][gz] = true
					player_spawn = _cell_center(gx, gz) + Vector3(0, 1.0, 0)
					return
	player_spawn = Vector3(0, 1.0, 0)


# -------------------------------------------------------------
# Ambient props — biome-specific scatter
# -------------------------------------------------------------
func _build_ambient() -> void:
	var kind: String = str(config.get("prop_kind", ""))
	var count: int = int(config.get("prop_count", 0))
	var accent: Color = config["accent_color"]

	for _i in range(count):
		var gx: int = _rng.randi_range(0, _grid_w - 1)
		var gz: int = _rng.randi_range(0, _grid_h - 1)
		if _occupied[gx][gz]:
			continue
		var pos := _cell_center(gx, gz)
		pos.x += _rng.randf_range(-_cell * 0.3, _cell * 0.3)
		pos.z += _rng.randf_range(-_cell * 0.3, _cell * 0.3)
		_spawn_prop(kind, pos, accent)


func _spawn_prop(kind: String, pos: Vector3, accent: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = accent
	mat.emission_enabled = true
	mat.emission = accent
	mat.emission_energy_multiplier = 0.8

	var mesh_inst := MeshInstance3D.new()
	match kind:
		"barrel_fire":
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.35
			cyl.bottom_radius = 0.35
			cyl.height = 0.8
			mesh_inst.mesh = cyl
			mesh_inst.position = pos + Vector3(0, 0.4, 0)
		"planter":
			var box := BoxMesh.new()
			box.size = Vector3(1.2, 0.5, 1.2)
			mesh_inst.mesh = box
			mat.emission_energy_multiplier = 0.25
			mesh_inst.position = pos + Vector3(0, 0.25, 0)
		"smoke_stack":
			var cyl2 := CylinderMesh.new()
			cyl2.top_radius = 0.7
			cyl2.bottom_radius = 1.0
			cyl2.height = 14.0
			mesh_inst.mesh = cyl2
			mat.emission_energy_multiplier = 0.15
			mesh_inst.position = pos + Vector3(0, 7.0, 0)
		"grow_lamp":
			var box2 := BoxMesh.new()
			box2.size = Vector3(0.4, 4.0, 0.4)
			mesh_inst.mesh = box2
			mesh_inst.position = pos + Vector3(0, 2.0, 0)
		"palm":
			var cyl3 := CylinderMesh.new()
			cyl3.top_radius = 0.18
			cyl3.bottom_radius = 0.24
			cyl3.height = 4.5
			mesh_inst.mesh = cyl3
			mat.emission_enabled = false
			mat.albedo_color = Color(0.30, 0.22, 0.12)
			mesh_inst.position = pos + Vector3(0, 2.25, 0)
		"warning_beacon":
			var sph := SphereMesh.new()
			sph.radius = 0.3
			sph.height = 0.6
			mesh_inst.mesh = sph
			mat.emission_energy_multiplier = 1.2
			mesh_inst.position = pos + Vector3(0, 3.0, 0)
		_:
			return
	mesh_inst.material_override = mat
	add_child(mesh_inst)


# -------------------------------------------------------------
# Utilities
# -------------------------------------------------------------
func _cell_center(gx: int, gz: int) -> Vector3:
	var x: float = (gx + 0.5) * _cell - _size.x / 2.0
	var z: float = (gz + 0.5) * _cell - _size.y / 2.0
	return Vector3(x, 0, z)


func _bake_nav() -> void:
	_nav_region.bake_navigation_mesh(false)
