extends Node
## M5 专用服务器入口：无渲染、无本地玩家，只跑主机权威模拟并广播快照。
## 用法：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <proj> \
##     res://scenes/dedicated.tscn -- --port=25600 [--bind=0.0.0.0]

const Protocol := preload("res://net/protocol.gd")

const AccountServerLib := preload("res://net/account_server.gd")

const DEFAULT_DATA_PATH := "user://accounts.json"

const RUN_RESET_DELAY := 20.0  # 一局结束后等这么久再自动重开（给客户端留时间看完结算）

var _port := Protocol.DEFAULT_PORT
var _bind := ""
var _data := DEFAULT_DATA_PATH
var _mode := "game"  # "game"（默认，既有单房间专服）或 "lobby"（大厅多房间，M6.3）
var _accounts = null
var _restarting := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			_port = int(a.substr(7))
		elif a.begins_with("--bind="):
			_bind = a.substr(7)
		elif a.begins_with("--mode="):
			_mode = a.substr(7)
		elif a.begins_with("--transport="):
			Net.set_websocket(a.substr(12) == "ws")
		elif a.begins_with("--data="):
			_data = a.substr(7)
	_accounts = AccountServerLib.new(_data)
	_accounts.load_from_disk()
	Net.enable_accounts(_accounts)
	Net.account_registered.connect(_on_registered)
	Net.account_session_closed.connect(_on_session_closed)
	Net.player_joined.connect(_on_joined)
	Net.player_left.connect(_on_left)
	Net.run_over.connect(_on_run_over)
	Net.run_reset.connect(_on_run_reset)
	Net.lobby_event.connect(_on_lobby_event)
	_start()


func _start() -> void:
	if _mode == "lobby":
		_start_lobby()
		return
	var err := Net.host_start(_port, true, _bind)
	if err != OK:
		printerr("[Dedicated] FAIL start port=%d err=%d" % [_port, err])
		get_tree().quit(1)
		return
	print(
		(
			"[Dedicated] listening port=%d bind=%s transport=%s accounts=%d"
			% [
				_port,
				"0.0.0.0" if _bind.is_empty() else _bind,
				"ws/tcp" if Net.transport_ws else "udp/enet",
				_accounts.count(),
			]
		)
	)


func _start_lobby() -> void:
	## 大厅专服：单进程多房间，房间生命周期由 LobbyServer 管理（结算不拆连接、不整服重开）。
	var err := Net.server_start(_port, _bind)
	if err != OK:
		printerr("[Dedicated] FAIL start lobby port=%d err=%d" % [_port, err])
		get_tree().quit(1)
		return
	print(
		(
			"[Dedicated] mode=lobby listening port=%d bind=%s transport=%s rooms=%d"
			% [
				_port,
				"0.0.0.0" if _bind.is_empty() else _bind,
				"ws/tcp" if Net.transport_ws else "udp/enet",
				Net.lobby_room_count(),
			]
		)
	)


func _on_lobby_event(event: String, code: String, peer: int) -> void:
	print(
		"[Dedicated] room %s code=%s peer=%d rooms=%d" % [event, code, peer, Net.lobby_room_count()]
	)


func _on_registered(ok: bool, err_code: int) -> void:
	print(
		(
			"[Dedicated] account registered ok=%s err=%d accounts=%d"
			% [ok, err_code, _accounts.count()]
		)
	)


func _on_session_closed() -> void:
	print("[Dedicated] account session closed")


func _on_joined(id: int) -> void:
	print("[Dedicated] player_joined id=%d" % id)


func _on_left(id: int) -> void:
	print("[Dedicated] player_left id=%d" % id)


func _on_run_reset(idle_seconds: float) -> void:
	print("[Dedicated] idle reset after %.1fs empty: run reset to wave 1" % idle_seconds)


func _on_run_over(won: bool, stats: Dictionary) -> void:
	if _mode == "lobby":
		return  # 大厅模式：房间生命周期由 LobbyServer 管理（结算不拆连接），不做整服重开
	if _restarting:
		return
	_restarting = true
	print(
		(
			"[Dedicated] run_over won=%s kills=%d level=%d boss=%d seconds=%.1f"
			% [
				won,
				int(stats.get("kills", 0)),
				int(stats.get("level", 1)),
				int(stats.get("boss_kills", 0)),
				float(stats.get("seconds", 0.0)),
			]
		)
	)
	await get_tree().create_timer(RUN_RESET_DELAY).timeout
	Net.host_stop()
	_restarting = false
	print("[Dedicated] restarting next run")
	_start()
