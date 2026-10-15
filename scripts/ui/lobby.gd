extends Control
## 大厅页：显示已登录身份 + 退出登录；创建 / 加入房间仍为占位（子项目 3）。本页不碰网络层 autoload。


func _ready() -> void:
	$BackButton.pressed.connect(_goto_main)
	$Center/Card/Box/CreateButton.pressed.connect(_goto_room)
	$Center/Card/Box/JoinButton.pressed.connect(_goto_room)
	$Center/Card/Box/CodeField.max_length = 6
	$Center/Card/Box/LogoutButton.pressed.connect(_on_logout)
	_update_who()


func _update_who() -> void:
	$Center/Card/Box/Who.text = "已登录：%s" % (Account.username if Account.is_logged_in() else "游客")


func _on_logout() -> void:
	Account.logout()
	_update_who()


func _goto_main() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _goto_room() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/room.tscn")
