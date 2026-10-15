extends Control
## 主菜单（= run/main_scene）：联机大厅为主入口。
## 局域网直连通道与 `--auto=join` 命令行透传已随「去除局域网联机功能」一并移除。


func _ready() -> void:
	Account.disconnect_lobby()  # 偏离 6：返回主菜单即断开大厅，主菜单恒为未登录
	$Center/Box/LobbyButton.pressed.connect(_on_lobby_pressed)
	$Center/Box/Links/LeaderboardButton.pressed.connect(_on_leaderboard_pressed)
	$Center/Box/Links/SettingsButton.pressed.connect(_on_settings_pressed)


func _on_lobby_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/login.tscn")


func _on_leaderboard_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/leaderboard.tscn")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/settings.tscn")
