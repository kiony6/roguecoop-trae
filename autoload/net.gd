extends Node
## 网络门面（autoload 名 "Net"）。
## 唯一的 @rpc 入口：所有 RPC 方法都挂在本节点上，保证主机/客户端 RPC 路径一致。
## 传输与模拟细节分别委托给 net/net_host.gd 与 net/net_client.gd。

signal player_joined(player_id: int)
signal player_left(player_id: int)
signal input_received(player_id: int)
signal world_state(
	tick: int, meta: Dictionary, players: Array, enemies: Array, loot: Array, projectiles: Array
)
signal upgrade_offer(choices: PackedInt32Array)
signal player_upgrade(player_id: int, card_id: int)
signal run_over(won: bool, stats: Dictionary)
signal room_ready
signal connected_ok(local_id: int)
signal connection_failed
signal disconnected

enum Mode { NONE, HOST, CLIENT }

const Protocol := preload("res://net/protocol.gd")
const NetHostLogic := preload("res://net/net_host.gd")
const NetClientLogic := preload("res://net/net_client.gd")
const AoI := preload("res://net/aoi.gd")

var mode: Mode = Mode.NONE
var local_id := 0
var dedicated := false
var debug_latency_ms := 0  # 调试用单程人为延迟（毫秒），0 = 关闭；RTT ≈ 2×该值
var transport_ws := false  # true = TCP/WebSocket，false = UDP/ENet（默认）

var _host := NetHostLogic.new()
var _client := NetClientLogic.new()
var _send_accum := 0.0
var _snap_accum := 0.0
var _known_peers: Array = []
var _run_over_sent := false
var _input_queue: Array = []
var _snap_queue: Array = []


func _ready() -> void:
	# 保证本地输入在 Player 采样之后再被消费（autoload 默认排在场景节点之前）
	process_physics_priority = 100
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_host() -> bool:
	return mode == Mode.HOST


func is_client() -> bool:
	return mode == Mode.CLIENT


func set_debug_latency_ms(ms: int) -> void:
	## 调试用单程人为延迟：上行在主机收到输入时入队、下行在客户端收到快照时入队。
	debug_latency_ms = maxi(0, ms)


func interp_delay_ms() -> float:
	## 远端插值回放延迟：默认 100ms；开调试延迟时抬到「单程延迟 + 100ms」以覆盖整段延迟。
	return 100.0 if debug_latency_ms <= 0 else float(debug_latency_ms) + 100.0


func set_websocket(enabled: bool) -> void:
	## 切换传输层：true = TCP（WebSocket，适配只开放 TCP 的托管环境），false = UDP（ENet，默认）。
	transport_ws = enabled


func ws_url(address: String, port: int) -> String:
	## WebSocket 客户端地址：create_client 需要带 scheme 的完整 URL。
	return "ws://%s:%d" % [address, port]


func is_run_over() -> bool:
	## M4.5：本局是否已结束（主机取权威状态，客户端取结算 RPC 落下的标记）。
	if mode == Mode.HOST:
		return _host.run_over
	if mode == Mode.CLIENT:
		return _client.run_over
	return false


func room_walls() -> Array:
	if mode == Mode.HOST:
		return _host.room_walls
	if mode == Mode.CLIENT:
		return _client.room_walls
	return []


# ---------------- 主机 ----------------


func host_start(port: int, as_dedicated: bool = false, bind_ip: String = "") -> Error:
	if mode != Mode.NONE:
		return ERR_ALREADY_IN_USE
	var peer: MultiplayerPeer = null
	var err := OK
	if transport_ws:
		# WS 没有 set_bind_ip：绑定地址只能通过 create_server 的第二参传入，"*" = 全部接口
		var ws := WebSocketMultiplayerPeer.new()
		err = ws.create_server(port, "*" if bind_ip.is_empty() else bind_ip)
		peer = ws
	else:
		var enet := ENetMultiplayerPeer.new()
		if not bind_ip.is_empty():
			enet.set_bind_ip(bind_ip)
		err = enet.create_server(port, Protocol.MAX_PLAYERS - 1, 2)
		peer = enet
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	dedicated = as_dedicated
	_host.reset(as_dedicated)
	_known_peers.clear()
	_run_over_sent = false
	_input_queue.clear()
	_snap_queue.clear()
	mode = Mode.HOST
	local_id = 0 if as_dedicated else 1
	_send_accum = 0.0
	_snap_accum = 0.0
	set_physics_process(true)
	if not as_dedicated:
		player_joined.emit(1)
	return OK


func host_stop() -> void:
	if mode != Mode.HOST:
		return
	var was_dedicated := dedicated
	mode = Mode.NONE
	set_physics_process(false)
	multiplayer.multiplayer_peer = null
	_host.reset(was_dedicated)
	dedicated = false
	local_id = 0
	_input_queue.clear()
	_snap_queue.clear()


# ---------------- 客户端 ----------------


