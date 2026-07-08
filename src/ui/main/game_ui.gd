extends Control

@onready var top_hud = $TopHUD
@onready var start_reset_button = $StartResetButton
@onready var hint_button = $HintButton
@onready var hint_dialog: AcceptDialog = $HintDialog


func _ready() -> void:
	start_reset_button.start_requested.connect(_on_start_requested)
	start_reset_button.reset_requested.connect(_on_reset_requested)
	hint_button.hint_requested.connect(_on_hint_requested)
	top_hud.show_preparing_hint()


func _on_start_requested() -> void:
	top_hud.show_simulating_hint()


func _on_reset_requested() -> void:
	top_hud.show_preparing_hint()


func _on_hint_requested() -> void:
	hint_dialog.popup_centered()
