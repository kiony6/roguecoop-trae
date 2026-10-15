extends Node
## M5 专用服务器入口：无渲染、无本地玩家，只跑主机权威模拟并广播快照。
## 用法：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <proj> \
##     res://scenes/dedicated.tscn -- --port=25600 [--bind=0.0.0.0]

const Protocol := preload("res://net/protocol.gd")

const RUN_RESET_DELAY := 20.0  # 一局结束后等这么久再自动重开（给客户端留时间看完结算）

var _port := Protocol.DEFAULT_PORT
var _bind := ""
var _restarting := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			_port = int(a.substr(7))
		elif a.begins_with("--bind="):
			_bind = a.substr(7)
		elif a.begins_with("--transport="):
			Net.set_websocket(a.substr(12) == "ws")
	Net.player_joined.connect(_on_joined)
	Net.player_left.connect(_on_left)
	Net.run_over.connect(_on_run_over)
	_start()


func _start() -> void:
	var err := Net.host_start(_port, true, _bind)
	if err != OK:
		printerr("[Dedicated] FAIL start port=%d err=%d" % [_port, err])
		get_tree().quit(1)
		return
	print(
		(
			"[Dedicated] listening port=%d bind=%s transport=%s"
			% [
				_port,
				"0.0.0.0" if _bind.is_empty() else _bind,
				"ws/tcp" if Net.transport_ws else "udp/enet"
			]
		)
	)


func _on_joined(id: int) -> void:
	print("[Dedicated] player_joined id=%d" % id)


func _on_left(id: int) -> void:
	print("[Dedicated] player_left id=%d" % id)


func _on_run_over(won: bool, stats: Dictionary) -> void:
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
