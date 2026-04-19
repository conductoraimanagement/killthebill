extends Node3D
class_name CrowdNPC

# =============================================================
# CrowdNPC: an ambient street citizen spawned in the landscape
# from the persistent NPC roster. Player can pickpocket one by
# walking up and pressing E. The pickpocket is a stealth roll;
# resolution is handled by Main + WorldDirector.apply_pickpocket_result.
#
# Unlike EnforcerPatrols (which hunt you), CrowdNPCs are passive
# targets until interacted with. Not all of them are in the streets
# at all times — filtered by NPCData.active_phase so night-only
# fences only appear after dusk.
# =============================================================

signal became_interactable(crowd)
signal became_non_interactable(crowd)
signal pickpocket_requested(crowd)

const DETECTION_RANGE := 2.6
const FLEE_SPEED := 6.0
const FLEE_DURATION := 1.5

var npc_data = null  # NPCData — set via set_npc_data before add_child

var _player: Node3D = null
var _in_range: bool = false
var _mesh_root: Node3D
var _body_mat: StandardMaterial3D

var _fleeing: bool = false
var _flee_elapsed: float = 0.0
var _flee_direction: Vector3 = Vector3.ZERO


func _ready() -> void:
	_build_visual()
	_apply_data_styling()
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		InputMap.action_add_event("interact", ev)


func set_player(player: Node3D) -> void:
	_player = player


func set_npc_data(data) -> void:
	npc_data = data
	_apply_data_styling()


func prompt_text() -> String:
	if npc_data != null:
		return "[E] Pickpocket %s" % npc_data.npc_name
	return "[E] Pickpocket"


func _process(delta: float) -> void:
	if _fleeing:
		global_position += _flee_direction * FLEE_SPEED * delta
		rotation.y = atan2(-_flee_direction.x, -_flee_direction.z)
		_flee_elapsed += delta
		if _flee_elapsed >= FLEE_DURATION:
			queue_free()
		return

	if _player == null:
		return

	var dist: float = _player.global_position.distance_to(global_position)
	var in_range_now: bool = dist <= DETECTION_RANGE

	if in_range_now and not _in_range:
		_in_range = true
		became_interactable.emit(self)
	elif not in_range_now and _in_range:
		_in_range = false
		became_non_interactable.emit(self)

	if _in_range and Input.is_action_just_pressed("interact"):
		pickpocket_requested.emit(self)


# Called after a successful pickpocket — citizen walks away unaware.
func consume() -> void:
	if _in_range:
		_in_range = false
		became_non_interactable.emit(self)
	queue_free()


# Called after a failed pickpocket — citizen bolts.
func flee() -> void:
	_fleeing = true
	_flee_elapsed = 0.0
	if _player:
		_flee_direction = (global_position - _player.global_position).normalized()
		_flee_direction.y = 0.0
	else:
		_flee_direction = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)).normalized()
	if _in_range:
		_in_range = false
		became_non_interactable.emit(self)


# -------------------------------------------------------------
# Visual — class-colored capsule, smaller than the player
# -------------------------------------------------------------
func _build_visual() -> void:
	_mesh_root = Node3D.new()
	add_child(_mesh_root)

	var body := MeshInstance3D.new()
	var caps := CapsuleMesh.new()
	caps.radius = 0.34
	caps.height = 1.5
	body.mesh = caps
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.45, 0.32, 0.25)
	_body_mat.roughness = 0.9
	body.material_override = _body_mat
	body.position = Vector3(0, 0.85, 0)
	_mesh_root.add_child(body)

	# Small head to distinguish from capsule silhouette
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.22
	sph.height = 0.44
	head.mesh = sph
	head.material_override = _body_mat
	head.position = Vector3(0, 1.75, 0)
	_mesh_root.add_child(head)


func _apply_data_styling() -> void:
	if _body_mat == null or npc_data == null:
		return
	# Color by social_class. Enforcers (class 1) aren't spawned as crowd,
	# but guard the branch anyway.
	match int(npc_data.social_class):
		1: _body_mat.albedo_color = Color(0.18, 0.20, 0.26)   # Enforcer-navy fallback
		2: _body_mat.albedo_color = Color(0.52, 0.36, 0.24)   # Worker rust
		3: _body_mat.albedo_color = Color(0.32, 0.30, 0.28)   # Destitute gray
