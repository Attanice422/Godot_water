extends Node3D

var main_node: Node
var grid_manager: Node
var water_root: Node3D
var level_data: Dictionary

var grid_width: int = 16
var grid_height: int = 12
var cell_size: float = 1.0
var source_flow: float = 0.6
var diffusion_coefficient: float = 2.0
var max_water_depth: float = 3.0

var simulation_running: bool = false
var simulation_step: float = 0.1
var accumulator: float = 0.0
var debug_timer: float = 0.0

var terrain_heights: Array = []  # [y][x]
var water_volumes: Array = []     # [y][x]
var water_heights: Array = []     # [y][x]
var delta_volumes: Array = []     # [y][x] - for safe update
var flow_speed: Array = []        # [y][x] - 流速追踪

var water_sources: Array = []

func setup(p_main: Node, p_grid_manager: Node, p_water_root: Node3D, p_level_data: Dictionary) -> void:
	main_node = p_main
	grid_manager = p_grid_manager
	water_root = p_water_root
	level_data = p_level_data
	
	grid_width = int(level_data.gridWidth)
	grid_height = int(level_data.gridHeight)
	cell_size = float(level_data.cellSize)
	source_flow = float(level_data.sourceFlow)
	diffusion_coefficient = float(level_data.diffusionCoefficient)
	max_water_depth = float(level_data.maxWaterDepth)
	water_sources = level_data.waterSources
	
	# Initialize data structures
	_init_data_structures()
	
	print("WaterSimulator setup done")
	print("gridWidth: ", grid_width)
	print("gridHeight: ", grid_height)
	print("sourceFlow: ", source_flow)
	print("diffusionCoefficient: ", diffusion_coefficient)
	print("maxWaterDepth: ", max_water_depth)
	print("waterSources count: ", water_sources.size())

func start_simulation() -> void:
	simulation_running = true
	accumulator = 0.0
	debug_timer = 0.0
	print("Water simulation started")
	print("simulation_running: ", simulation_running)

func stop_simulation() -> void:
	simulation_running = false
	accumulator = 0.0
	debug_timer = 0.0
	print("Water simulation stopped")

func reset_water() -> void:
	stop_simulation()
	
	# Reset all water volumes to 0
	for y in range(grid_height):
		for x in range(grid_width):
			water_volumes[y][x] = 0.0
			delta_volumes[y][x] = 0.0
			water_heights[y][x] = terrain_heights[y][x]
			flow_speed[y][x] = 0.0
	
	_clear_visuals()
	print("Water simulation reset")
	print("simulation_running after reset: ", simulation_running)
	print("WaterRoot child count after reset: ", water_root.get_child_count())

func clear_visuals() -> void:
	_clear_visuals()

func get_water_volume(x: int, y: int) -> float:
	if x < 0 or x >= grid_width or y < 0 or y >= grid_height:
		return 0.0
	return water_volumes[y][x]

func get_water_height(x: int, y: int) -> float:
	if x < 0 or x >= grid_width or y < 0 or y >= grid_height:
		return 0.0
	return water_heights[y][x]

func get_flow_speed(x: int, y: int) -> float:
	if x < 0 or x >= grid_width or y < 0 or y >= grid_height:
		return 0.0
	return flow_speed[y][x]

func is_running() -> bool:
	return simulation_running

func _init_data_structures() -> void:
	terrain_heights.clear()
	water_volumes.clear()
	water_heights.clear()
	delta_volumes.clear()
	flow_speed.clear()
	
	for y in range(grid_height):
		var terrain_row: Array = []
		var volume_row: Array = []
		var height_row: Array = []
		var delta_row: Array = []
		var speed_row: Array = []
		
		for x in range(grid_width):
			var terrain_h = float(level_data.terrain[y][x])
			terrain_row.append(terrain_h)
			volume_row.append(0.0)
			height_row.append(terrain_h)
			delta_row.append(0.0)
			speed_row.append(0.0)
		
		terrain_heights.append(terrain_row)
		water_volumes.append(volume_row)
		water_heights.append(height_row)
		delta_volumes.append(delta_row)
		flow_speed.append(speed_row)

func _clear_visuals() -> void:
	for child in water_root.get_children():
		child.queue_free()

func _process(delta: float) -> void:
	if not simulation_running:
		return
	
	accumulator += delta
	debug_timer += delta
	
	# Fixed time step simulation
	while accumulator >= simulation_step:
		_simulate_step(simulation_step)
		accumulator -= simulation_step
	
	# Update visuals every frame
	_update_visuals()
	
	# Debug output every 1 second
	if debug_timer >= 1.0:
		_debug_print_summary()
		debug_timer = 0.0

func _simulate_step(dt: float) -> void:
	# 1. Source injection
	_inject_water_from_sources(dt)
	
	# 2. Update water heights
	_update_water_heights()
	
	# 3. Calculate diffusion (store in delta_volumes)
	_calculate_diffusion(dt)
	
	# 4. Apply delta volumes
	_apply_delta_volumes()
	
	# 5. Update water heights again
	_update_water_heights()

func _inject_water_from_sources(dt: float) -> void:
	for source in water_sources:
		var x = int(source.x)
		var y = int(source.y)
		var max_flow = float(source.maxFlow)
		
		if not _is_valid_water_cell(x, y):
			continue
		
		water_volumes[y][x] += max_flow * dt
		water_volumes[y][x] = min(water_volumes[y][x], max_water_depth)

