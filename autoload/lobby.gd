extends Node
## 大厅/房间门面（autoload 名 "Lobby"）：页面只认本单例的信号与状态。
## 本文件只调用 Net 的公开 API，自己绝不声明 RPC 方法 —— 保证 RPC 入口唯一在 autoload/net.gd。

signal room_updated
signal room_failed(reason: String)

const LobbyLib := preload("res://net/lobby.gd")

var room_code := ""  # "" = 不在房间（与 _rpc_room_state("") 哨兵一致）
var is_host := false
var room_state := LobbyLib.STATE.WAITING
var members := PackedStringArray()  # 大厅用户名，房主首位
var last_error := 0


func _ready() -> void:
	Net.room_state.connect(_on_room_state)
	Net.room_error.connect(_on_room_error)


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


func reset() -> void:
	room_code = ""
	is_host = false
	room_state = LobbyLib.STATE.WAITING
	members = PackedStringArray()
	last_error = 0


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