func client_connect(address: String, port: int) -> Error:
	if mode != Mode.NONE:
		return ERR_ALREADY_IN_USE
	var peer: MultiplayerPeer = null
	var err := OK
	if transport_ws:
		var ws := WebSocketMultiplayerPeer.new()
		err = ws.create_client(ws_url(address, port))
		peer = ws
	else:
		var enet := ENetMultiplayerPeer.new()
		err = enet.create_client(address, port)
		peer = enet
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_client.reset()
	_known_peers.clear()
	_run_over_sent = false
	mode = Mode.CLIENT
	local_id = 0
	_send_accum = 0.0
	set_physics_process(true)
	return OK


func client_disconnect() -> void:
	if mode != Mode.CLIENT:
		return
	mode = Mode.NONE
	set_physics_process(false)
	multiplayer.multiplayer_peer = null
	_client.reset()
	local_id = 0


# ---------------- 对外输入 ----------------


func send_local_input(move: Vector2, buttons: int) -> void:
	var dir := move
	if dir.length() > 1.0:
		dir = dir.normalized()
	if mode == Mode.HOST:
		_host.local_move = dir
		_host.local_buttons = buttons
	elif mode == Mode.CLIENT:
		_client.pending_move = dir
		_client.pending_buttons = buttons


func send_upgrade_pick(card_id: int) -> void:
	if mode == Mode.CLIENT:
		_rpc_upgrade_pick.rpc_id(1, card_id)
	elif mode == Mode.HOST:
		if _host.apply_choice(1, card_id):
			player_upgrade.emit(1, card_id)


func _read_local_move() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func _read_buttons() -> int:
	var b := 0
	if Input.is_action_pressed("fire"):
		b |= 1
	if Input.is_action_pressed("dash"):
		b |= 2
	return b


# ---------------- 主循环 ----------------


func _physics_process(delta: float) -> void:
	if mode == Mode.HOST:
		_drain_input_queue()
		if not dedicated:
			# 主机本地玩家的输入在这里采样：不依赖场景树中是否恰好存在玩家节点
			_host.local_move = _read_local_move()
			_host.local_buttons = _read_buttons()
		if not _host.run_over:
			_host.physics_step(delta)
		if not dedicated:
			# 本机渲染每物理帧刷新（60Hz），直连完整权威状态
			world_state.emit(
				_host.tick,
				_host.meta(local_id),
				_host.player_states(),
				_host.enemy_states(),
				_host.loot_states(),
				_host.projectile_states()
			)
		if not _host.run_over:
			# 升级候选只对真实对端下发（专用服务器没有 peer 1，逐 peer 走可靠 RPC）
			_offer_to_players()
		# M4.2：结算检测必须在门控外无条件执行，否则结算信号永不发出、物理永久停摆
		_check_run_over()
		_snap_accum += delta
		if _snap_accum >= 1.0 / float(Protocol.SNAPSHOT_RATE):
			_snap_accum = 0.0
			_send_snapshots()
	elif mode == Mode.CLIENT:
		_drain_snap_queue()
		# M4.5：结算后停止上报输入（仍继续应用快照，保持画面与冻结的权威状态一致）
		if local_id != 0 and not _client.run_over:
			_send_accum += delta
			if _send_accum >= 1.0 / float(Protocol.INPUT_RATE):
				_send_accum = 0.0
				_client.tick += 1
				_rpc_input.rpc_id(
					1,
					_client.tick,
					Protocol.encode_input(
						_client.pending_move, Vector2.RIGHT, _client.pending_buttons
					)
				)


func _offer_to_players() -> void:
	for peer in _host.peer_ids():
		var choices := _host.pending_offer(peer)
		if choices.is_empty():
			continue
		var packed := PackedInt32Array(choices)
		if peer == 1:
			upgrade_offer.emit(packed)
		else:
			_rpc_upgrade_offer.rpc_id(peer, packed)


func _check_run_over() -> void:
	if _host.run_over and not _run_over_sent:
		_run_over_sent = true
		# M5：专用服务器没有本地玩家（local_id=0），取接入的第一名客户端作为运维日志样本
		var sample := local_id
		if dedicated:
			var ids := _host.peer_ids()
			sample = int(ids[0]) if ids.size() > 0 else 0
		var local_stats := _host.stats(sample) if _host.has_player(sample) else {}
		run_over.emit(_host.won, local_stats)
		for peer in _host.peer_ids():
			if peer == 1:
				continue
			var stats := _host.stats(peer)
			_rpc_run_over.rpc_id(
				peer,
				_host.won,
				int(stats["kills"]),
				int(stats["level"]),
				int(stats["boss_kills"]),
				float(stats["seconds"])
			)


func _send_snapshots() -> void:
	var players := _host.player_states()
	var enemies := _host.enemy_states()
	var loot := _host.loot_states()
	for peer in _host.peer_ids():
		if peer == 1:
			continue  # 主机本地走 world_state 直连
		if not _host.players.has(peer):
			continue
		var meta := _host.meta(peer)
		var center: Vector2 = _host.players[peer]["pos"]
		var culled_enemies := AoI.cull(center, AoI.AOI_RADIUS, enemies)
		var culled_loot := AoI.cull(center, AoI.AOI_RADIUS, loot)
		var projs := _host.projectile_states()
		var culled_proj := AoI.cull(center, AoI.AOI_RADIUS, projs)
		var payload := Protocol.encode_snapshot(
			_host.tick, meta, players, culled_enemies, culled_loot, culled_proj
		)
		_rpc_snapshot.rpc_id(peer, _host.tick, payload)
	_host.snapshot_count += 1


