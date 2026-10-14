extends Node
## M2 联机冒烟测试 —— 客户端端。由 run_net_test.ps1 与主机实例并行启动。

const Protocol := preload("res://net/protocol.gd")

var _t := 0.0
var _connected := false
var _snapshots := 0
var _saw_two := false
var _self_seen := false
var _self_start_captured := false
var _self_start := Vector2.ZERO
var _self_moved := false
var _enemy_seen := false
var _loot_seen := false
var _ip := "127.0.0.1"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ip="):
			_ip = a.substr(5)

	Net.connected_ok.connect(_on_connected)
	Net.connection_failed.connect(_on_failed)
	Net.world_state.connect(_on_state)

	var err := Net.client_connect(_ip, Protocol.DEFAULT_PORT)
	if err != OK:
		printerr("[NetTest-Client] FAIL connect err=%d" % err)
		get_tree().quit(1)


func _physics_process(_delta: float) -> void:
	# 持续向右移动 + 开火
	Net.send_local_input(Vector2.RIGHT, 1)


func _on_connected(local_id: int) -> void:
	_connected = true
	print("[NetTest-Client] connected local_id=%d" % local_id)


func _on_failed() -> void:
	printerr("[NetTest-Client] FAIL connection_failed")
	get_tree().quit(1)


func _on_state(_tick: int, players: Array, enemies: Array, loot: Array) -> void:
	_snapshots += 1
	if players.size() >= 2:
		_saw_two = true
	for p in players:
		if p["id"] != Net.local_id:
			continue
		_self_seen = true
		if not _self_start_captured:
			_self_start = p["pos"]
			_self_start_captured = true
		elif p["pos"].x - _self_start.x > 30.0:
			_self_moved = true
	if not enemies.is_empty():
		_enemy_seen = true
	if not loot.is_empty():
		_loot_seen = true


func _process(delta: float) -> void:
	_t += delta
	if (
		_connected
		and _snapshots >= 10
		and _saw_two
		and _self_seen
		and _self_moved
		and _enemy_seen
		and _loot_seen
	):
		print(
			(
				(
					"[NetTest-Client] PASS local_id=%d snapshots=%d two_players=1 moved=1 "
					+ "enemy_seen=1 loot_seen=1"
				)
				% [Net.local_id, _snapshots]
			)
		)
		get_tree().quit(0)
	elif _t > 25.0:
		printerr(
			(
				(
					"[NetTest-Client] FAIL timeout connected=%s snapshots=%d two=%s self=%s "
					+ "moved=%s eseen=%s lseen=%s"
				)
				% [
					_connected,
					_snapshots,
					_saw_two,
					_self_seen,
					_self_moved,
					_enemy_seen,
					_loot_seen,
				]
			)
		)
		get_tree().quit(1)
