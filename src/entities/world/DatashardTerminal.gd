extends Node3D
class_name DatashardTerminal

# =============================================================
# DatashardTerminal: the information-warfare lever.
# Walk within range, press E, a modal opens listing living
# oligarchs. Picking one triggers WorldDirector's leak_scandal
# ripple against that oligarch.
#
# Intentionally mirrors InteractableTarget's shape — same input
# action, same proximity model — but delegates to the HUD
# instead of firing a ripple directly.
# =============================================================

signal became_interactable(target: DatashardTerminal)
signal became_non_interactable(target: DatashardTerminal)
signal requested_oligarch_pick(terminal: DatashardTerminal)

@export var terminal_name: String = "Datashard Terminal"
@export var interact_range: float = 3.0

var _player: Node3D = null
var _in_range: bool = false
var _mesh: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	_build_visual()
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		InputMap.action_add_event("interact", ev)


func set_player(player: Node3D) -> void:
	_player = player


func _process(_delta: float) -> void:
	if _player == null:
		return
	var dist: float = _player.global_position.distance_to(global_position)
	var in_range_now: bool = dist <= interact_range

	if in_range_now and not _in_range:
		_in_range = true
		became_interactable.emit(self)
	elif not in_range_now and _in_range:
		_in_range = false
		became_non_interactable.emit(self)

	if _in_range and Input.is_action_just_pressed("interact"):
		requested_oligarch_pick.emit(self)


func prompt_text() -> String:
	return "[E] Leak scandal via %s" % terminal_name


func _build_visual() -> void:
	# Visual-only (no collision) — see InteractableTarget for why.
	# Base pedestal
	var base_mesh := MeshInstance3D.new()
	var base_box := BoxMesh.new()
	base_box.size = Vector3(1.6, 0.6, 1.6)
	base_mesh.mesh = base_box
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.16, 0.18, 0.22)
	base_mesh.material_override = base_mat
	base_mesh.position = Vector3(0, 0.3, 0)
	add_child(base_mesh)

	# Terminal screen — glowing cyan monolith
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.6, 0.3)
	_mesh.mesh = box
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.30, 0.79, 0.79)   # cyan
	_material.emission_enabled = true
	_material.emission = Color(0.30, 0.79, 0.79)
	_material.emission_energy_multiplier = 0.9
	_mesh.material_override = _material
	_mesh.position = Vector3(0, 1.4, 0)
	add_child(_mesh)
