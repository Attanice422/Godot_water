extends Node3D

const STATE_PREPARING = "preparing"
const STATE_SIMULATING = "simulating"
const STATE_VICTORY = "victory"
const STATE_FAILURE = "failure"

@onready var grid_manager: Node = $GridManager
@onready var board_root: Node3D = $BoardRoot
@onready var block_root: Node3D = $BlockRoot
@onready var water_root: Node3D = $WaterRoot
@onready var marker_root: Node3D = $MarkerRoot
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var hud: Control = $UI/HUDRoot
@onready var block_placement: Node = $BlockPlacement
@onready var water_simulator: Node = $WaterSimulator
@onready var task_area_manager: Node = $TaskAreaManager

var current_state: String = STATE_PREPARING
var elapsed_time: float = 0.0
var level_data: Dictionary = {}
var wall_remaining: int = 0

func _ready():
	print("Main scene loaded")
	print("Godot water diversion MVP initialized")
	
	level_data = load_level_config("res://data/levels/level_001.json")
	if not validate_level_config(level_data):
		print("Invalid level config")
		return
	
	print_level_info(level_data)
	
	wall_remaining = int(level_data.inventory.wall)
	
	setup_grid_manager()
	grid_manager.load_level(level_data)
	
	print("BoardRoot children after grid load: ", board_root.get_child_count())
	print("MarkerRoot children after grid load: ", marker_root.get_child_count())
	
	setup_camera()
	
	setup_hud()
	
	block_placement.setup(self, grid_manager, block_root, wall_remaining)
	
	water_simulator.setup(self, grid_manager, water_root, level_data)
	
	task_area_manager.setup(self, water_simulator, level_data)
	
	set_state(STATE_PREPARING)

func set_wall_remaining(count: int) -> void:
	wall_remaining = count
	hud.update_wall_count(wall_remaining)

func _process(delta):
	if current_state == STATE_SIMULATING:
		elapsed_time += delta
		hud.update_elapsed_time(elapsed_time)
		task_area_manager.update_task_areas(delta)

func load_level_config(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		print("Failed to open level file")
		return {}
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_text)
	if parse_result != OK:
		print("Failed to parse level JSON")
		return {}
	
	return json.data

func validate_level_config(config: Dictionary) -> bool:
	if not config.has("terrain") or config.terrain.size() != 12:
		return false
	
	for row in config.terrain:
		if row.size() != 16:
			return false
	
	return true

func print_level_info(config: Dictionary):
	print("Level loaded: ", config.levelId)
	print("Level name: ", config.name)
	print("Grid size: ", config.gridWidth, " x ", config.gridHeight)
	print("Cell size: ", config.cellSize)
	print("Wall count: ", config.inventory.wall)
	print("Water source count: ", config.waterSources.size())
	print("Task area count: ", config.taskAreas.size())
	print("Terrain rows: ", config.terrain.size())
	print("Terrain cols of first row: ", config.terrain[0].size())

func setup_grid_manager():
	if grid_manager.has_method("setup"):
		grid_manager.setup(board_root, marker_root)

func setup_camera():
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 22.0
	
	# 调整为更低的俯视角度，突出3D地形高度
	camera.global_position = Vector3(1, 12, 16)
	camera.look_at(Vector3(0, 1.5, 0), Vector3.UP)
	
	print("Camera setup done")
	print("Camera current: ", camera.current)
	print("Camera projection: ", camera.projection)
	print("Camera size: ", camera.size)
	print("Camera global position: ", camera.global_position)
	
	# 添加环境光，增强3D立体感
	_add_environment()

func setup_hud():
	hud.setup(self)
	hud.update_level_name(level_data.name)
	hud.update_wall_count(wall_remaining)

func set_state(new_state: String) -> void:
	current_state = new_state
	hud.update_state(current_state)
	
	if current_state == STATE_VICTORY:
		hud.show_result("victory")
	elif current_state == STATE_FAILURE:
		hud.show_result("failure")
	else:
		hud.hide_result()

func start_simulation() -> void:
	if current_state != STATE_PREPARING:
		return
	print("start_simulation called")
	elapsed_time = 0.0
	water_simulator.reset_water()
	water_simulator.start_simulation()
	set_state(STATE_SIMULATING)

func reset_to_preparing() -> void:
	print("reset_to_preparing called")
	elapsed_time = 0.0
	water_simulator.stop_simulation()
	water_simulator.reset_water()
	task_area_manager.reset()
	hud.update_elapsed_time(elapsed_time)
	set_state(STATE_PREPARING)
	print("current_state after reset: ", current_state)

func trigger_victory() -> void:
	print("trigger_victory called")
	water_simulator.stop_simulation()
	set_state(STATE_VICTORY)

func trigger_failure() -> void:
	print("trigger_failure called")
	water_simulator.stop_simulation()
	set_state(STATE_FAILURE)

func is_editable() -> bool:
	return current_state == STATE_PREPARING

func _add_environment() -> void:
	var world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.35, 0.45, 0.55, 1.0)
	
	# 环境光设置，让暗面也有光照，凸显3D立体感
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.28, 0.35, 1.0)
	env.ambient_light_energy = 0.6
	
	world_env.environment = env
	add_child(world_env)
	
	print("WorldEnvironment added")
