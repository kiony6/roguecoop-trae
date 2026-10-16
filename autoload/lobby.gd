extends Node
## 大厅/房间门面（autoload 名 "Lobby"）：页面只认本单例的信号与状态。
## 本文件只调用 Net 的公开 API，自己绝不声明 RPC 方法 —— 保证 RPC 入口唯一在 autoload/net.gd。

signal room_updated
signal room_failed(reason: String)
signal room_config_updated  # 房配置（关卡/难度）变化（M7）
signal progress_updated  # 关卡解锁进度下发（M7）

const LobbyLib := preload("res://net/lobby.gd")

var room_code := ""  # "" = 不在房间（与 _rpc_room_state("") 哨兵一致）
var is_host := false
var room_state := LobbyLib.STATE.WAITING
var members := PackedStringArray()  # 大厅用户名，房主首位
var last_error := 0
var level_id := LobbyLib.DEFAULT_LEVEL  # 当前房间关卡（M7）
var difficulty_id := LobbyLib.DEFAULT_DIFFICULTY  # 当前房间难度（M7）
var cleared_levels := PackedInt32Array()  # 已通关关卡集合（M7）
var best_wave := PackedInt32Array()  # 各关最佳波次，下标 = 关卡 id（M7）


func _ready() -> void:
	Net.room_state.connect(_on_room_state)
	Net.room_error.connect(_on_room_error)
	Net.room_config.connect(_on_room_config)
	Net.progress_data.connect(_on_progress_data)


func in_room() -> bool:
	return not room_code.is_empty()


func can_use() -> bool:
	## 仅联机大厅通道（ROLE_LOBBY 客户端）可用；P2 直连主机不支持房间功能。
	return Net.is_client()


func create_room() -> void:
	if not _guard():
		return
	Net.send_room_create()


func join_room(code: String) -> void:
	if not _guard():
		return
	if not LobbyLib.is_valid_code(code):
		room_failed.emit(LobbyLib.reason_text(LobbyLib.ERR.BAD_CODE))
		return
	Net.send_room_join(code)


func leave_room() -> void:
	if not Net.is_client():
		return
	Net.send_room_leave()


func start_run() -> void:
	if not _guard():
		return
	Net.send_room_start()


func set_config(new_level_id: int, new_difficulty_id: int) -> void:
	## 房主选关/选难度（M7）：仅联机大厅房主上行，服务端校验身份后广播。
	if not _guard() or not is_host:
		return
	Net.send_room_config(new_level_id, new_difficulty_id)


func request_progress() -> void:
	## 拉取本人关卡解锁进度（M7）：进入房间页或登录后调用。
	if not can_use():
		return
	Net.send_progress_request()


func request_leaderboard(board: int, diff_id: int) -> void:
	## 拉取榜单（M7）：排行榜页调用；board ∈ {Protocol.BOARD_WAVE, BOARD_SKILL}。
	if not can_use():
		return
	Net.send_leaderboard_request(board, diff_id)


func reset() -> void:
	room_code = ""
	is_host = false
	room_state = LobbyLib.STATE.WAITING
	members = PackedStringArray()
	last_error = 0
	level_id = LobbyLib.DEFAULT_LEVEL
	difficulty_id = LobbyLib.DEFAULT_DIFFICULTY
	cleared_levels = PackedInt32Array()
	best_wave = PackedInt32Array()


func _guard() -> bool:
	if Net.is_client():
		return true
	room_failed.emit("请先登录联机大厅")
	return false


func _on_room_state(code: String, host: bool, state: int, names: PackedStringArray) -> void:
	room_code = code
	is_host = host
	room_state = state
	members = names
	room_updated.emit()


func _on_room_error(err: int) -> void:
	last_error = err
	room_failed.emit(LobbyLib.reason_text(err))


func _on_room_config(new_level_id: int, new_difficulty_id: int) -> void:
	level_id = new_level_id
	difficulty_id = new_difficulty_id
	room_config_updated.emit()


func _on_progress_data(cleared: PackedInt32Array, waves: PackedInt32Array) -> void:
	cleared_levels = cleared
	best_wave = waves
	progress_updated.emit()
