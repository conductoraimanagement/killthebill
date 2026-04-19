extends Node3D
class_name EnforcerPatrol

# =============================================================
# EnforcerPatrol: an ambient Enforcer on a simple A↔B patrol.
# When the player enters detection range AND the player is
# hot enough, it emits `encountered_player` and stops moving.
# The HUD owns the encounter modal; after the player picks a
# resolution, the modal calls resolve() which queue_frees the
# patrol.
# =============================================================

signal encountered_player(patrol)

const DETECTION_RANGE := 6.0
const PATROL_SPEED := 2.6
const HEAT_DETECTION_THRESHOLD := 30

@export var waypoint_a: Vector3 = Vector3.ZERO
@export var waypoint_b: Vector3 = Vector3.ZERO

var _player: Node3D = null
var _target: Vector3 = Vector3.ZERO
var _encounter_fired: bool = false
var _mesh_root: Node3D


func _ready() -> void:
	_build_visual()
	_target = waypoint_b
	global_position = waypoint_a


func set_player(player: Node3D) -> void:
	_player = player


func set_waypoints(a: Vector3, b: Vector3) -> void:
	waypoint_a = a
	waypoint_b = b
	_target = b
	global_position = a


func _process(delta: float) -> void:
	# Patrol movement
	var to_target: Vector3 = _target - global_position
	to_target.y = 0.0
	var dist_to_wp: float = to_target.length()
	if dist_to_wp < 0.4:
		_target = waypoint_a if _target == waypoint_b else waypoint_b
	else:
		var step: Vector3 = to_target.normalized() * PATROL_SPEED * delta
		global_position += step
		# Face movement direction
		if step.length_squared() > 0.0001:
			rotation.y = atan2(-step.x, -step.z)

	# Detection check — only if we haven't already fired this encounter.
	if _encounter_fired or _player == null:
		return

	var pm := get_node_or_null("/root/PlayerManager")
	if pm == null:
		return
	if int(pm.heat) < HEAT_DETECTION_THRESHOLD:
		return

	if _player.global_position.distance_to(global_position) <= DETECTION_RANGE:
		_encounter_fired = true
		encountered_player.emit(self)


# Called by the HUD encounter modal after the player resolves it.
# The patrol is consumed — despawn. Future slices can change this
# (flee might keep the patrol on alert instead of despawning).
func resolve() -> void:
	queue_free()


# -------------------------------------------------------------
# Visual: dark uniform capsule + amber emissive shoulder strap
# -------------------------------------------------------------
func _build_visual() -> void:
	_mesh_root = Node3D.new()
	add_child(_mesh_root)

	# Body
	var body := MeshInstance3D.new()
	var caps := CapsuleMesh.new()
	caps.radius = 0.42
	caps.height = 1.8
	body.mesh = caps
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.08, 0.09, 0.13)
	body_mat.roughness = 0.55
	body.material_override = body_mat
	body.position = Vector3(0, 1.0, 0)
	_mesh_root.add_child(body)

	# Helmet (a small darker sphere on top)
	var helmet := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.30
	sph.height = 0.60
	helmet.mesh = sph
	var helmet_mat := StandardMaterial3D.new()
	helmet_mat.albedo_color = Color(0.04, 0.05, 0.08)
	helmet_mat.roughness = 0.4
	helmet.material_override = helmet_mat
	helmet.position = Vector3(0, 2.05, 0)
	_mesh_root.add_child(helmet)

	# Shoulder strap — amber emissive so you can read it as an Enforcer at distance
	var strap := MeshInstance3D.new()
	var strap_box := BoxMesh.new()
	strap_box.size = Vector3(0.95, 0.14, 0.55)
	strap.mesh = strap_box
	var strap_mat := StandardMaterial3D.new()
	strap_mat.albedo_color = Color(1.00, 0.62, 0.15)
	strap_mat.emission_enabled = true
	strap_mat.emission = Color(1.00, 0.62, 0.15)
	strap_mat.emission_energy_multiplier = 0.7
	strap.material_override = strap_mat
	strap.position = Vector3(0, 1.55, 0)
	_mesh_root.add_child(strap)

	# Short-range headlight — a cone rod out the front to suggest scanning
	var scan := MeshInstance3D.new()
	var scan_box := BoxMesh.new()
	scan_box.size = Vector3(0.10, 0.10, 0.40)
	scan.mesh = scan_box
	scan.material_override = strap_mat
	scan.position = Vector3(0, 1.7, -0.35)
	_mesh_root.add_child(scan)
