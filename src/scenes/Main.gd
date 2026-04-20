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

var _landscape: LandscapeGenerator
var _player: CharacterBody3D
var _camera: CameraController
var _hud: HUD
var _sabotage_targets: Array = []   # list of InteractableTarget spawned by the landscape
var _terminal: DatashardTerminal


# Public accessor for autoloads (PlayerManager.compute_heat_cost needs
# the active landscape for witness-count sampling). Returns null while
# regions are being regenerated between travels.
func get_active_landscape() -> LandscapeGenerator:
	return _landscape


func _ready() -> void:
	_ensure_input_actions()
	_setup_hud()

	_hud.oligarch_picked.connect(_on_oligarch_picked)
	_hud.politician_bribed.connect(_on_politician_bribed)
	_hud.travel_requested.connect(_on_travel_requested)
	_hud.crowd_pickpocket_requested.connect(pickpocket_crowd)
	_hud.enforcer_flee_failed.connect(_on_enforcer_flee_failed)

	# Pending loaded config, if any
	var preloaded: Dictionary = {}
	var cfg_mgr = get_node_or_null("/root/WorldConfigManager")
	if cfg_mgr and not cfg_mgr.pending_config.is_empty():
		preloaded = cfg_mgr.pending_config
		cfg_mgr.pending_config = {}

	if preloaded.is_empty():
		_hud.show_loading("> generating world…  regions, oligarchs, senate, citizens")
		# Offer the 13-month goal choice while the world generates behind it.
		_hud.show_goal_choice_modal()
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
# Time now flows from TimeSystem (autoload). Days advance on their
# own cadence; WorldDirector subscribes to day_advanced and
# phase_changed inside _finish_setup. No local Timer needed.
# -------------------------------------------------------------


