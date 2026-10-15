extends Control
## 登录页（空壳）：账号系统见子项目 2。本页只做版式与导航，不碰任何网络层 autoload。


func _ready() -> void:
	$BackButton.pressed.connect(_goto.bind("res://scenes/main.tscn"))
	$Center/Card/Box/PreviewButton.pressed.connect(_goto.bind("res://scenes/ui/lobby.tscn"))
	$Center/Card/Box/RegisterButton.pressed.connect(_goto.bind("res://scenes/ui/register.tscn"))


func _goto(path: String) -> void:
	get_tree().change_scene_to_file(path)
