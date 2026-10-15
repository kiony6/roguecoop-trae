extends Node
## M3/M4 联机冒烟测试 —— 主机端。由 run_net_test.ps1 与客户端实例并行启动。

const Protocol := preload("res://net/protocol.gd")

var _t := 0.0
var _remote_input := false
var _saw_two := false
var _start_captured := false
var _client_start := Vector2.ZERO
var _client_moved := false
var _host_start_captured := false
var _host_start := Vector2.ZERO
var _host_moved := false
var _seen_enemies := {}
var _enemy_seen := false
var _enemy_killed := false
var _seen_loot := {}
var _loot_seen := false
var _loot_picked := false
var _level_seen := false
var _level_seen_at := 0.0
var _status_seen := false
var _proj_seen := false
var _room_ok := false
var _wave_ok := false


func _ready() -> void:
	# 模拟主机本地按键：移动 + 开火，验证主机侧输入真的被采样（曾出现主机 WASD 无效的回归）
	Input.action_press("move_right")
	Input.action_press("fire")
	Net.input_received.connect(_on_input)
	Net.world_state.connect(_on_state)
	var err := Net.host_start(Protocol.DEFAULT_PORT)
	if err != OK:
		printerr("[NetTest-Host] FAIL start_server err=%d" % err)
		get_tree().quit(1)


func _on_input(pid: int) -> void:
	if pid != 1:
		_remote_input = true


func _on_state(
	_tick: int, meta: Dictionary, players: Array, enemies: Array, loot: Array, projectiles: Array
) -> void:
	if players.size() >= 2:
		_saw_two = true
	if int(meta.get("level", 1)) >= 2:
		if not _level_seen:
			_level_seen_at = _t
		_level_seen = true
	# M4：波次档位已推进到 >=1、程序化房间墙体已生成、快照含弹丸
	if int(meta.get("wave", 0)) >= 1:
		_wave_ok = true
	if Net.room_walls().size() > 0:
		_room_ok = true
	if not projectiles.is_empty():
		_proj_seen = true
	for p in players:
		if p.has("status"):
			_status_seen = true
		if p["id"] == 1:
			if not _host_start_captured:
				_host_start = p["pos"]
				_host_start_captured = true
			elif p["pos"].x - _host_start.x > 30.0:
				_host_moved = true
			continue
		if not _start_captured:
			_client_start = p["pos"]
			_start_captured = true
		elif p["pos"].x - _client_start.x > 30.0:
			_client_moved = true

	var enemy_now := {}
	for e in enemies:
		enemy_now[e["id"]] = true
		_seen_enemies[e["id"]] = true
	if not enemy_now.is_empty():
		_enemy_seen = true
	for id in _seen_enemies.keys():
		if not enemy_now.has(id):
			_enemy_killed = true

	var loot_now := {}
	for l in loot:
		loot_now[l["id"]] = true
		_seen_loot[l["id"]] = true
	if not loot_now.is_empty():
		_loot_seen = true
	for id in _seen_loot.keys():
		if not loot_now.has(id):
			_loot_picked = true


func _process(delta: float) -> void:
	_t += delta
	# 最少存活 4s，保证客户端有足够时间收满快照并观察到位移/战斗/升级
	var combat_ok := _enemy_seen and _enemy_killed and _loot_seen
	# 等级达标后再停留 0.6s，确保客户端至少收到一份包含 level>=2 的快照后才退出
	var linger_ok := _level_seen and (_t - _level_seen_at) > 0.6
	if (
		_remote_input
		and _saw_two
		and _client_moved
		and _host_moved
		and combat_ok
		and linger_ok
		and _status_seen
		and _proj_seen
		and _room_ok
		and _wave_ok
		and _t > 4.0
	):
		print(
			(
				"[NetTest-Host] PASS remote_input=1 two_players=1 client_moved=1 host_moved=1 "
				+ "enemy_seen=1 enemy_killed=1 loot_seen=1 loot_picked=%d level_seen=1 "
				+ "status_seen=1 proj_seen=1 room_ok=1 wave_ok=1"
			)
			% (1 if _loot_picked else 0)
		)
		get_tree().quit(0)
	elif _t > 25.0:
		printerr(
			(
				"[NetTest-Host] FAIL timeout remote_input=%s two=%s cmoved=%s hmoved=%s "
				+ "eseen=%s ekilled=%s lseen=%s level=%s status=%s proj=%s room=%s wave=%s"
			)
			% [
				_remote_input,
				_saw_two,
				_client_moved,
				_host_moved,
				_enemy_seen,
				_enemy_killed,
				_loot_seen,
				_level_seen,
				_status_seen,
				_proj_seen,
				_room_ok,
				_wave_ok,
			]
		)
		get_tree().quit(1)