# -------------------------------------------------------------
# Playthrough → landscape → spawn player
# -------------------------------------------------------------
func _on_playthrough_ready() -> void:
	# Starting the clock is handled inside WorldDirector._finish_setup
	# (via TimeSystem.start()). Nothing extra here beyond building the
	# 3D landscape for the current region.
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
	var terminal_pos: Vector3 = landscape.landmark_spawns.get("datashard_terminal", Vector3(-10, 0, -6))
	terminal_pos.y = 0

	_spawn_player(spawn)
	_setup_camera()
	_spawn_terminal(terminal_pos)

	# Sabotage targets are spawned by the landscape itself — we just wire
	# interaction signals for each. Clear old refs from any previous region.
	_sabotage_targets.clear()
	if not landscape.sabotage_target_spawned.is_connected(_on_sabotage_target_spawned):
		landscape.sabotage_target_spawned.connect(_on_sabotage_target_spawned)
	for t in landscape.sabotage_targets:
		_on_sabotage_target_spawned(t)

	# Landscape now listens to TimeSystem for day/night blending.
	if has_node("/root/TimeSystem"):
		var ts = get_node("/root/TimeSystem")
		if not ts.time_of_day_updated.is_connected(landscape.on_time_of_day_updated):
			ts.time_of_day_updated.connect(landscape.on_time_of_day_updated)
		# Apply current time immediately so the first frame isn't full-noon.
		landscape.on_time_of_day_updated(ts.time_of_day)

	# Wire Enforcer patrols — each spawned patrol gets the player ref so it
	# can run proximity detection, and its encountered_player signal goes to
	# the HUD encounter modal.
	if not landscape.patrol_spawned.is_connected(_on_patrol_spawned):
		landscape.patrol_spawned.connect(_on_patrol_spawned)
	for p in landscape.enforcer_patrols:
		_on_patrol_spawned(p)

	# Mid-phase patrol respawn when heat crosses a threshold.
	var pm = get_node_or_null("/root/PlayerManager")
	if pm and not pm.heat_changed.is_connected(landscape.on_heat_changed):
		pm.heat_changed.connect(landscape.on_heat_changed)

	# Wire ambient crowd NPCs — proximity prompt + pickpocket resolution.
	if not landscape.crowd_spawned.is_connected(_on_crowd_spawned):
		landscape.crowd_spawned.connect(_on_crowd_spawned)
	for c in landscape.crowd_npcs:
		_on_crowd_spawned(c)

	# Wire the transit zone — proximity prompt + open travel modal.
	if landscape.transit_zone:
		landscape.transit_zone.set_player(_player)
		if not landscape.transit_zone.became_interactable.is_connected(_on_transit_interactable):
			landscape.transit_zone.became_interactable.connect(_on_transit_interactable)
		if not landscape.transit_zone.became_non_interactable.is_connected(_on_target_left):
			landscape.transit_zone.became_non_interactable.connect(_on_target_left)
	if not landscape.transit_zone_activated.is_connected(_on_transit_zone_activated):
		landscape.transit_zone_activated.connect(_on_transit_zone_activated)

	print("Main: landscape ready for '%s' (type=%s, biome=%s). Day clock live." % [
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
func _on_sabotage_target_spawned(target: InteractableTarget) -> void:
	if _player:
		target.set_player(_player)
	if not target.became_interactable.is_connected(_on_sabotage_target_interactable):
		target.became_interactable.connect(_on_sabotage_target_interactable)
	if not target.became_non_interactable.is_connected(_on_target_left):
		target.became_non_interactable.connect(_on_target_left)
	if not target.sabotaged_signal.is_connected(_on_sabotage_target_sabotaged):
		target.sabotaged_signal.connect(_on_sabotage_target_sabotaged)
	_sabotage_targets.append(target)


func _on_sabotage_target_interactable(target: InteractableTarget) -> void:
	_hud.show_prompt(target.prompt_text())


func _on_sabotage_target_sabotaged(target: InteractableTarget) -> void:
	print("Main: target '%s' (sector=%s) sabotaged." % [target.depot_name, target.sector])


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
func _on_terminal_interactable(term: DatashardTerminal) -> void:
	if WorldDirector.get_living_oligarchs().is_empty():
		_hud.show_prompt("[E] %s — no targets yet" % term.terminal_name)
	else:
		_hud.show_prompt(term.prompt_text())


func _on_target_left(_target) -> void:
	_hud.hide_prompt()


func _on_terminal_activated(_terminal_node: DatashardTerminal) -> void:
	_hud.hide_prompt()
	_hud.show_terminal_menu()


func _on_oligarch_picked(oligarch_id: String, action_id: String) -> void:
	print("Main: oligarch action (action=%s, target=%s)." % [action_id, oligarch_id])
	WorldDirector.trigger_event(action_id, oligarch_id)


func _on_politician_bribed(politician_id: String, direction: String) -> void:
	print("Main: bribe politician (id=%s, dir=%s)." % [politician_id, direction])
	WorldDirector.trigger_event("bribe_politician", "%s|%s" % [politician_id, direction])


func _on_patrol_spawned(patrol: EnforcerPatrol) -> void:
	if _player:
		patrol.set_player(_player)
	if not patrol.encountered_player.is_connected(_on_patrol_encounter):
		patrol.encountered_player.connect(_on_patrol_encounter)


func _on_patrol_encounter(patrol: EnforcerPatrol) -> void:
	_hud.hide_prompt()
	# Light alert: world notices where you are. No reinforcement spawn
	# (that's flee-fail only). Other patrols in this phase re-bias.
	if _landscape and is_instance_valid(_landscape) and _player:
		_landscape.raise_alert(_player.global_position, false)
	_hud.show_enforcer_encounter(patrol)


func _on_enforcer_flee_failed(position: Vector3) -> void:
	if _landscape and is_instance_valid(_landscape):
		_landscape.raise_alert(position, true)


func _on_crowd_spawned(crowd: CrowdNPC) -> void:
	if _player:
		crowd.set_player(_player)
	if not crowd.became_interactable.is_connected(_on_crowd_interactable):
		crowd.became_interactable.connect(_on_crowd_interactable)
	if not crowd.became_non_interactable.is_connected(_on_target_left):
		crowd.became_non_interactable.connect(_on_target_left)
	if not crowd.interact_requested.is_connected(_on_crowd_interact):
		crowd.interact_requested.connect(_on_crowd_interact)


func _on_crowd_interactable(crowd: CrowdNPC) -> void:
	_hud.show_prompt(crowd.prompt_text())


func _on_transit_interactable(zone: TransitZone) -> void:
	_hud.show_prompt(zone.prompt_text())


func _on_transit_zone_activated(_zone: TransitZone) -> void:
	_hud.hide_prompt()
	_hud.show_travel_modal()


func _on_travel_requested(region_name: String) -> void:
	travel_to_region(region_name)


# Teardown current landscape + all interactables, regenerate for the
# target region's data. Keeps autoloaded state (WorldDirector economy,
# PlayerManager credits/heat, SenateDirector bill history) untouched —
# travel is a scene-local event, not a run reset.
#
# Moving from one region to another costs ~6 in-game hours — transit
# rides aren't instant, and the clock should reflect that.
const TRAVEL_HOURS_COST: float = 6.0

func travel_to_region(region_name: String) -> void:
	print("Main: traveling to %s" % region_name)
	var region_gen = get_node_or_null("/root/RegionGenerator")
	if region_gen == null:
		push_warning("RegionGenerator missing; cannot travel")
		return
	var target_data: Dictionary = region_gen.get_region_by_name(region_name)
	if target_data.is_empty():
		push_warning("Region '%s' not found" % region_name)
		return

	# Burn travel time BEFORE regenerating. If the skip crosses a day
	# boundary, WorldDirector will tick on day_advanced before the new
	# region finishes loading — that's correct: sim catches up.
	if has_node("/root/TimeSystem"):
		get_node("/root/TimeSystem").skip_hours(TRAVEL_HOURS_COST)

	# Teardown — queue_free cascades to children (patrols, crowd, transit,
	# sabotage targets). Main-owned entities (player, camera, terminal)
	# must be freed explicitly.
	if is_instance_valid(_landscape): _landscape.queue_free()
	if is_instance_valid(_terminal):  _terminal.queue_free()
	if is_instance_valid(_player):    _player.queue_free()
	if is_instance_valid(_camera):    _camera.queue_free()
	_landscape = null
	_terminal = null
	_player = null
	_camera = null
	_sabotage_targets.clear()

	WorldDirector.current_region = region_name

	# Rebuild at the new region.
	_landscape = LandscapeGenerator.new()
	_landscape.name = "Landscape"
	add_child(_landscape)
	if not _landscape.landscape_ready.is_connected(_on_landscape_ready):
		_landscape.landscape_ready.connect(_on_landscape_ready)
	_landscape.generate(target_data)


func _on_crowd_interact(crowd: CrowdNPC) -> void:
	_hud.hide_prompt()
	_hud.show_crowd_interact_menu(crowd)


# Called by HUD after the player picks PICKPOCKET in the crowd menu.
func pickpocket_crowd(crowd: CrowdNPC) -> void:
	var pm = get_node_or_null("/root/PlayerManager")
	if pm == null or crowd.npc_data == null:
		return
	# Stealth roll. Base 50%, +40% from stealth_preference, -10% from target's conformity
	# (conformist citizens pay attention; rule-breakers notice you less).
	var stealth: float = float(pm.player_stealth_preference)
	var conformity: float = float(crowd.npc_data.conformity)
	var chance: float = clamp(0.50 + stealth * 0.40 - conformity * 0.10, 0.15, 0.90)
	var success: bool = randf() < chance
	WorldDirector.apply_pickpocket_result(crowd.npc_data.npc_id, success)
	if success:
		crowd.consume()
	else:
		crowd.flee()


# -------------------------------------------------------------
# Input actions
# -------------------------------------------------------------
func _ensure_input_actions() -> void:
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		InputMap.action_add_event("interact", ev)
