extends Button

signal rotate_requested


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	rotate_requested.emit()
