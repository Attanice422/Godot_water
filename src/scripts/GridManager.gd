extends Node3D

var board_root: Node3D
var marker_root: Node3D
var level_data: Dictionary
var grid_width: int
var grid_height: int
var cell_size: float

var ground_tiles: Array = []
var source_markers: Array = []
var victory_markers: Array = []
var failure_markers: Array = []

var obstacles: Dictionary = {}

func setup(p_board_root: Node3D, p_marker_root: Node3D):
	board_root = p_board_root
	marker_root = p_marker_root

func load_level(p_level_data: Dictionary):
	level_data = p_level_data
	grid_width = int(level_data.gridWidth)
	grid_height = int(level_data.gridHeight)
	cell_size = float(level_data.cellSize)
	
	_clear_board()
	_clear_markers()
	_generate_ground()
	_generate_markers()
	
	print("GridManager load_level called")
	print("gridWidth: ", grid_width)
	print("gridHeight: ", grid_height)
	print("cellSize: ", cell_size)
	print("BoardRoot is null? ", board_root == null)
	print("MarkerRoot is null? ", marker_root == null)
	print("Generated ground tile count: ", ground_tiles.size())
	print("Generated source marker count: ", source_markers.size())
	print("Generated victory marker count: ", victory_markers.size())
	print("Generated failure marker count: ", failure_markers.size())
	print("BoardRoot child count: ", board_root.get_child_count())
	print("MarkerRoot child count: ", marker_root.get_child_count())

func grid_to_world(x: int, y: int) -> Vector3:
	var world_x = (float(x) - float(grid_width - 1) / 2.0) * cell_size
	var world_z = (float(y) - float(grid_height - 1) / 2.0) * cell_size
	return Vector3(world_x, 0, world_z)

func world_to_grid(world_pos: Vector3) -> Vector2i:
	var gx = int(round(world_pos.x / cell_size + float(grid_width - 1) / 2.0))
	var gy = int(round(world_pos.z / cell_size + float(grid_height - 1) / 2.0))
	return Vector2i(gx, gy)

func is_inside_grid(x: int, y: int) -> bool:
	return x >= 0 and x < grid_width and y >= 0 and y < grid_height

func set_obstacle(x: int, y: int, block_id: String) -> void:
	if not is_inside_grid(x, y):
		return
	var key = Vector2i(x, y)
	if block_id == "":
		obstacles.erase(key)
	else:
		obstacles[key] = block_id

func has_obstacle(x: int, y: int) -> bool:
	return obstacles.has(Vector2i(x, y))

func get_block_id(x: int, y: int) -> String:
	var key = Vector2i(x, y)
	if obstacles.has(key):
		return str(obstacles[key])
	return ""

func clear_obstacles() -> void:
	obstacles.clear()

func get_visual_height(x: int, y: int) -> float:
	if not is_inside_grid(x, y):
		return 0.0
	return float(level_data.terrain[y][x]) * 0.15

func is_water_source_cell(x: int, y: int) -> bool:
	for source in level_data.waterSources:
		if int(source.x) == x and int(source.y) == y:
			return true
	return false

func is_task_area_cell(x: int, y: int) -> bool:
	for area in level_data.taskAreas:
		var region = area.region
		if x >= int(region.x1) and x <= int(region.x2) and y >= int(region.y1) and y <= int(region.y2):
			return true
	return false

func _clear_board():
	for child in board_root.get_children():
		child.queue_free()
	ground_tiles.clear()

func _clear_markers():
	for child in marker_root.get_children():
		child.queue_free()
	source_markers.clear()
	victory_markers.clear()
	failure_markers.clear()

func _generate_ground():
	var terrain = level_data.terrain
	
	for y in range(grid_height):
		for x in range(grid_width):
			var terrain_height = float(terrain[y][x])
			var visual_height = terrain_height * 0.15
			
			var tile = _create_ground_tile(x, y, visual_height)
			board_root.add_child(tile)
			ground_tiles.append(tile)

func _create_ground_tile(x: int, y: int, visual_height: float) -> MeshInstance3D:
	var tile = MeshInstance3D.new()
	tile.name = "Tile_%d_%d" % [x, y]
	
	var mesh = BoxMesh.new()
	mesh.size = Vector3(cell_size * 0.95, 0.08, cell_size * 0.95)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.65, 0.58, 0.36, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	
	tile.mesh = mesh
	
	var world_pos = grid_to_world(x, y)
	tile.position = Vector3(world_pos.x, visual_height, world_pos.z)
	
	return tile

func _generate_markers():
	# Generate water source markers
	for source in level_data.waterSources:
		var x = int(source.x)
		var y = int(source.y)
		_create_source_marker(x, y)
	
	# Generate task area markers
	for area in level_data.taskAreas:
		var region = area.region
		var task_type = area.taskType
		
		for y in range(int(region.y1), int(region.y2) + 1):
			for x in range(int(region.x1), int(region.x2) + 1):
				if task_type == "victory":
					_create_victory_marker(x, y)
				elif task_type == "failure":
					_create_failure_marker(x, y)

func _create_source_marker(x: int, y: int):
	var marker = MeshInstance3D.new()
	marker.name = "SourceMarker_%d_%d" % [x, y]
	
	var mesh = BoxMesh.new()
	mesh.size = Vector3(cell_size * 0.85, 0.18, cell_size * 0.85)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.0, 0.4, 1.0, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	
	marker.mesh = mesh
	
	var world_pos = grid_to_world(x, y)
	var terrain_height = float(level_data.terrain[y][x])
	var visual_height = terrain_height * 0.15
	marker.position = Vector3(world_pos.x, visual_height + 0.15, world_pos.z)
	
	marker_root.add_child(marker)
	source_markers.append(marker)

func _create_victory_marker(x: int, y: int):
	var marker = MeshInstance3D.new()
	marker.name = "VictoryMarker_%d_%d" % [x, y]
	
	var mesh = BoxMesh.new()
	mesh.size = Vector3(cell_size * 0.85, 0.18, cell_size * 0.85)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.0, 0.9, 0.2, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	
	marker.mesh = mesh
	
	var world_pos = grid_to_world(x, y)
	var terrain_height = float(level_data.terrain[y][x])
	var visual_height = terrain_height * 0.15
	marker.position = Vector3(world_pos.x, visual_height + 0.15, world_pos.z)
	
	marker_root.add_child(marker)
	victory_markers.append(marker)

func _create_failure_marker(x: int, y: int):
	var marker = MeshInstance3D.new()
	marker.name = "FailureMarker_%d_%d" % [x, y]
	
	var mesh = BoxMesh.new()
	mesh.size = Vector3(cell_size * 0.85, 0.18, cell_size * 0.85)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.1, 0.1, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	
	marker.mesh = mesh
	
	var world_pos = grid_to_world(x, y)
	var terrain_height = float(level_data.terrain[y][x])
	var visual_height = terrain_height * 0.15
	marker.position = Vector3(world_pos.x, visual_height + 0.15, world_pos.z)
	
	marker_root.add_child(marker)
	failure_markers.append(marker)
