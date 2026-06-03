extends Control

@onready var depth_slider = $DepthRow/DepthSlider
@onready var depth_value  = $DepthRow/DepthValue

func _ready():
	depth_slider.value = GameSettings.beaker_capacity
	depth_value.text   = str(GameSettings.beaker_capacity)

func _on_depth_changed(value: float):
	GameSettings.beaker_capacity = int(value)
	depth_value.text = str(int(value))

func _on_hanoi_pressed():
	get_tree().change_scene_to_file("res://scenes/hanoi.tscn")

func _on_beaker_pressed():
	get_tree().change_scene_to_file("res://scenes/beaker.tscn")
