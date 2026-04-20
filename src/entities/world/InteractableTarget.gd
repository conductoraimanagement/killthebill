extends Node3D
class_name InteractableTarget

# =============================================================
# InteractableTarget: a sabotageable point of interest.
# Walk within range, press E, WorldDirector runs _ripple_sabotage
# on the given sector.
#
# Per-region-type variants: one entity class, many landmark kinds.
# KIND_CONFIGS maps landmark_kind → sector + visual profile. Set
# landmark_kind BEFORE add_child.
# =============================================================

signal became_interactable(target: InteractableTarget)
signal became_non_interactable(target: InteractableTarget)
signal sabotaged_signal(target: InteractableTarget)

const KIND_CONFIGS: Dictionary = {
	"food_depot": {
		"sector": "Food",
		"color": Color(1.00, 0.80, 0.20),
		"emission": Color(1.00, 0.60, 0.10),
		"mesh": "box",
		"size": Vector3(2.4, 2.4, 2.4),
		"display_prefix": "Food Depot",
	},
	"financial_center": {
		"sector": "Finance",
		"color": Color(0.24, 0.70, 0.85),
		"emission": Color(0.30, 0.80, 0.95),
		"mesh": "tall_box",
		"size": Vector3(2.2, 6.0, 2.2),
		"display_prefix": "Financial Center",
	},
	"clearing_house": {
		"sector": "Finance",
		"color": Color(0.75, 0.65, 0.32),
		"emission": Color(1.00, 0.88, 0.35),
		"mesh": "cylinder",
		"size": Vector3(2.6, 3.6, 2.6),
		"display_prefix": "Clearing House",
	},
	"refinery": {
		"sector": "Tech",
		"color": Color(0.45, 0.25, 0.14),
		"emission": Color(1.00, 0.52, 0.15),
		"mesh": "cylinder",
		"size": Vector3(2.4, 4.8, 2.4),
		"display_prefix": "Refinery",
	},
	"power_relay": {
		"sector": "Energy",
		"color": Color(0.40, 0.34, 0.12),
		"emission": Color(1.00, 0.85, 0.15),
		"mesh": "box",
		"size": Vector3(2.6, 2.6, 2.6),
		"display_prefix": "Power Relay",
	},
	"hydro_vault": {
		"sector": "Food",
		"color": Color(0.40, 0.75, 0.48),
		"emission": Color(0.35, 1.00, 0.45),
		"mesh": "low_box",
		"size": Vector3(3.2, 1.8, 3.2),
		"display_prefix": "Hydro Vault",
	},
	"grain_silo": {
		"sector": "Food",
		"color": Color(0.62, 0.56, 0.40),
		"emission": Color(0.85, 0.75, 0.55),
		"mesh": "cylinder",
		"size": Vector3(2.0, 5.6, 2.0),
		"display_prefix": "Grain Silo",
	},
	"private_dock": {
		"sector": "Security",
		"color": Color(0.32, 0.32, 0.36),
		"emission": Color(1.00, 0.40, 0.40),
		"mesh": "long_box",
		"size": Vector3(4.5, 1.3, 1.8),
		"display_prefix": "Private Dock",
	},
	"checkpoint_scanner": {
		"sector": "Security",
		"color": Color(0.25, 0.25, 0.30),
		"emission": Color(1.00, 0.20, 0.20),
		"mesh": "tall_box",
		"size": Vector3(1.6, 4.2, 1.6),
		"display_prefix": "Checkpoint Scanner",
	},
	"media_spire": {
		"sector": "Media",
		"color": Color(0.80, 0.28, 0.55),
		"emission": Color(1.00, 0.16, 0.50),
		"mesh": "tall_box",
		"size": Vector3(1.5, 7.0, 1.5),
		"display_prefix": "Media Spire",
	},
}

@export var landmark_kind: String = "food_depot"
@export var sector: String = "Food"
@export var depot_name: String = "Food Depot"
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


func set_landmark_kind(kind: String) -> void:
	landmark_kind = kind
	var cfg: Dictionary = KIND_CONFIGS.get(kind, KIND_CONFIGS["food_depot"])
	sector = str(cfg.get("sector", "Food"))


func _build_visual() -> void:
	# Visual-only (no collision) — navmesh is already baked by the landscape
	# by the time we spawn. Adding a blocking body here would just snare
	# the NavigationAgent3D.
	var cfg: Dictionary = KIND_CONFIGS.get(landmark_kind, KIND_CONFIGS["food_depot"])
	var size: Vector3 = cfg.get("size", Vector3(2.4, 2.4, 2.4))
	var mesh_shape: String = str(cfg.get("mesh", "box"))

	var mesh_res: Mesh
	match mesh_shape:
		"cylinder":
			var cyl := CylinderMesh.new()
			cyl.top_radius = size.x / 2.0
			cyl.bottom_radius = size.x / 2.0
			cyl.height = size.y
			mesh_res = cyl
		_:
			var box := BoxMesh.new()
			box.size = size
			mesh_res = box

	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh_res
	_material = StandardMaterial3D.new()
	_material.albedo_color = cfg.get("color", Color(1.00, 0.80, 0.20))
	_material.emission_enabled = true
	_material.emission = cfg.get("emission", Color(1.00, 0.60, 0.10))
	_material.emission_energy_multiplier = 0.7
	_mesh.material_override = _material
	_mesh.position = Vector3(0, size.y / 2.0, 0)
	add_child(_mesh)
