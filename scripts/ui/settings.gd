extends Control
## 设置页（空壳）：当前版本无可用设置项。


func _ready() -> void:
	$BackButton.pressed.connect(_goto_main)


func _goto_main() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
