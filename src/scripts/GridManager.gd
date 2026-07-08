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
	return float(level_data.terrain[y][x]) * TERRAIN_HEIGHT_SCALE

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
	# 添加基准平面，形成3D高度参照
	_create_base_plane()
	
	for y in range(grid_height):
		for x in range(grid_width):
			var tile = _create_ground_tile(x, y)
			board_root.add_child(tile)
			ground_tiles.append(tile)

func _create_base_plane() -> void:
	var plane = MeshInstance3D.new()
	plane.name = "BasePlane"
	
	var mesh = BoxMesh.new()
	var total_width = grid_width * cell_size
	var total_height = grid_height * cell_size
	mesh.size = Vector3(total_width, 0.05, total_height)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.3, 0.2, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.roughness = 0.9
	mesh.material = material
	
	plane.mesh = mesh
	plane.position = Vector3(0, -0.03, 0)
	
	board_root.add_child(plane)

# 地形高度缩放系数，决定3D地形的视觉高度
const TERRAIN_HEIGHT_SCALE: float = 0.5

func _get_terrain_color(terrain_height: float) -> Color:
	# 根据高度返回渐变颜色：低处绿色 → 中段棕色 → 高处灰白
	var normalized = clamp(terrain_height / 6.0, 0.0, 1.0)
	
	if normalized < 0.33:
		# 低海拔：绿色 (草地)
		var t = normalized / 0.33
		return Color(0.25 + t * 0.15, 0.45 + t * 0.15, 0.18 + t * 0.05, 1.0)
	elif normalized < 0.66:
		# 中海拔：棕色 (泥土/岩石)
		var t = (normalized - 0.33) / 0.33
		return Color(0.55 + t * 0.15, 0.42 + t * 0.08, 0.25 + t * 0.05, 1.0)
	else:
		# 高海拔：灰白色 (山岩)
		var t = (normalized - 0.66) / 0.34
		return Color(0.6 + t * 0.25, 0.55 + t * 0.25, 0.5 + t * 0.3, 1.0)

func _create_ground_tile(x: int, y: int) -> MeshInstance3D:
	var tile = MeshInstance3D.new()
	tile.name = "Tile_%d_%d" % [x, y]
	
	var terrain_height = float(level_data.terrain[y][x])
	# 3D 柱体高度 = 地形值 * 缩放系数，最小高度 0.1 保证可见
	var column_height = max(terrain_height * TERRAIN_HEIGHT_SCALE, 0.1)
	
	var mesh = BoxMesh.new()
	mesh.size = Vector3(cell_size * 0.95, column_height, cell_size * 0.95)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = _get_terrain_color(terrain_height)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.roughness = 0.85
	mesh.material = material
	
	tile.mesh = mesh
	
	var world_pos = grid_to_world(x, y)
	# 柱体底部在 y=0，顶部在 column_height
	tile.position = Vector3(world_pos.x, column_height / 2.0, world_pos.z)
	
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

func _create_marker_material(base_color: Color, emissive_color: Color) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = base_color
	material.emission = emissive_color
	material.emission_energy = 0.3
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.roughness = 0.5
	return material

func _create_source_marker(x: int, y: int):
	var marker = MeshInstance3D.new()
	marker.name = "SourceMarker_%d_%d" % [x, y]
	
	var mesh = BoxMesh.new()
	mesh.size = Vector3(cell_size * 0.85, 0.2, cell_size * 0.85)
	
	mesh.material = _create_marker_material(Color(0.0, 0.5, 1.0, 1.0), Color(0.1, 0.3, 0.9))
	
	marker.mesh = mesh
	
	var world_pos = grid_to_world(x, y)
	var visual_height = get_visual_height(x, y)
	marker.position = Vector3(world_pos.x, visual_height + 0.15, world_pos.z)
	
	marker_root.add_child(marker)
	source_markers.append(marker)

func _create_victory_marker(x: int, y: int):
	var marker = MeshInstance3D.new()
	marker.name = "VictoryMarker_%d_%d" % [x, y]
	
	var mesh = BoxMesh.new()
	mesh.size = Vector3(cell_size * 0.85, 0.2, cell_size * 0.85)
	
	mesh.material = _create_marker_material(Color(0.0, 0.85, 0.2, 1.0), Color(0.0, 0.5, 0.1))
	
	marker.mesh = mesh
	
	var world_pos = grid_to_world(x, y)
	var visual_height = get_visual_height(x, y)
	marker.position = Vector3(world_pos.x, visual_height + 0.15, world_pos.z)
	
	marker_root.add_child(marker)
	victory_markers.append(marker)

func _create_failure_marker(x: int, y: int):
	var marker = MeshInstance3D.new()
	marker.name = "FailureMarker_%d_%d" % [x, y]
	
	var mesh = BoxMesh.new()
	mesh.size = Vector3(cell_size * 0.85, 0.2, cell_size * 0.85)
	
	mesh.material = _create_marker_material(Color(1.0, 0.15, 0.15, 1.0), Color(0.7, 0.05, 0.05))
	
	marker.mesh = mesh
	
	var world_pos = grid_to_world(x, y)
	var visual_height = get_visual_height(x, y)
	marker.position = Vector3(world_pos.x, visual_height + 0.15, world_pos.z)
	
	marker_root.add_child(marker)
	failure_markers.append(marker)
