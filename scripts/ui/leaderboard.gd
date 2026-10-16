extends Control
## 排行榜页（M7）：双榜（波次榜 / 技能榜）+ 难度筛选器（默认普通，仅波次榜可见）。
## 数据经联机大厅专服拉取（Lobby.request_leaderboard → Net.leaderboard_data）；
## 未登录 / 未连大厅时显示空态，不发 RPC。

const Protocol := preload("res://net/protocol.gd")
const Levels := preload("res://sim/levels.gd")

const WAVE_HEADERS := ["排名", "玩家", "最高波次", "击杀", "存活时长", "Boss数"]
const SKILL_HEADERS := ["排名", "玩家", "解锁节点数", "最高波次", "击杀"]

var _board := Protocol.BOARD_WAVE
var _difficulty := Levels.DEFAULT_DIFFICULTY
var _diff_buttons: Array[Button] = []


func _ready() -> void:
	$BackButton.pressed.connect(_goto_main)
	$Center/Box/BoardRow/WaveBoardButton.pressed.connect(_on_board.bind(Protocol.BOARD_WAVE))
	$Center/Box/BoardRow/SkillBoardButton.pressed.connect(_on_board.bind(Protocol.BOARD_SKILL))
	Net.leaderboard_data.connect(_on_data)
	_build_difficulty_row()
	_apply_board()
	if not Lobby.can_use():
		_show_empty("请先登录联机大厅")
		return
	_reload()


func _build_difficulty_row() -> void:
	var row: HBoxContainer = $Center/Box/DiffRow
	for id in range(Levels.difficulty_count()):
		var btn := Button.new()
		btn.text = Levels.name_of_difficulty(id)
		btn.pressed.connect(_on_difficulty.bind(id))
		row.add_child(btn)
		_diff_buttons.append(btn)


func _apply_board() -> void:
	## 表头与列数随榜单切换；难度筛选器仅波次榜可见。
	var wave := _board == Protocol.BOARD_WAVE
	$Center/Box/BoardRow/WaveBoardButton.theme_type_variation = (
		&"PrimaryButton" if wave else &"TextButton"
	)
	$Center/Box/BoardRow/SkillBoardButton.theme_type_variation = (
		&"TextButton" if wave else &"PrimaryButton"
	)
	$Center/Box/DiffRow.visible = wave
	$Center/Box/Scope.text = _scope_text()
	for id in _diff_buttons.size():
		_diff_buttons[id].theme_type_variation = &"PrimaryButton" if id == _difficulty else &""
	_build_table([])


func _reload() -> void:
	if not Lobby.can_use():
		_show_empty("请先登录联机大厅")
		return
	Lobby.request_leaderboard(_board, _difficulty)


func _on_board(board: int) -> void:
	if board == _board:
		return
	_board = board
	_apply_board()
	_reload()


func _on_difficulty(id: int) -> void:
	if id == _difficulty:
		return
	_difficulty = id
	_apply_board()
	_reload()


func _on_data(board: int, difficulty_id: int, rows: Array) -> void:
	## 只认当前榜单；波次榜还需难度一致，避免快速切换时的过期回包覆盖。
	if board != _board:
		return
	if board == Protocol.BOARD_WAVE and difficulty_id != _difficulty:
		return
	_build_table(rows)


func _build_table(rows: Array) -> void:
	var table: GridContainer = $Center/Box/Table
	for c in table.get_children():
		c.queue_free()
	var headers := WAVE_HEADERS if _board == Protocol.BOARD_WAVE else SKILL_HEADERS
	table.columns = headers.size()
	for h in headers:
		var head := Label.new()
		head.theme_type_variation = &"Caption"
		head.text = h
		table.add_child(head)
	for i in rows.size():
		var cells: Array = (
			_wave_cells(rows[i], i) if _board == Protocol.BOARD_WAVE else _skill_cells(rows[i], i)
		)
		for cell in cells:
			var label := Label.new()
			label.text = cell
			table.add_child(label)
	$Center/Box/Empty.text = "暂无战绩"
	$Center/Box/Empty.visible = rows.is_empty()


func _wave_cells(row: Dictionary, index: int) -> Array:
	return [
		str(index + 1),
		String(row.get("username", "")),
		str(int(row.get("wave", 0))),
		str(int(row.get("kills", 0))),
		_fmt_seconds(float(row.get("seconds", 0.0))),
		str(int(row.get("boss_kills", 0))),
	]


func _skill_cells(row: Dictionary, index: int) -> Array:
	return [
		str(index + 1),
		String(row.get("username", "")),
		str(int(row.get("nodes", 0))),
		str(int(row.get("wave", 0))),
		str(int(row.get("kills", 0))),
	]


func _show_empty(text: String) -> void:
	var table: GridContainer = $Center/Box/Table
	for c in table.get_children():
		c.queue_free()
	table.columns = (WAVE_HEADERS if _board == Protocol.BOARD_WAVE else SKILL_HEADERS).size()
	$Center/Box/Empty.text = text
	$Center/Box/Empty.visible = true


func _scope_text() -> String:
	if _board == Protocol.BOARD_WAVE:
		var dname := Levels.name_of_difficulty(_difficulty)
		return "单人历史最佳榜 · 难度：%s · 指标：最高到达波次（并列比击杀）" % dname
	return "技能榜 · 指标：技能树解锁节点数（并列比最高波次）"


static func _fmt_seconds(seconds: float) -> String:
	var s := maxi(int(seconds), 0)
	return "%d:%02d" % [s / 60, s % 60]


func _goto_main() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
