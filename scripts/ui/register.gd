extends Control
## 注册页（空壳）：客户端本地派生 verifier，密码不过网线 —— 真实功能见子项目 2。


func _ready() -> void:
	$BackButton.pressed.connect(_goto_login)
	$Center/Card/Box/BackToLogin.pressed.connect(_goto_login)


func _goto_login() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/login.tscn")
