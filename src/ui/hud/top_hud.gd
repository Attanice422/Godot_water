extends Control

@onready var state_value_label: Label = $Background/Margin/Content/LevelState/Value
@onready var hint_label: Label = $HintLabel


func show_preparing_hint() -> void:
	state_value_label.text = "准备中"
	hint_label.visible = true


func show_simulating_hint() -> void:
	state_value_label.text = "水流模拟中…"
	hint_label.visible = false
