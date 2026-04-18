extends Camera3D
class_name CameraController

@export var move_speed: float = 20.0
@export var zoom_speed: float = 2.0
@export var min_zoom: float = 5.0
@export var max_zoom: float = 25.0
@export var edge_pan_margin: int = 50
@export var follow_speed: float = 5.0

var target: Node3D = null
var _current_zoom: float = 15.0
var _is_following: bool = false

func _ready() -> void:
    # Enforce Isometric Orthogonal Perspective
    projection = Camera3D.PROJECTION_ORTHOGONAL
    size = _current_zoom
    
    # Standard Isometric Angles: X: -30 deg, Y: 45 deg, Z: 0
    rotation_degrees = Vector3(-30, 45, 0)
    
    # Ensure camera is high enough to not clip through geometry
    position.y = 50.0

func _process(delta: float) -> void:
    if _is_following and target != null:
        _smooth_follow(delta)
    else:
        _handle_panning(delta)

func _input(event: InputEvent) -> void:
    _handle_zooming(event)

func set_target(new_target: Node3D) -> void:
    target = new_target
    _is_following = true

func detach() -> void:
    _is_following = false
    target = null

func _smooth_follow(delta: float) -> void:
    if target:
        var target_pos = target.global_position
        
        # Calculate offset based on camera angle to ensure target is centered
        # Magic math for a 30-degree downward tilt
        var offset_dist = position.y / tan(deg_to_rad(30.0))
        
        # Since camera is rotated 45 degrees on Y, we split the offset across X and Z
        var dir = Vector3(0, 0, 1).rotated(Vector3.UP, deg_to_rad(45))
        var desired_pos = target_pos + (dir * offset_dist)
        desired_pos.y = position.y
        
        # Smooth interpolation
        global_position = global_position.lerp(desired_pos, follow_speed * delta)

func _handle_panning(delta: float) -> void:
    var input_dir = Vector3.ZERO
    
    # WASD Panning
    if Input.is_action_pressed("ui_up"): input_dir.z -= 1
    if Input.is_action_pressed("ui_down"): input_dir.z += 1
    if Input.is_action_pressed("ui_left"): input_dir.x -= 1
    if Input.is_action_pressed("ui_right"): input_dir.x += 1
    
    # Screen Edge Panning
    var mouse_pos = get_viewport().get_mouse_position()
    var viewport_size = get_viewport().get_visible_rect().size
    
    if mouse_pos.x < edge_pan_margin: input_dir.x -= 1
    if mouse_pos.x > viewport_size.x - edge_pan_margin: input_dir.x += 1
    if mouse_pos.y < edge_pan_margin: input_dir.z -= 1
    if mouse_pos.y > viewport_size.y - edge_pan_margin: input_dir.z += 1
    
    if input_dir != Vector3.ZERO:
        # Normalize to prevent faster diagonal movement
        input_dir = input_dir.normalized()
        
        # Rotate input direction to match isometric 45-degree rotation
        var rotated_dir = input_dir.rotated(Vector3.UP, deg_to_rad(45))
        
        # Apply movement
        global_position += rotated_dir * move_speed * delta

func _handle_zooming(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _current_zoom -= zoom_speed
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _current_zoom += zoom_speed
            
        _current_zoom = clamp(_current_zoom, min_zoom, max_zoom)
        size = _current_zoom
