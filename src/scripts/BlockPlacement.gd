extends Node3D

var main_node: Node
var grid_manager: Node
var block_root: Node3D
var max_walls: int = 0
var remaining_walls: int = 0
var placed_blocks: Dictionary = {}  # key: Vector2i(x, y), value: Node3D

func _ready():
	print("BlockPlacement ready")

func setup(p_main: Node, p_grid_manager: Node, p_block_root: Node3D, p_max_walls: int) -> void:
	main_node = p_main
	grid_manager = p_grid_manager
	block_root = p_block_root
	max_walls = p_max_walls
	remaining_walls = max_walls
	
	print("BlockPlacement setup done")
	print("max_walls: ", max_walls)
	print("remaining_walls: ", remaining_walls)
	print("main_node is null? ", main_node == null)
	print("grid_manager is null? ", grid_manager == null)
	print("block_root is null? ", block_root == null)

func clear_blocks() -> void:
	for key in placed_blocks:
		var block = placed_blocks[key]
		if is_instance_valid(block):
			block.queue_free()
	placed_blocks.clear()
	remaining_walls = max_walls

func get_remaining_walls() -> int:
	return remaining_walls

func is_cell_occupied(x: int, y: int) -> bool:
	return placed_blocks.has(Vector2i(x, y))

func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed:
		return
	
	print("BlockPlacement received left click")
	
	if not main_node.is_editable():
		print("Cannot edit. Current state: ", main_node.current_state)
		return
	
	var hovered_control = get_viewport().gui_get_hovered_control()
	if hovered_control != null:
		if hovered_control is Button:
			print("Click ignored because hovered control: ", hovered_control.name)
			return
	
	var camera = get_viewport().get_camera_3d()
	if camera == null:
		print("Cannot place wall: camera is null")
		return
	
	var ray_origin = camera.project_ray_origin(event.position)
	var ray_dir = camera.project_ray_normal(event.position)
	
	var world_pos = _raycast_plane(ray_origin, ray_dir)
	if world_pos == null:
		print("Ray did not hit placement plane")
		return
	
	print("Click world pos: ", world_pos)
	
	var cell = grid_manager.world_to_grid(world_pos)
	var gx = cell.x
	var gy = cell.y
	
	print("Clicked cell: ", gx, ", ", gy)
	
	if not grid_manager.is_inside_grid(gx, gy):
		print("Cannot place wall: out of grid")
		return
	
	if grid_manager.is_water_source_cell(gx, gy):
		print("Cannot place wall: water source")
		return
	
	if grid_manager.is_task_area_cell(gx, gy):
		print("Cannot place wall: task area")
		return
	
	var key = Vector2i(gx, gy)
	if placed_blocks.has(key):
		_remove_wall(gx, gy)
		return
	
	if remaining_walls <= 0:
		print("Cannot place wall: no walls remaining")
		return
	
	_place_wall(gx, gy)

func _raycast_plane(ray_origin: Vector3, ray_dir: Vector3) -> Variant:
	# 射线与平面 Y=0 求交点（地形柱体底部在 Y=0）
	var plane_y = 0.0
	var denom = ray_dir.y
	if abs(denom) < 0.0001:
		return null
	
	var t = (plane_y - ray_origin.y) / denom
	if t < 0:
		return null
	
	var hit_point = ray_origin + ray_dir * t
	return hit_point

func _place_wall(x: int, y: int) -> void:
	var world_pos = grid_manager.grid_to_world(x, y)
	var visual_height = grid_manager.get_visual_height(x, y)
	
	var wall = MeshInstance3D.new()
	wall.name = "Wall_%d_%d" % [x, y]
	
	var mesh = BoxMesh.new()
	mesh.size = Vector3(grid_manager.cell_size * 0.75, 1.0, grid_manager.cell_size * 0.75)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.33, 0.38, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.roughness = 0.7
	mesh.material = material
	
	wall.mesh = mesh
	# 墙壁放在地形柱体顶部
	wall.position = Vector3(world_pos.x, visual_height + 0.55, world_pos.z)
	
	block_root.add_child(wall)
	
	var key = Vector2i(x, y)
	placed_blocks[key] = wall
	grid_manager.set_obstacle(x, y, wall.name)
	remaining_walls -= 1
	main_node.set_wall_remaining(remaining_walls)
	
	print("Wall placed at: ", x, ", ", y)
	print("BlockRoot child count: ", block_root.get_child_count())
	print("Remaining walls: ", remaining_walls)

func _remove_wall(x: int, y: int) -> void:
	var key = Vector2i(x, y)
	if not placed_blocks.has(key):
		return
	
	var block = placed_blocks[key]
	if is_instance_valid(block):
		block.queue_free()
	
	placed_blocks.erase(key)
	grid_manager.set_obstacle(x, y, "")
	remaining_walls += 1
	main_node.set_wall_remaining(remaining_walls)
	
	print("Wall removed at: ", x, ", ", y)
	print("Remaining walls: ", remaining_walls)
