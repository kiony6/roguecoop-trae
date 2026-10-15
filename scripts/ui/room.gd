extends Control
## 房间页：真实组队码 / 动态成员列表（大厅用户名，房主首位）/ 房主开局 / 离开房间。
## 本页只认 autoload Lobby，不直接触碰网络层。

const LobbyLib := preload("res://net/lobby.gd")


func _ready() -> void:
	$BackButton.pressed.connect(_on_leave)
	$Center/Card/Box/StartButton.pressed.connect(_on_start)
	Lobby.room_updated.connect(_on_room_updated)
	Lobby.room_failed.connect(_on_room_failed)
	if not Lobby.in_room():
		_goto_lobby.call_deferred()
		return
	_refresh()


func _refresh() -> void:
	var box: VBoxContainer = $Center/Card/Box
	box.get_node("Code").text = Lobby.room_code
	box.get_node("StartButton").visible = Lobby.is_host
	box.get_node("StartButton").text = "开始（%d 人）" % Lobby.members.size()
	box.get_node("TickHint").text = "房主点「开始」后全员进入同一张地图"
	var members: VBoxContainer = box.get_node("Members")
	for c in members.get_children():
		c.queue_free()
	for i in Lobby.members.size():
		var label := Label.new()
		label.text = "%s%s" % ["房主 · " if i == 0 else "队友 · ", Lobby.members[i]]
		if i != 0:
			label.theme_type_variation = &"Caption"
		members.add_child(label)


func _on_start() -> void:
	Lobby.start_run()


func _on_leave() -> void:
	Lobby.leave_room()
	_goto_lobby()


func _on_room_updated() -> void:
	if not Lobby.in_room():
		_goto_lobby()
		return
	if Lobby.room_state == LobbyLib.STATE.RUNNING:
		get_tree().change_scene_to_file("res://scenes/world.tscn")
		return
	_refresh()


func _on_room_failed(reason: String) -> void:
	$Center/Card/Box/TickHint.text = reason


func _goto_lobby() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")
