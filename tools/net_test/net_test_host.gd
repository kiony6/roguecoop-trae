extends Node
## M1 联机冒烟测试 —— 主机端。由 run_net_test.ps1 与客户端实例并行启动。

const Protocol := preload("res://net/protocol.gd")

var _t := 0.0
var _remote_input := false
var _saw_two := false
var _start_captured := false
var _client_start := Vector2.ZERO
var _client_moved := false


func _ready() -> void:
	Net.input_received.connect(_on_input)
	Net.world_state.connect(_on_state)
	var err := Net.host_start(Protocol.DEFAULT_PORT)
	if err != OK:
		printerr("[NetTest-Host] FAIL start_server err=%d" % err)
		get_tree().quit(1)


func _on_input(pid: int) -> void:
	if pid != 1:
		_remote_input = true


func _on_state(_tick: int, players: Array) -> void:
	if players.size() >= 2:
		_saw_two = true
	for p in players:
		if p["id"] == 1:
			continue
		if not _start_captured:
			_client_start = p["pos"]
			_start_captured = true
		elif p["pos"].x - _client_start.x > 30.0:
			_client_moved = true


func _process(delta: float) -> void:
	_t += delta
	# 最少存活 3s，保证客户端有足够时间收满 ≥10 个快照并观察到位移
	if _remote_input and _saw_two and _client_moved and _t > 3.0:
		print("[NetTest-Host] PASS remote_input=1 two_players=1 client_moved=1")
		get_tree().quit(0)
	elif _t > 20.0:
		printerr("[NetTest-Host] FAIL timeout remote_input=%s two_players=%s moved=%s"
			% [_remote_input, _saw_two, _client_moved])
		get_tree().quit(1)
