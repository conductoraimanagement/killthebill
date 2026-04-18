extends Node3D
class_name GreyboxTestScene

@onready var navigation_region: NavigationRegion3D = NavigationRegion3D.new()

func _ready() -> void:
    print("Initializing Greybox Test Scene (The Sinks)...")
    
    # 1. Setup Navigation Region to encapsulate the environment
    var nav_mesh = NavigationMesh.new()
    # Optimize navmesh for player collision size
    nav_mesh.agent_radius = 0.5
    nav_mesh.agent_height = 2.0
    navigation_region.navigation_mesh = nav_mesh
    add_child(navigation_region)
    
    # 2. Create the Floor
    _create_floor()
    
    # 3. Create Obstacles (Brutalist blocks)
    # Use deterministic random seed for consistent testing
    seed(1337)
    for i in range(15):
        var pos = Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))
        _create_obstacle(pos)
        
    # 4. Bake Navigation Mesh based on generated geometry
    navigation_region.bake_navigation_mesh(false)
    print("Greybox environment built and NavMesh baked.")

func _create_floor() -> void:
    var floor_body = StaticBody3D.new()
    navigation_region.add_child(floor_body)
    
    var mesh_instance = MeshInstance3D.new()
    var box = BoxMesh.new()
    box.size = Vector3(50, 1, 50)
    mesh_instance.mesh = box
    floor_body.add_child(mesh_instance)
    
    var shape = CollisionShape3D.new()
    var box_shape = BoxShape3D.new()
    box_shape.size = Vector3(50, 1, 50)
    shape.shape = box_shape
    floor_body.add_child(shape)
    
    floor_body.position = Vector3(0, -0.5, 0)

func _create_obstacle(pos: Vector3) -> void:
    var body = StaticBody3D.new()
    navigation_region.add_child(body)
    
    var mesh_instance = MeshInstance3D.new()
    var box = BoxMesh.new()
    # Randomly scale the blocks to simulate haphazard slum architecture
    box.size = Vector3(randf_range(2, 6), randf_range(2, 8), randf_range(2, 6))
    mesh_instance.mesh = box
    body.add_child(mesh_instance)
    
    var shape = CollisionShape3D.new()
    var box_shape = BoxShape3D.new()
    box_shape.size = box.size
    shape.shape = box_shape
    body.add_child(shape)
    
    # Offset Y so it sits on the floor
    body.position = Vector3(pos.x, box.size.y / 2.0, pos.z)
