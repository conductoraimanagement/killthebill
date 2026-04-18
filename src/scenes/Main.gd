extends Node3D
class_name MainScene

# =============================================================
# Main: the playable root scene.
#
# Responsibilities:
#   1. Build the HUD in loading state
#   2. Pick up a pending loaded world config, if any
#   3. Kick off WorldDirector.initialize_playthrough()
#   4. When setup completes, spawn the LandscapeGenerator for the
#      current region
#   5. When the landscape reports ready, spawn the player + camera
#      + interactables at its landmark positions, start the world
#      cycle timer
#   6. Route HUD modal picks (leak scandal) → WorldDirector ripples
# =============================================================

const CYCLE_SECONDS := 25.0
const NEWS_EVERY_N_CYCLES := 3

var _landscape: LandscapeGenerator
var _player: CharacterBody3D
var _camera: CameraController
var _hud: HUD
var _depot: InteractableTarget
var _terminal: DatashardTerminal
var _cycle_timer: Timer


func _ready() -> void:
	_ensure_input_actions()
	_setup_hud()
	_setup_cycle_timer()

	_hud.oligarch_picked.connect(_on_oligarch_picked)
	_hud.politician_bribed.connect(_on_politician_bribed)

	# Pending loaded config, if any
	var preloaded: Dictionary = {}
	var cfg_mgr = get_node_or_null("/root/WorldConfigManager")
	if cfg_mgr and not cfg_mgr.pending_config.is_empty():
		preloaded = cfg_mgr.pending_config
		cfg_mgr.pending_config = {}

	if preloaded.is_empty():
		_hud.show_loading("> generating world…  regions, oligarchs, senate, citizens")
	else:
		_hud.show_loading("> loading saved world: %s" % str(preloaded.get("name", "unknown")))

	if not WorldDirector.playthrough_setup_complete.is_connected(_on_playthrough_ready):
		WorldDirector.playthrough_setup_complete.connect(_on_playthrough_ready)

	WorldDirector.initialize_playthrough(preloaded)
	print("Main scene ready. Click to move once the landscape finishes generating. E to interact. P for Senate roster. F5 to save. F9 to load.")


# -------------------------------------------------------------
# Input — click-to-move raycast onto navmesh
# -------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_ground_click(event.position)


func _handle_ground_click(screen_pos: Vector2) -> void:
	if _camera == null or _player == null:
		return
	var from: Vector3 = _camera.project_ray_origin(screen_pos)
	var to: Vector3 = from + _camera.project_ray_normal(screen_pos) * 500.0
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.has("position"):
		_player.set_movement_target(hit.position)


# -------------------------------------------------------------
# World cycle timer
# -------------------------------------------------------------
func _setup_cycle_timer() -> void:
	_cycle_timer = Timer.new()
	_cycle_timer.wait_time = CYCLE_SECONDS
	_cycle_timer.one_shot = false
	_cycle_timer.autostart = false
	_cycle_timer.timeout.connect(_on_cycle_tick)
	add_child(_cycle_timer)


func _on_cycle_tick() -> void:
	WorldDirector.run_world_cycle()
	if WorldDirector.cycle % NEWS_EVERY_N_CYCLES == 0:
		WorldDirector.trigger_news_cycle()


# -------------------------------------------------------------
# Playthrough → landscape → spawn player
# -------------------------------------------------------------
func _on_playthrough_ready() -> void:
	var region_data: Dictionary = _current_region_data()
	if region_data.is_empty():
		push_error("Main: no current region data; falling back to URBAN_SLUM stub")
		region_data = {"name": "Ash Row", "type": "URBAN_SLUM", "visual_biome": "brutalist_fog"}

	_landscape = LandscapeGenerator.new()
	_landscape.name = "Landscape"
	add_child(_landscape)
	_landscape.landscape_ready.connect(_on_landscape_ready)
	_landscape.generate(region_data)


func _current_region_data() -> Dictionary:
	var region_gen = get_node_or_null("/root/RegionGenerator")
	if region_gen == null:
		return {}
	# Prefer the explicit starting_region; fall back to first unlocked.
	if region_gen.starting_region != "":
		return region_gen.get_region_by_name(region_gen.starting_region)
	var unlocked: Array = region_gen.get_unlocked_regions()
	if unlocked.size() > 0:
		return unlocked[0]
	return {}


