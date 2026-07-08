extends Window

signal retry_requested
signal hint_requested

@onready var title_label: Label = $Content/TitleLabel
@onready var retry_button: Button = $Content/ButtonRow/RetryButton
@onready var hint_button = $Content/ButtonRow/HintButton


func _ready() -> void:
	retry_button.pressed.connect(_on_retry_pressed)
	hint_button.hint_requested.connect(_on_hint_requested)


func set_title_text(value: String) -> void:
	title_label.text = value


func _on_retry_pressed() -> void:
	retry_requested.emit()


func _on_hint_requested() -> void:
	hint_requested.emit()
