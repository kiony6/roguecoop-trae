extends Control
## 大厅页：显示已登录身份 + 创建 / 加入房间（组队码）+ 退出登录。
## 本页只认 autoload Lobby / Account，不直接触碰网络层。

const LobbyLib := preload("res://net/lobby.gd")


func _ready() -> void:
	$BackButton.pressed.connect(_goto_main)
	$Center/Card/Box/CreateButton.pressed.connect(_on_create)
	$Center/Card/Box/JoinButton.pressed.connect(_on_join)
	$Center/Card/Box/CodeField.max_length = 6
	$Center/Card/Box/LogoutButton.pressed.connect(_on_logout)
	$Center/Card/Box/LeaderboardButton.pressed.connect(_on_leaderboard)
	Lobby.room_updated.connect(_on_room_updated)
	Lobby.room_failed.connect(_on_room_failed)
	_update_who()
	_set_status("")


func _update_who() -> void:
	var who := Account.username if Account.is_logged_in() else "游客"
	$Center/Card/Box/Who.text = "已登录：%s" % who
	$Badge.text = who


func _set_status(text: String) -> void:
	$Center/Card/Box/Status.text = text


func _on_create() -> void:
	_set_status("正在创建房间…")
	Lobby.create_room()


func _on_join() -> void:
	var field := $Center/Card/Box/CodeField as LineEdit
	var code := field.text.strip_edges()
	_set_status("正在加入 %s…" % code)
	Lobby.join_room(code)


func _on_logout() -> void:
	Account.logout()
	_update_who()
	_set_status("已退出登录")


func _on_leaderboard() -> void:
	## 保持大厅连接跳到排行榜页（该页据此拉取在线榜数据）。
	get_tree().change_scene_to_file("res://scenes/ui/leaderboard.tscn")


func _on_room_updated() -> void:
	if not Lobby.in_room():
		return
	if Lobby.room_state == LobbyLib.STATE.RUNNING:
		get_tree().change_scene_to_file("res://scenes/world.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/ui/room.tscn")


func _on_room_failed(reason: String) -> void:
	_set_status(reason)


func _goto_main() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
