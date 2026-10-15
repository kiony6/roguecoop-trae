extends Node
## M3/M4 联机冒烟测试 —— 客户端。由 run_net_test.ps1 与主机实例并行启动。

const Protocol := preload("res://net/protocol.gd")

# 场景说明：M4.4 武器改为自动攻击（无需按键）、碎片从任意距离飞向击杀者。
# 经验已按拾取者独立，故客户端不能与主机站位重合（重合时同距击杀归主机）。
# 客户端前段右移满足位移断言，随后左移远离主机，使两端各自就近击杀、各自拾取自己的经验。
const MOVE_BEFORE := 1.5
const FIRE_NEAR := 70.0

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
var _level_seen := false
var _status_seen := false
var _proj_seen := false
var _room_ok := false
var _ip := "127.0.0.1"
var _self_pos := Vector2.ZERO
var _have_self := false
var _nearest_enemy := INF


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
	# 前段右移（满足位移断言）；随后左移远离主机，各自就近击杀并拾取自己的经验
	if _t < MOVE_BEFORE:
		Net.send_local_input(Vector2.RIGHT, 0)
	else:
		Net.send_local_input(Vector2.LEFT, 0)


func _on_connected(local_id: int) -> void:
	_connected = true
	print("[NetTest-Client] connected local_id=%d" % local_id)


func _on_failed() -> void:
	printerr("[NetTest-Client] FAIL connection_failed")
	get_tree().quit(1)


func _on_state(
	_tick: int, meta: Dictionary, players: Array, enemies: Array, loot: Array, projectiles: Array
) -> void:
	_snapshots += 1
	if players.size() >= 2:
		_saw_two = true
	if int(meta.get("level", 1)) >= 2:
		_level_seen = true
	# M4：客户端收到含弹丸的快照，且已收到主机可靠下发的房间（_rpc_room）
	if not projectiles.is_empty():
		_proj_seen = true
	if Net.room_walls().size() > 0:
		_room_ok = true
	for p in players:
		if p.has("status"):
			_status_seen = true
		if p["id"] != Net.local_id:
			continue
		_self_seen = true
		_self_pos = p["pos"]
		_have_self = true
		if not _self_start_captured:
			_self_start = p["pos"]
			_self_start_captured = true
		elif p["pos"].x - _self_start.x > 30.0:
			_self_moved = true
	if not enemies.is_empty():
		_enemy_seen = true
	if not loot.is_empty():
		_loot_seen = true
	# 供开火门控使用：到最近敌人的距离
	_nearest_enemy = INF
	if _have_self:
		for e in enemies:
			_nearest_enemy = minf(_nearest_enemy, _self_pos.distance_to(e["pos"]))


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
		and _level_seen
		and _status_seen
		and _proj_seen
		and _room_ok
	):
		print(
			(
				(
					"[NetTest-Client] PASS local_id=%d snapshots=%d two_players=1 moved=1 "
					+ "enemy_seen=1 loot_seen=1 level_seen=1 status_seen=1 proj_seen=1 room_ok=1"
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
					+ "moved=%s eseen=%s lseen=%s level=%s status=%s proj=%s room=%s"
				)
				% [
					_connected,
					_snapshots,
					_saw_two,
					_self_seen,
					_self_moved,
					_enemy_seen,
					_loot_seen,
					_level_seen,
					_status_seen,
					_proj_seen,
					_room_ok,
				]
			)
		)
		get_tree().quit(1)
