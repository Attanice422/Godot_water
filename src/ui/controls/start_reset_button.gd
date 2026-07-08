extends Button

signal start_requested
signal reset_requested

var is_simulating_preview := false


func _ready() -> void:
	pressed.connect(_on_pressed)
	_refresh_text()


func _on_pressed() -> void:
	if is_simulating_preview:
		is_simulating_preview = false
		reset_requested.emit()
	else:
		is_simulating_preview = true
		start_requested.emit()
	_refresh_text()


func reset_to_preparing() -> void:
	is_simulating_preview = false
	_refresh_text()


func _refresh_text() -> void:
	text = "重置" if is_simulating_preview else "开始"
