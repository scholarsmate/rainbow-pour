extends Control

func _on_hanoi_pressed():
	get_tree().change_scene_to_file("res://scenes/hanoi.tscn")

func _on_beaker_pressed():
	get_tree().change_scene_to_file("res://scenes/beaker.tscn")
