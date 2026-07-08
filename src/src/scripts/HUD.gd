extends Control

var main_node: Node

@onready var level_name_label: Label = $TopPanel/LevelNameLabel
@onready var state_label: Label = $TopPanel/StateLabel
@onready var time_label: Label = $TopPanel/TimeLabel
@onready var wall_count_label: Label = $TopPanel/WallCountLabel
@onready var action_button: Button = $ActionButton
@onready var result_panel: Panel = $ResultPanel
@onready var result_title_label: Label = $ResultPanel/ResultTitleLabel
@onready var retry_button: Button = $ResultPanel/RetryButton
@onready var next_button: Button = $ResultPanel/NextButton
@onready var top_panel: Panel = $TopPanel

func _ready():
	action_button.pressed.connect(_on_action_button_pressed)
	retry_button.pressed.connect(_on_retry_button_pressed)
	next_button.pressed.connect(_on_next_button_pressed)
	
	# 设置 mouse_filter，避免 UI 阻挡棋盘点击
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wall_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# 按钮需要正常响应点击
	action_button.mouse_filter = Control.MOUSE_FILTER_STOP
	retry_button.mouse_filter = Control.MOUSE_FILTER_STOP
	next_button.mouse_filter = Control.MOUSE_FILTER_STOP
	result_panel.mouse_filter = Control.MOUSE_FILTER_STOP

func setup(p_main_node: Node):
	main_node = p_main_node
	result_panel.visible = false
	next_button.visible = false
	_create_flow_legend()

func _create_flow_legend() -> void:
	# 流速图例面板 - 用于路演展示
	var legend_panel = Panel.new()
	legend_panel.name = "FlowLegend"
	legend_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legend_panel.position = Vector2(690, 10)
	legend_panel.size = Vector2(100, 130)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.4)
	legend_panel.add_theme_stylebox_override("panel", style)
	
	var title_label = Label.new()
	title_label.text = "流速图例"
	title_label.position = Vector2(10, 5)
	title_label.size = Vector2(80, 20)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	title_label.add_theme_font_size_override("font_size", 12)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legend_panel.add_child(title_label)
	
	# 颜色条：深蓝 → 天蓝 → 浅蓝
	var colors = [
		{"label": "慢", "color": Color(0.05, 0.1, 0.4, 1.0)},
		{"label": "中", "color": Color(0.15, 0.3, 0.65, 1.0)},
		{"label": "快", "color": Color(0.6, 0.75, 0.95, 1.0)}
	]
	
	for i in range(colors.size()):
		var box = ColorRect.new()
		box.name = "LegendColor_%d" % i
		box.position = Vector2(10, 35 + i * 30)
		box.size = Vector2(20, 20)
		box.color = colors[i]["color"]
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		legend_panel.add_child(box)
		
		var label = Label.new()
		label.text = colors[i]["label"]
		label.position = Vector2(38, 35 + i * 30)
		label.size = Vector2(50, 20)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_font_size_override("font_size", 12)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		legend_panel.add_child(label)
	
	add_child(legend_panel)

func update_level_name(level_name: String):
	level_name_label.text = "关卡名：" + level_name

func update_state(state: String):
	match state:
		"preparing":
			state_label.text = "状态：准备中"
			action_button.text = "开始"
		"simulating":
			state_label.text = "状态：水流模拟中……"
			action_button.text = "重置"
		"victory":
			state_label.text = "状态：胜利"
			action_button.text = "重试"
		"failure":
			state_label.text = "状态：失败"
			action_button.text = "重试"

func update_elapsed_time(time: float):
	time_label.text = "用时：" + "%.1f" % time + "s"

func update_wall_count(count: int):
	wall_count_label.text = "石墙：" + str(count)

func show_result(result: String):
	match result:
		"victory":
			result_title_label.text = "引水成功"
		"failure":
			result_title_label.text = "村子被淹了"
	result_panel.visible = true

func hide_result():
	result_panel.visible = false

func _on_action_button_pressed():
	if main_node and main_node.has_method("start_simulation") and main_node.has_method("reset_to_preparing"):
		if main_node.current_state == "preparing":
			main_node.start_simulation()
		else:
			main_node.reset_to_preparing()

func _on_retry_button_pressed():
	if main_node and main_node.has_method("reset_to_preparing"):
		main_node.reset_to_preparing()

func _on_next_button_pressed():
	pass
