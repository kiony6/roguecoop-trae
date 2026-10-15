extends Control
## 房间页（空壳）：组队码为视觉焦点，成员列表为静态样例 —— 真实功能见子项目 3。本页不碰任何网络层 autoload。


func _ready() -> void:
	$BackButton.pressed.connect(_leave)


func _leave() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")
