extends Control
## 大厅页（空壳）：创建房间 / 输组队码加入 —— 真实功能见子项目 3。本页不碰任何网络层 autoload。


func _ready() -> void:
	$BackButton.pressed.connect(_goto_main)
	$Center/Card/Box/CreateButton.pressed.connect(_goto_room)
	$Center/Card/Box/JoinButton.pressed.connect(_goto_room)
	$Center/Card/Box/CodeField.max_length = 6


func _goto_main() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _goto_room() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/room.tscn")
