extends Button

signal hint_requested


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	hint_requested.emit()