func _update_water_heights() -> void:
	for y in range(grid_height):
		for x in range(grid_width):
			water_heights[y][x] = terrain_heights[y][x] + water_volumes[y][x]

func _calculate_diffusion(dt: float) -> void:
	# Reset delta_volumes and flow_speed
	for y in range(grid_height):
		for x in range(grid_width):
			delta_volumes[y][x] = 0.0
			flow_speed[y][x] = 0.0
	
	# 地形高度缩放系数（与 GridManager 一致），用于计算真实地势差
	const TERRAIN_HEIGHT_SCALE: float = 0.5
	
	# Check 4 directions for each cell
	for y in range(grid_height):
		for x in range(grid_width):
			if not _is_valid_water_cell(x, y):
				continue
			
			var current_height = water_heights[y][x]
			var current_volume = water_volumes[y][x]
			
			if current_volume <= 0.001:
				continue
			
			# Check 4 neighbors: right, left, down, up
			var neighbors = [
				Vector2i(x + 1, y),
				Vector2i(x - 1, y),
				Vector2i(x, y + 1),
				Vector2i(x, y - 1)
			]
			
			for neighbor in neighbors:
				var nx = neighbor.x
				var ny = neighbor.y
				
				if not _is_valid_water_cell(nx, ny):
					continue
				
				if grid_manager.has_obstacle(nx, ny):
					continue
				
				var neighbor_height = water_heights[ny][nx]
				
				if current_height > neighbor_height:
					var height_diff = current_height - neighbor_height
					# 地势差放大：结合地形高度的真实3D差异
					var terrain_diff = (terrain_heights[y][x] - terrain_heights[ny][nx]) * TERRAIN_HEIGHT_SCALE
					var effective_diff = height_diff + terrain_diff * 0.5
					var flow = effective_diff * diffusion_coefficient * dt * 0.25
					flow = min(flow, current_volume / 4.0)
					
					delta_volumes[y][x] -= flow
					delta_volumes[ny][nx] += flow
					# 流速记录：累加流出量
					flow_speed[y][x] += flow

func _apply_delta_volumes() -> void:
	for y in range(grid_height):
		for x in range(grid_width):
			water_volumes[y][x] += delta_volumes[y][x]
			water_volumes[y][x] = clamp(water_volumes[y][x], 0.0, max_water_depth)

func _is_valid_water_cell(x: int, y: int) -> bool:
	if x < 0 or x >= grid_width or y < 0 or y >= grid_height:
		return false
	if grid_manager.has_obstacle(x, y):
		return false
	return true

func _update_visuals() -> void:
	_clear_visuals()
	
	for y in range(grid_height):
		for x in range(grid_width):
			var volume = water_volumes[y][x]
			
			if volume <= 0.02:
				continue
			
			if grid_manager.has_obstacle(x, y):
				continue
			
			_create_water_visual(x, y, volume, flow_speed[y][x])

# 根据流速返回颜色：慢速深蓝 → 中速蓝 → 快速浅蓝/白
func _get_flow_color(speed: float) -> Color:
	var normalized = clamp(speed / 0.15, 0.0, 1.0)
	if normalized < 0.3:
		# 慢速：深蓝
		var t = normalized / 0.3
		return Color(0.05 + t * 0.1, 0.1 + t * 0.15, 0.4 + t * 0.2, 0.75)
	elif normalized < 0.7:
		# 中速：天蓝
		var t = (normalized - 0.3) / 0.4
		return Color(0.15 + t * 0.2, 0.3 + t * 0.3, 0.65 + t * 0.2, 0.75)
	else:
		# 快速：浅蓝偏白
		var t = (normalized - 0.7) / 0.3
		return Color(0.35 + t * 0.45, 0.6 + t * 0.3, 0.85 + t * 0.15, 0.75)

func _create_water_visual(x: int, y: int, volume: float, speed: float) -> void:
	var world_pos = grid_manager.grid_to_world(x, y)
	var visual_height = grid_manager.get_visual_height(x, y)
	
	var water = MeshInstance3D.new()
	water.name = "Water_%d_%d" % [x, y]
	
	var mesh_height = max(0.05, volume * 0.4)
	var mesh = BoxMesh.new()
	mesh.size = Vector3(cell_size * 0.8, mesh_height, cell_size * 0.8)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = _get_flow_color(speed)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.3
	material.metallic = 0.1
	mesh.material = material
	
	water.mesh = mesh
	# 水面放在地形柱体顶部
	water.position = Vector3(world_pos.x, visual_height + mesh_height / 2.0 + 0.02, world_pos.z)
	
	water_root.add_child(water)

func _debug_print_summary() -> void:
	var visible_count = 0
	var source_volume = 0.0
	var max_speed = 0.0
	var total_flow = 0.0
	
	for y in range(grid_height):
		for x in range(grid_width):
			if water_volumes[y][x] > 0.02:
				visible_count += 1
			if flow_speed[y][x] > max_speed:
				max_speed = flow_speed[y][x]
			total_flow += flow_speed[y][x]
	
	for source in water_sources:
		var x = int(source.x)
		var y = int(source.y)
		if _is_valid_water_cell(x, y):
			source_volume = water_volumes[y][x]
			break
	
	print("Total visible water cells: ", visible_count)
	print("Source cell volume: ", source_volume)
	print("Max flow speed: %.5f | Total flow: %.5f" % [max_speed, total_flow])
