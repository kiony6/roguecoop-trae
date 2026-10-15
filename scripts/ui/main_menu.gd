extends Control
## 主菜单（= run/main_scene）：联机大厅为主入口，局域网直连为次级。
## 命令行透传：带 --ip= / --port= / --transport= / --auto= 任一即直接切到直连页，由它消费这些参数。

const DIRECT_ARGS: Array = ["--ip=", "--port=", "--transport=", "--auto="]


func _ready() -> void:
	$Center/Box/LobbyButton.pressed.connect(_on_lobby_pressed)
	$Center/Box/DirectButton.pressed.connect(_on_direct_pressed)
	$Center/Box/Links/LeaderboardButton.pressed.connect(_on_leaderboard_pressed)
	$Center/Box/Links/SettingsButton.pressed.connect(_on_settings_pressed)
	if _has_direct_args():
		_on_direct_pressed.call_deferred()


func _has_direct_args() -> bool:
	for a in OS.get_cmdline_user_args():
		for prefix in DIRECT_ARGS:
			if a.begins_with(prefix):
				return true
	return false


func _on_lobby_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/login.tscn")


func _on_direct_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/direct_connect.tscn")


func _on_leaderboard_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/leaderboard.tscn")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/settings.tscn")
