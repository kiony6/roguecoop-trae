extends Control
## 排行榜页（空壳）：单人历史最佳榜，指标 = 最高到达波次 —— 真实功能见子项目 4。本页不碰任何网络层 autoload。


func _ready() -> void:
	$BackButton.pressed.connect(_goto_main)


func _goto_main() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
