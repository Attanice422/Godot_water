extends Button

signal delete_requested


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	delete_requested.emit()
