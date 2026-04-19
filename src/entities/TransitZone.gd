extends Node3D
class_name TransitZone

# =============================================================
# TransitZone: the edge-of-map landmark where the player can
# trigger inter-region travel. A tall magenta-emissive pillar
# with a dark base, distinct silhouette from the depot (yellow)
# and the datashard terminal (cyan).
# =============================================================

signal became_interactable(zone)
signal became_non_interactable(zone)
signal activated(zone)

const INTERACT_RANGE := 3.5

var _player: Node3D = null
var _in_range: bool = false


func _ready() -> void:
	_build_visual()
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		InputMap.action_add_event("interact", ev)


func set_player(player: Node3D) -> void:
	_player = player


func prompt_text() -> String:
	return "[E] Travel to another region"


func _process(_delta: float) -> void:
	if _player == null:
		return
	var dist: float = _player.global_position.distance_to(global_position)
	var in_range_now: bool = dist <= INTERACT_RANGE

	if in_range_now and not _in_range:
		_in_range = true
		became_interactable.emit(self)
	elif not in_range_now and _in_range:
		_in_range = false
		became_non_interactable.emit(self)

	if _in_range and Input.is_action_just_pressed("interact"):
		activated.emit(self)


func _build_visual() -> void:
	# Base plinth — dark, grounded
	var base := MeshInstance3D.new()
	var base_box := BoxMesh.new()
	base_box.size = Vector3(2.2, 0.5, 2.2)
	base.mesh = base_box
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.14, 0.10, 0.18)
	base.material_override = base_mat
	base.position = Vector3(0, 0.25, 0)
	add_child(base)

	# Pillar — tall magenta emissive
	var pillar := MeshInstance3D.new()
	var p_box := BoxMesh.new()
	p_box.size = Vector3(0.8, 6.0, 0.8)
	pillar.mesh = p_box
	var p_mat := StandardMaterial3D.new()
	p_mat.albedo_color = Color(0.65, 0.25, 0.85)
	p_mat.emission_enabled = true
	p_mat.emission = Color(0.85, 0.35, 1.00)
	p_mat.emission_energy_multiplier = 1.2
	pillar.material_override = p_mat
	pillar.position = Vector3(0, 3.5, 0)
	add_child(pillar)

	# Top ring — accent
	var ring := MeshInstance3D.new()
	var r_box := BoxMesh.new()
	r_box.size = Vector3(1.6, 0.2, 1.6)
	ring.mesh = r_box
	ring.material_override = p_mat
	ring.position = Vector3(0, 6.6, 0)
	add_child(ring)
