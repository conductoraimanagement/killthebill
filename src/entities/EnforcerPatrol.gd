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

# Alert state — set by LandscapeGenerator.raise_alert(pos) after any
# failed-flee encounter. Alerted patrols bias their waypoints toward
# the last known player position AND light a red strobe on the strap.
var _alerted: bool = false
var _alert_target: Vector3 = Vector3.ZERO
var _alert_strobe: MeshInstance3D
var _strobe_timer: float = 0.0


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
	# If alerted, waypoints re-target toward the last known player
	# position each second. Not pathfinding — just a bias. Patrols
	# still walk A↔B, but A and B drift toward the alert target.
	if _alerted:
		_strobe_timer += delta
		if _alert_strobe:
			var visible: bool = fmod(_strobe_timer, 0.8) < 0.4
			_alert_strobe.visible = visible
		# Occasionally re-anchor the patrol route toward the alert point.
		var alert_dist: float = global_position.distance_to(_alert_target)
		if alert_dist > 4.0:
			# Slide A/B toward the alert; clamped so they still form an A↔B line.
			var pull := (_alert_target - global_position).normalized() * 0.6
			pull.y = 0.0
			waypoint_a = waypoint_a.lerp(waypoint_a + pull, delta * 1.2)
			waypoint_b = waypoint_b.lerp(waypoint_b + pull, delta * 1.2)

	# Patrol movement
	var to_target: Vector3 = _target - global_position
	to_target.y = 0.0
	var dist_to_wp: float = to_target.length()
	if dist_to_wp < 0.4:
		_target = waypoint_a if _target == waypoint_b else waypoint_b
	else:
		var speed: float = PATROL_SPEED * (1.4 if _alerted else 1.0)
		var step: Vector3 = to_target.normalized() * speed * delta
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


# Called by LandscapeGenerator when the network-wide alert fires
# (player failed a flee). This patrol biases its route toward the
# reported position and lights a strobe.
func raise_alert(target_position: Vector3) -> void:
	_alerted = true
	_alert_target = target_position
	_strobe_timer = 0.0
	if _alert_strobe:
		_alert_strobe.visible = true


func clear_alert() -> void:
	_alerted = false
	if _alert_strobe:
		_alert_strobe.visible = false


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

	# Red strobe on the strap — visible only when _alerted, blinking via _process.
	_alert_strobe = MeshInstance3D.new()
	var strobe_mesh := SphereMesh.new()
	strobe_mesh.radius = 0.14
	strobe_mesh.height = 0.28
	_alert_strobe.mesh = strobe_mesh
	var strobe_mat := StandardMaterial3D.new()
	strobe_mat.albedo_color = Color(1.00, 0.12, 0.18)
	strobe_mat.emission_enabled = true
	strobe_mat.emission = Color(1.00, 0.10, 0.18)
	strobe_mat.emission_energy_multiplier = 1.3
	_alert_strobe.material_override = strobe_mat
	_alert_strobe.position = Vector3(0, 1.75, 0.15)
	_alert_strobe.visible = false
	_mesh_root.add_child(_alert_strobe)
