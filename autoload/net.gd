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

var _host := NetHostLogic.new()
var _client := NetClientLogic.new()
var _send_accum := 0.0
var _snap_accum := 0.0
var _known_peers: Array = []
var _run_over_sent := false


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


func room_walls() -> Array:
	if mode == Mode.HOST:
		return _host.room_walls
	if mode == Mode.CLIENT:
		return _client.room_walls
	return []


# ---------------- 主机 ----------------


func host_start(port: int) -> Error:
	if mode != Mode.NONE:
		return ERR_ALREADY_IN_USE
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, Protocol.MAX_PLAYERS - 1, 2)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_host.reset()
	_known_peers.clear()
	_run_over_sent = false
	mode = Mode.HOST
	local_id = 1
	_send_accum = 0.0
	_snap_accum = 0.0
	set_physics_process(true)
	player_joined.emit(1)
	return OK


func host_stop() -> void:
	if mode != Mode.HOST:
		return
	mode = Mode.NONE
	set_physics_process(false)
	multiplayer.multiplayer_peer = null
	_host.reset()
	local_id = 0


# ---------------- 客户端 ----------------


func client_connect(address: String, port: int) -> Error:
	if mode != Mode.NONE:
		return ERR_ALREADY_IN_USE
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
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
		# 主机本地玩家的输入在这里采样：不依赖场景树中是否恰好存在玩家节点
		_host.local_move = _read_local_move()
		_host.local_buttons = _read_buttons()
		if not _host.run_over:
			_host.physics_step(delta)
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
			_offer_to_players()
		_check_run_over()
		_snap_accum += delta
		if _snap_accum >= 1.0 / float(Protocol.SNAPSHOT_RATE):
			_snap_accum = 0.0
			_send_snapshots()
	elif mode == Mode.CLIENT and local_id != 0:
		_send_accum += delta
		if _send_accum >= 1.0 / float(Protocol.INPUT_RATE):
			_send_accum = 0.0
			_client.tick += 1
			_rpc_input.rpc_id(
				1,
				_client.tick,
				Protocol.encode_input(_client.pending_move, Vector2.RIGHT, _client.pending_buttons)
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
		run_over.emit(_host.won, _host.stats(local_id))
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
	var f := Protocol.decode_input(payload)
	_host.set_remote_input(sender, f["move"], f["buttons"])
	input_received.emit(sender)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _rpc_snapshot(_tick_in: int, payload: PackedByteArray) -> void:
	if mode != Mode.CLIENT:
		return
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
	run_over.emit(
		won, {"kills": kills, "level": level, "boss_kills": boss_kills, "seconds": seconds}
	)
