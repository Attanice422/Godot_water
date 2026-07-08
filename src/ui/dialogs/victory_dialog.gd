extends Window

signal next_level_requested

@onready var title_label: Label = $Content/TitleLabel
@onready var time_value_label: Label = $Content/Stats/TimeRow/TimeValue
@onready var resource_value_label: Label = $Content/Stats/ResourceRow/ResourceValue
@onready var money_value_label: Label = $Content/Stats/MoneyRow/MoneyValue
@onready var next_level_button: Button = $Content/ButtonRow/NextLevelButton


func _ready() -> void:
	next_level_button.pressed.connect(_on_next_level_pressed)


func set_title_text(value: String) -> void:
	title_label.text = value


func set_stats(elapsed_seconds: int, resource_count: int, money_cost: int) -> void:
	time_value_label.text = str(elapsed_seconds)
	resource_value_label.text = str(resource_count)
	money_value_label.text = str(money_cost)


func _on_next_level_pressed() -> void:
	next_level_requested.emit()
