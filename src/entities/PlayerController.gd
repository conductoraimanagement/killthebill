extends CharacterBody3D
class_name PlayerController

@export var move_speed: float = 5.0
@export var acceleration: float = 10.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

func _ready() -> void:
    if not nav_agent:
        push_warning("PlayerController requires a NavigationAgent3D child node.")
    else:
        nav_agent.path_desired_distance = 0.5
        nav_agent.target_desired_distance = 0.5

func _physics_process(delta: float) -> void:
    if not nav_agent or nav_agent.is_navigation_finished():
        # Stop moving if we reached the target
        velocity = velocity.move_toward(Vector3.ZERO, acceleration * delta)
        move_and_slide()
        return

    var current_agent_position: Vector3 = global_position
    var next_path_position: Vector3 = nav_agent.get_next_path_position()

    # Calculate direction to the next path point
    var direction = current_agent_position.direction_to(next_path_position)
    
    # We only care about X and Z movement for a typical isometric ground unit
    direction.y = 0
    if direction.length_squared() > 0.001:
        direction = direction.normalized()

    # Apply velocity
    var desired_velocity = direction * move_speed
    velocity = velocity.lerp(desired_velocity, acceleration * delta)

    # Face the movement direction
    if direction.length_squared() > 0.01:
        # Look at the target direction
        var target_rotation = atan2(-direction.x, -direction.z)
        rotation.y = lerp_angle(rotation.y, target_rotation, 10.0 * delta)

    move_and_slide()

# Called externally (e.g., from the CameraController or InputManager via raycast)
func set_movement_target(target_point: Vector3) -> void:
    if nav_agent:
        nav_agent.set_target_position(target_point)
