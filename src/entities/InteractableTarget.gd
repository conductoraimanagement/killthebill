extends Node3D
class_name InteractableTarget

# =============================================================
# InteractableTarget: a sabotageable point of interest.
# The first playable lever. Walk within range, press E, the
# WorldDirector runs _ripple_sabotage on the given sector.
# =============================================================

signal became_interactable(target: InteractableTarget)
signal became_non_interactable(target: InteractableTarget)
signal sabotaged_signal(target: InteractableTarget)

@export var sector: String = "Food"
@export var depot_name: String = "Ash Row Food Depot"
@export var interact_range: float = 3.0
@export var sabotaged: bool = false

var _player: Node3D = null
var _in_range: bool = false
var _mesh: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	_build_visual()
	# Register the input action once (cheap idempotent).
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		InputMap.action_add_event("interact", ev)


func set_player(player: Node3D) -> void:
	_player = player


func _process(_delta: float) -> void:
	if sabotaged or _player == null:
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
		_sabotage()


func _sabotage() -> void:
	if sabotaged:
		return
	sabotaged = true
	if _in_range:
		_in_range = false
		became_non_interactable.emit(self)

	# Visual burn-out
	if _material:
		_material.albedo_color = Color(0.18, 0.14, 0.10)
		_material.emission_enabled = false

	# Fire the world-level ripple (already defined in WorldDirector).
	WorldDirector.trigger_event("sabotage_facility", sector)
	sabotaged_signal.emit(self)


func prompt_text() -> String:
	return "[E] Sabotage %s" % depot_name


func _build_visual() -> void:
	# Visual-only (no collision) — navmesh is already baked by the Greybox
	# by the time we spawn. Adding a blocking body here would just snare
	# the NavigationAgent3D. Good enough for the slice.
	var box := BoxMesh.new()
	box.size = Vector3(2.4, 2.4, 2.4)

	_mesh = MeshInstance3D.new()
	_mesh.mesh = box
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(1.00, 0.80, 0.20)        # slag yellow
	_material.emission_enabled = true
	_material.emission = Color(1.00, 0.60, 0.10)
	_material.emission_energy_multiplier = 0.7
	_mesh.material_override = _material
	_mesh.position = Vector3(0, box.size.y / 2.0, 0)
	add_child(_mesh)