func _drain_input_queue() -> void:
	if _input_queue.is_empty():
		return
	var now := Time.get_ticks_msec()
	var keep: Array = []
	for it in _input_queue:
		if int(it["due"]) <= now:
			_apply_remote_input(int(it["sender"]), it["payload"])
		else:
			keep.append(it)
	_input_queue = keep


func _drain_snap_queue() -> void:
	if _snap_queue.is_empty():
		return
	var now := Time.get_ticks_msec()
	var keep: Array = []
	for it in _snap_queue:
		if int(it["due"]) <= now:
			_apply_snapshot(it["payload"])
		else:
			keep.append(it)
	_snap_queue = keep


func _apply_remote_input(sender: int, payload: PackedByteArray) -> void:
	var f := Protocol.decode_input(payload)
	_host.set_remote_input(sender, f["move"], f["buttons"])
	input_received.emit(sender)


func _apply_snapshot(payload: PackedByteArray) -> void:
	var snap := Protocol.decode_snapshot(payload)
	_client.last_snapshot_tick = snap["tick"]
	_client.last_meta = snap["meta"]
	_client.last_players = snap["players"]
	world_state.emit(
		snap["tick"],
		snap["meta"],
		snap["players"],
		snap["enemies"],
		snap["loot"],
		snap["projectiles"]
	)


# ---------------- 连接事件 ----------------


func _on_peer_connected(id: int) -> void:
	if mode != Mode.HOST:
		return
	_host.add_player(id)
	_rpc_room.rpc_id(id, Protocol.encode_room(_host.room_walls))
	player_joined.emit(id)
	_broadcast_peer_list()


func _on_peer_disconnected(id: int) -> void:
	if mode != Mode.HOST:
		return
	_host.remove_player(id)
	player_left.emit(id)
	_broadcast_peer_list()


func _on_connected_to_server() -> void:
	local_id = multiplayer.get_unique_id()
	connected_ok.emit(local_id)


func _on_connection_failed() -> void:
	mode = Mode.NONE
	set_physics_process(false)
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	mode = Mode.NONE
	set_physics_process(false)
	multiplayer.multiplayer_peer = null
	disconnected.emit()


func _broadcast_peer_list() -> void:
	_rpc_peer_list.rpc(_host.peer_ids())


# ---------------- RPC ----------------

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _rpc_input(_tick_in: int, payload: PackedByteArray) -> void:
	if mode != Mode.HOST:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or sender == 1:
		return
	if not _host.has_player(sender):
		return
	if debug_latency_ms > 0:
		_input_queue.append(
			{"due": Time.get_ticks_msec() + debug_latency_ms, "payload": payload, "sender": sender}
		)
		return
	_apply_remote_input(sender, payload)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _rpc_snapshot(_tick_in: int, payload: PackedByteArray) -> void:
	if mode != Mode.CLIENT:
		return
	if debug_latency_ms > 0:
		_snap_queue.append({"due": Time.get_ticks_msec() + debug_latency_ms, "payload": payload})
		return
	_apply_snapshot(payload)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_peer_list(ids: PackedInt32Array) -> void:
	if mode != Mode.CLIENT:
		return
	var my_id := multiplayer.get_unique_id()
	for id in ids:
		if id == my_id:
			continue
		if not _known_peers.has(id):
			_known_peers.append(id)
			player_joined.emit(id)
	for id in _known_peers.duplicate():
		if not ids.has(id):
			_known_peers.erase(id)
			player_left.emit(id)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_room(payload: PackedByteArray) -> void:
	if mode != Mode.CLIENT:
		return
	_client.room_walls = Protocol.decode_room(payload)
	room_ready.emit()


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_upgrade_offer(choices: PackedInt32Array) -> void:
	if mode != Mode.CLIENT:
		return
	upgrade_offer.emit(choices)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_upgrade_pick(card_id: int) -> void:
	if mode != Mode.HOST:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or sender == 1:
		return
	if _host.apply_choice(sender, card_id):
		player_upgrade.emit(sender, card_id)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_run_over(won: bool, kills: int, level: int, boss_kills: int, seconds: float) -> void:
	if mode != Mode.CLIENT:
		return
	# M4.5：客户端同步进入结算态——冻结本地预测并停止上报输入，
	# 避免客户端继续预测、被冻结的权威位置反复拽回而在胜利后抽搐。
	_client.run_over = true
	_client.pending_move = Vector2.ZERO
	_client.pending_buttons = 0
	run_over.emit(
		won, {"kills": kills, "level": level, "boss_kills": boss_kills, "seconds": seconds}
	)
