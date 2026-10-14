extends Node
## 网络门面（autoload 名 "Net"）。
## 唯一的 @rpc 入口：所有 RPC 方法都挂在本节点上，保证主机/客户端 RPC 路径一致。
## 传输与模拟细节分别委托给 net/net_host.gd 与 net/net_client.gd。

signal player_joined(player_id: int)
signal player_left(player_id: int)
signal input_received(player_id: int)
signal world_state(tick: int, players: Array)
signal connected_ok(local_id: int)
signal connection_failed
signal disconnected

enum Mode { NONE, HOST, CLIENT }

const Protocol := preload("res://net/protocol.gd")
const NetHostLogic := preload("res://net/net_host.gd")
const NetClientLogic := preload("res://net/net_client.gd")

var mode: Mode = Mode.NONE
var local_id := 0

var _host := NetHostLogic.new()
var _client := NetClientLogic.new()
var _send_accum := 0.0
var _snap_accum := 0.0
var _known_peers: Array = []


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


# ---------------- 主循环 ----------------


func _physics_process(delta: float) -> void:
	if mode == Mode.HOST:
		_host.physics_step(delta)
		# 本机渲染每物理帧刷新（60Hz），网络快照另行降频
		world_state.emit(_host.tick, _host.player_states())
		_snap_accum += delta
		if _snap_accum >= 1.0 / float(Protocol.SNAPSHOT_RATE):
			_snap_accum = 0.0
			_send_snapshot()
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


func _send_snapshot() -> void:
	var payload := Protocol.encode_snapshot(_host.tick, _host.player_states())
	_host.snapshot_count += 1
	_rpc_snapshot.rpc(_host.tick, payload)


# ---------------- 连接事件 ----------------


func _on_peer_connected(id: int) -> void:
	if mode != Mode.HOST:
		return
	_host.add_player(id)
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
	_client.last_players = snap["players"]
	world_state.emit(snap["tick"], snap["players"])


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
