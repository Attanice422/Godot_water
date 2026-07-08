extends Node3D

var main_node: Node
var water_simulator: Node
var level_data: Dictionary
var task_areas: Array = []
var area_timers: Dictionary = {}
var debug_timer: float = 0.0

func setup(p_main: Node, p_water_simulator: Node, p_level_data: Dictionary) -> void:
	main_node = p_main
	water_simulator = p_water_simulator
	level_data = p_level_data
	task_areas = level_data.taskAreas
	
	print("TaskAreaManager setup done")
	print("task area count: ", task_areas.size())
	
	for task_area in task_areas:
		var area_id = task_area.areaId
		var task_type = task_area.taskType
		area_timers[area_id] = 0.0
		print("Task area loaded: ", area_id, " ", task_type)

func reset() -> void:
	for area_id in area_timers:
		area_timers[area_id] = 0.0

func update_task_areas(delta: float) -> void:
	# 只在模拟中执行，结算后 main_node._process 不会再调用此函数
	debug_timer += delta
	
	# 先检查所有 failure 任务
	for task_area in task_areas:
		if task_area.taskType == "failure":
			if _check_task_area(task_area, delta):
				print("Failure task triggered: ", task_area.areaId)
				main_node.trigger_failure()
				return
	
	# 再检查所有 victory 任务
	for task_area in task_areas:
		if task_area.taskType == "victory":
			if _check_task_area(task_area, delta):
				print("Victory task triggered: ", task_area.areaId)
				main_node.trigger_victory()
				return
	
	# 每隔 1 秒打印一次调试信息
	if debug_timer >= 1.0:
		debug_timer = 0.0
		print("[Tune] elapsed_time: ", main_node.elapsed_time, " state: ", main_node.current_state)
		for task_area in task_areas:
			var area_id = task_area.areaId
			var metric = get_area_metric(task_area)
			var timer = area_timers[area_id]
			var duration = float(task_area.duration)
			print("[Tune] Area ", area_id, " metric: %.3f" % metric, " timer: %.2f" % timer, " / ", duration)

func get_area_metric(task_area: Dictionary) -> float:
	var region = task_area.region
	var x1 = int(region.x1)
	var y1 = int(region.y1)
	var x2 = int(region.x2)
	var y2 = int(region.y2)
	
	var max_volume = 0.0
	for y in range(y1, y2 + 1):
		for x in range(x1, x2 + 1):
			var volume = water_simulator.get_water_volume(x, y)
			if volume > max_volume:
				max_volume = volume
	
	return max_volume

func _check_task_area(task_area: Dictionary, delta: float) -> bool:
	var area_id = task_area.areaId
	var threshold = float(task_area.threshold)
	var compare = task_area.compare
	var duration = float(task_area.duration)
	
	var metric = get_area_metric(task_area)
	
	if _compare(metric, threshold, compare):
		area_timers[area_id] += delta
	else:
		area_timers[area_id] = 0.0
	
	return area_timers[area_id] >= duration

func _compare(value: float, threshold: float, compare: String) -> bool:
	match compare:
		">=":
			return value >= threshold
		">":
			return value > threshold
		"<=":
			return value <= threshold
		"<":
			return value < threshold
	
	return false
