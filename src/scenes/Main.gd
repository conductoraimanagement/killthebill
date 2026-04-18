extends Node3D
class_name MainScene

# =============================================================
# Main: the playable root scene.
#
# Responsibilities (in order on _ready):
#   1. Build the greybox environment + lighting + camera + player
#   2. Place interactables (food depot, datashard terminal)
#   3. Build HUD in loading state
#   4. Kick off procedural world generation via WorldDirector
#   5. On playthrough_setup_complete → start the world-cycle timer
#   6. Relay HUD modal picks (leak scandal) → WorldDirector ripples
# =============================================================

const REGION_NAME := "Ash Row"
const REGION_TYPE := "URBAN_SLUM"

# Cadence: one world cycle every N seconds (oligarchs evolve,
# Senate ticks, region dynamics update). Chosen so that the
# player feels the world shift without being overwhelmed.
const CYCLE_SECONDS := 25.0
# Every N cycles, also pull a news cycle (LLM or offline fallback)
# so NetFeed has periodic ambient churn even if the player isn't
# doing anything.
const NEWS_EVERY_N_CYCLES := 3

var _greybox: GreyboxTestScene
var _player: CharacterBody3D
var _camera: CameraController
var _hud: HUD
var _depot: InteractableTarget
var _terminal: DatashardTerminal
var _cycle_timer: Timer


func _ready() -> void:
	_ensure_input_actions()
	WorldDirector.current_region = REGION_NAME

	_setup_environment()
	_setup_lighting()
	_setup_player()
	_setup_camera()
	_setup_depot()
	_setup_terminal()
	_setup_hud()
	_setup_cycle_timer()

	# Bridge HUD modal picks → WorldDirector ripples
	_hud.oligarch_picked.connect(_on_oligarch_picked)

	# Pick up a pending loaded config, if any (set when the user picks one
	# from the Load Modal — WorldConfigManager calls reload_current_scene).
	var preloaded: Dictionary = {}
	var cfg_mgr = get_node_or_null("/root/WorldConfigManager")
	if cfg_mgr and not cfg_mgr.pending_config.is_empty():
		preloaded = cfg_mgr.pending_config
		cfg_mgr.pending_config = {}

	if preloaded.is_empty():
		_hud.show_loading("> generating world…  oligarchs, regions, citizens, senate")
	else:
		_hud.show_loading("> loading saved world: %s" % str(preloaded.get("name", "unknown")))

	if not WorldDirector.playthrough_setup_complete.is_connected(_on_playthrough_ready):
		WorldDirector.playthrough_setup_complete.connect(_on_playthrough_ready)

	WorldDirector.initialize_playthrough(preloaded)

	print("Main scene ready. Region=%s. Click to move. E to interact." % REGION_NAME)


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
# World cycle timer (A)
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


func _on_playthrough_ready() -> void:
	print("Main: playthrough ready. Starting cycle timer.")
	_cycle_timer.start()


# -------------------------------------------------------------
# Environment / lighting
# -------------------------------------------------------------
func _setup_environment() -> void:
	_greybox = GreyboxTestScene.new()
	_greybox.name = "Greybox"
	add_child(_greybox)


func _setup_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 45, 0)
	sun.light_energy = 0.9
	sun.light_color = Color(1.00, 0.92, 0.85)
	sun.shadow_enabled = true
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.04, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.38, 0.45)
	e.ambient_light_energy = 0.45
	e.fog_enabled = true
	e.fog_light_color = Color(0.20, 0.19, 0.22)
	e.fog_density = 0.008
	env.environment = e
	add_child(env)


# -------------------------------------------------------------
# Player / camera
# -------------------------------------------------------------
func _setup_player() -> void:
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

	_player.position = Vector3(0, 1.0, 5)
	add_child(_player)


func _setup_camera() -> void:
	_camera = CameraController.new()
	_camera.name = "Camera"
	add_child(_camera)
	_camera.set_target(_player)


# -------------------------------------------------------------
# Interactables
# -------------------------------------------------------------
func _setup_depot() -> void:
	_depot = InteractableTarget.new()
	_depot.name = "FoodDepot"
	_depot.sector = "Food"
	_depot.depot_name = "%s Food Depot" % REGION_NAME
	add_child(_depot)
	_depot.position = Vector3(10, 0, -8)
	_depot.set_player(_player)

	_depot.became_interactable.connect(_on_depot_interactable)
	_depot.became_non_interactable.connect(_on_target_left)
	_depot.sabotaged_signal.connect(_on_depot_sabotaged)


func _setup_terminal() -> void:
	_terminal = DatashardTerminal.new()
	_terminal.name = "DatashardTerminal"
	_terminal.terminal_name = "black-market terminal"
	add_child(_terminal)
	_terminal.position = Vector3(-10, 0, -6)
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
	# Only useful after generation has produced oligarchs.
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
	_hud.show_oligarch_target_modal("leak_scandal")


func _on_oligarch_picked(oligarch_id: String, action_id: String) -> void:
	print("Main: leaking scandal (action=%s, target=%s)." % [action_id, oligarch_id])
	WorldDirector.trigger_event(action_id, oligarch_id)


# -------------------------------------------------------------
# Input actions
# -------------------------------------------------------------
func _ensure_input_actions() -> void:
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		InputMap.action_add_event("interact", ev)
