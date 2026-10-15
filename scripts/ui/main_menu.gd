extends Control
## 主菜单（= run/main_scene）：联机大厅为主入口，局域网直连为次级。
## 命令行透传：仅当启动参数显式要求 `--auto=join` 时，首帧直达直连页（一次性，返回主菜单后不再弹回）。
## `--ip=` / `--port=` / `--transport=` 只作预填，由直连页自行消费，不劫持主菜单。


func _ready() -> void:
	$Center/Box/LobbyButton.pressed.connect(_on_lobby_pressed)
	$Center/Box/DirectButton.pressed.connect(_on_direct_pressed)
	$Center/Box/Links/LeaderboardButton.pressed.connect(_on_leaderboard_pressed)
	$Center/Box/Links/SettingsButton.pressed.connect(_on_settings_pressed)
	if Boot.take_auto_join_pending():
		_on_direct_pressed.call_deferred()


func _on_lobby_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/login.tscn")


func _on_direct_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/direct_connect.tscn")


func _on_leaderboard_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/leaderboard.tscn")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/settings.tscn")