func _on_landscape_ready(landscape: LandscapeGenerator) -> void:
	var spawn: Vector3 = landscape.player_spawn
	var depot_pos: Vector3 = landscape.landmark_spawns.get("food_depot", Vector3(10, 0, -8))
	var terminal_pos: Vector3 = landscape.landmark_spawns.get("datashard_terminal", Vector3(-10, 0, -6))
	# Lift landmarks slightly so they sit on the ground.
	depot_pos.y = 0
	terminal_pos.y = 0

	_spawn_player(spawn)
	_setup_camera()
	_spawn_depot(depot_pos, landscape.region)
	_spawn_terminal(terminal_pos)

	_cycle_timer.start()
	print("Main: landscape ready for '%s' (type=%s, biome=%s). Cycle timer started." % [
		str(landscape.region.get("name", "?")),
		str(landscape.region.get("type", "?")),
		str(landscape.region.get("visual_biome", "?")),
	])


# -------------------------------------------------------------
# Player / camera
# -------------------------------------------------------------
func _spawn_player(at: Vector3) -> void:
	_player = CharacterBody3D.new()
	_player.name = "Player"
	_player.set_script(load("res://src/entities/PlayerController.gd"))

	var nav := NavigationAgent3D.new()
	nav.name = "NavigationAgent3D"
	_player.add_child(nav)

	var col := CollisionShape3D.new()
	var caps := CapsuleShape3D.new()
	caps.radius = 0.4
	caps.height = 1.6
	col.shape = caps
	_player.add_child(col)

	var mesh_inst := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.4
	mesh.height = 1.6
	mesh_inst.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.00, 0.34, 0.13)
	mat.emission_enabled = true
	mat.emission = Color(1.00, 0.34, 0.13)
	mat.emission_energy_multiplier = 0.25
	mesh_inst.material_override = mat
	_player.add_child(mesh_inst)

	# Facing indicator
	var nose := MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.15, 0.15, 0.5)
	nose.mesh = nose_mesh
	nose.position = Vector3(0, 0.2, -0.5)
	nose.material_override = mat
	_player.add_child(nose)

	_player.position = at
	add_child(_player)


func _setup_camera() -> void:
	_camera = CameraController.new()
	_camera.name = "Camera"
	add_child(_camera)
	_camera.set_target(_player)


# -------------------------------------------------------------
# Interactables
# -------------------------------------------------------------
func _spawn_depot(at: Vector3, region_data: Dictionary) -> void:
	_depot = InteractableTarget.new()
	_depot.name = "FoodDepot"
	_depot.sector = "Food"
	var region_name: String = str(region_data.get("name", "Region"))
	_depot.depot_name = "%s Food Depot" % region_name
	add_child(_depot)
	_depot.position = at
	_depot.set_player(_player)
	_depot.became_interactable.connect(_on_depot_interactable)
	_depot.became_non_interactable.connect(_on_target_left)
	_depot.sabotaged_signal.connect(_on_depot_sabotaged)


func _spawn_terminal(at: Vector3) -> void:
	_terminal = DatashardTerminal.new()
	_terminal.name = "DatashardTerminal"
	_terminal.terminal_name = "black-market terminal"
	add_child(_terminal)
	_terminal.position = at
	_terminal.set_player(_player)
	_terminal.became_interactable.connect(_on_terminal_interactable)
	_terminal.became_non_interactable.connect(_on_target_left)
	_terminal.requested_oligarch_pick.connect(_on_terminal_activated)


func _setup_hud() -> void:
	_hud = HUD.new()
	add_child(_hud)


# -------------------------------------------------------------
# Interactable glue
# -------------------------------------------------------------
func _on_depot_interactable(target: InteractableTarget) -> void:
	_hud.show_prompt(target.prompt_text())


func _on_terminal_interactable(term: DatashardTerminal) -> void:
	if WorldDirector.get_living_oligarchs().is_empty():
		_hud.show_prompt("[E] %s — no targets yet" % term.terminal_name)
	else:
		_hud.show_prompt(term.prompt_text())


func _on_target_left(_target) -> void:
	_hud.hide_prompt()


func _on_depot_sabotaged(target: InteractableTarget) -> void:
	print("Main: depot '%s' sabotaged — economy ripples applied." % target.depot_name)


func _on_terminal_activated(_terminal_node: DatashardTerminal) -> void:
	_hud.hide_prompt()
	_hud.show_terminal_menu()


func _on_oligarch_picked(oligarch_id: String, action_id: String) -> void:
	print("Main: oligarch action (action=%s, target=%s)." % [action_id, oligarch_id])
	WorldDirector.trigger_event(action_id, oligarch_id)


func _on_politician_bribed(politician_id: String, direction: String) -> void:
	print("Main: bribe politician (id=%s, dir=%s)." % [politician_id, direction])
	WorldDirector.trigger_event("bribe_politician", "%s|%s" % [politician_id, direction])


# -------------------------------------------------------------
# Input actions
# -------------------------------------------------------------
func _ensure_input_actions() -> void:
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		InputMap.action_add_event("interact", ev)
