extends Control
## 房间页：真实组队码 / 动态成员列表（大厅用户名，房主首位）/ 房主选关与选难度 /
## 房主开局 / 离开房间。本页只认 autoload Lobby，不直接触碰网络层。

const LobbyLib := preload("res://net/lobby.gd")
const Levels := preload("res://sim/levels.gd")

var _level_buttons: Array[Button] = []
var _diff_buttons: Array[Button] = []


func _ready() -> void:
	$BackButton.pressed.connect(_on_leave)
	$Center/Card/Box/StartButton.pressed.connect(_on_start)
	Lobby.room_updated.connect(_on_room_updated)
	Lobby.room_failed.connect(_on_room_failed)
	Lobby.room_config_updated.connect(_refresh_config)
	Lobby.progress_updated.connect(_refresh_config)
	_build_config()
	if not Lobby.in_room():
		_goto_lobby.call_deferred()
		return
	Lobby.request_progress()
	_refresh()


func _build_config() -> void:
	var level_row: HBoxContainer = $Center/Card/Box/Config/LevelRow
	var diff_row: HBoxContainer = $Center/Card/Box/Config/DiffRow
	for id in range(Levels.level_count()):
		var btn := Button.new()
		btn.pressed.connect(_on_level_pressed.bind(id))
		level_row.add_child(btn)
		_level_buttons.append(btn)
	for id in range(Levels.difficulty_count()):
		var btn := Button.new()
		btn.pressed.connect(_on_diff_pressed.bind(id))
		diff_row.add_child(btn)
		_diff_buttons.append(btn)


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
	_refresh_config()


func _refresh_config() -> void:
	var cfg: VBoxContainer = $Center/Card/Box/Config
	cfg.visible = Lobby.can_use() and Lobby.in_room()
	var editable := Lobby.is_host  # 只有房主能改配置；非房主只读
	var suffix := "" if editable else "（房主选择）"
	$Center/Card/Box/Config/LevelLabel.text = "关卡%s" % suffix
	$Center/Card/Box/Config/DiffLabel.text = "难度%s" % suffix
	for id in _level_buttons.size():
		var btn := _level_buttons[id]
		var unlocked := _is_level_unlocked(id)
		btn.text = Levels.name_of_level(id)
		btn.disabled = not editable or not unlocked
		btn.theme_type_variation = &"PrimaryButton" if id == Lobby.level_id else &""
		if not unlocked:
			btn.tooltip_text = "通关上一关后解锁"
	for id in _diff_buttons.size():
		var btn := _diff_buttons[id]
		btn.text = Levels.name_of_difficulty(id)
		btn.disabled = not editable
		btn.theme_type_variation = &"PrimaryButton" if id == Lobby.difficulty_id else &""


func _is_level_unlocked(id: int) -> bool:
	## 首关（id 0）恒解锁；其余关卡需先通关上一关。进度来自服务端账本。
	return id == 0 or Lobby.cleared_levels.has(id) or Lobby.cleared_levels.has(id - 1)


func _on_level_pressed(id: int) -> void:
	Lobby.set_config(id, Lobby.difficulty_id)


func _on_diff_pressed(id: int) -> void:
	Lobby.set_config(Lobby.level_id, id)


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
