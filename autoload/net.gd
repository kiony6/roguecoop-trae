extends Node  # gdlint:ignore=max-public-methods
## 网络门面（autoload 名 "Net"）。
## 唯一的 @rpc 入口：所有 RPC 方法都挂在本节点上，保证主机/客户端 RPC 路径一致。
## 传输与模拟细节分别委托给 net/net_host.gd 与 net/net_client.gd。
## 注：本节点即 Net 的公开 API 集合，公共方法数必然超过 gdlint 默认上限 20，
## 故在第 1 行显式豁免 max-public-methods（工程无 .gdlintrc）。

signal player_joined(player_id: int)
signal player_left(player_id: int)
signal input_received(player_id: int)
signal world_state(
	tick: int, meta: Dictionary, players: Array, enemies: Array, loot: Array, projectiles: Array
)
signal upgrade_offer(choices: PackedInt32Array)
signal player_upgrade(player_id: int, card_id: int)
signal run_over(won: bool, stats: Dictionary)
signal run_reset(idle_seconds: float)
signal room_ready
signal connected_ok(local_id: int)
signal connection_failed
signal disconnected
signal auth_challenge(salt_b64: String, nonce_b64: String)
signal auth_result(ok: bool, username: String, err_code: int)
signal account_registered(ok: bool, err_code: int)
signal account_session_closed
signal version_mismatch(server_version: int)
signal room_state(code: String, is_host: bool, state: int, members: PackedStringArray)
signal room_error(err: int)
signal lobby_event(event: String, code: String, peer: int)
signal skill_state_changed(points: int, nodes: PackedInt32Array)
signal player_skill_unlock(player_id: int, node_id: int)
signal fx(kind: int, pos: Vector2, dir: Vector2, radius: float)
signal enemy_elements(ids: PackedInt32Array, elems: PackedByteArray)  # 稀疏元素状态（只含带元素的敌人）
signal room_config(level_id: int, difficulty_id: int)  # 房配置下发（M7）
signal progress_data(cleared: PackedInt32Array, best_wave: PackedInt32Array)  # 关卡解锁进度（M7）
signal leaderboard_data(board: int, difficulty_id: int, rows: Array)  # 榜单数据（M7）

enum Mode { NONE, HOST, CLIENT, SERVER }

const Protocol := preload("res://net/protocol.gd")
const NetHostLogic := preload("res://net/net_host.gd")
const NetClientLogic := preload("res://net/net_client.gd")
const AoI := preload("res://net/aoi.gd")
const AccountLib := preload("res://net/account.gd")
const LobbyLib := preload("res://net/lobby.gd")
const LobbyServer := preload("res://net/lobby_server.gd")

const HANDSHAKE_TIMEOUT_MS := 5000  # 连接期 declare / hello 未到达的容忍窗口

var mode: Mode = Mode.NONE
var local_id := 0
var dedicated := false
var debug_latency_ms := 0  # 调试用单程人为延迟（毫秒），0 = 关闭；RTT ≈ 2×该值
var transport_ws := false  # true = TCP/WebSocket，false = UDP/ENet（默认）
var role := Protocol.ROLE_PLAYER  # 本端连接角色：ROLE_PLAYER 进对局 / ROLE_LOBBY 只走账号 RPC
var forced_version := -1  # >= 0 时替代 Protocol.PROTOCOL_VERSION（仅供测试注入）

var _host := NetHostLogic.new()
var _client := NetClientLogic.new()
var _send_accum := 0.0
var _snap_accum := 0.0
var _known_peers: Array = []
var _run_over_sent := false
var _input_queue: Array = []
var _snap_queue: Array = []
var _idle_resets_seen := 0
var _account_server = null  # 账号服务实例（HOST 且启用账号时非空；由 dedicated.gd 注入）
var _score_board = null  # 榜单与关卡进度（SERVER 且启用榜单时非空；由 dedicated.gd 注入）
var _declared: Dictionary = {}  # 服务端：peer -> {"version": int, "role": int}
var _handshake_deadlines: Dictionary = {}  # 服务端：peer -> declare 截止毫秒
var _hello_deadline := -1  # 客户端：等 hello 的截止毫秒
var _lobby = null  # SERVER 模式：房间表 + peer→房间 路由（由 server_start 创建）
var _skill_points := 0  # CLIENT：最近一次收到的技能点
var _skill_nodes: Array = []  # CLIENT：最近一次收到的已解锁节点


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


func is_server() -> bool:
	return mode == Mode.SERVER


func lobby_room_count() -> int:
	## SERVER 模式当前存活房间数（供运维日志）；非 SERVER 返回 0。
	return 0 if _lobby == null else int(_lobby.room_count())


func _is_host_like() -> bool:
	## HOST 与 SERVER 都是「服务端」，共享握手 / 账号 / 声明 RPC 的受理路径。
	return mode == Mode.HOST or mode == Mode.SERVER


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


func set_role(r: int) -> void:
	role = r


func set_forced_version(v: int) -> void:
	forced_version = v


func desired_version() -> int:
	return forced_version if forced_version >= 0 else Protocol.PROTOCOL_VERSION


func enable_accounts(server) -> void:
	## 专服注入账号服务实例；仅 HOST 模式使用。
	_account_server = server


func accounts_enabled() -> bool:
	return _account_server != null


func enable_scores(board) -> void:
	## 专服注入榜单与关卡进度实例；仅 SERVER 模式使用。
	_score_board = board


func scores_enabled() -> bool:
	return _score_board != null


func _username_of(peer: int) -> String:
	## 大厅用户名字符串（未登录 / 未启用账号时为空串）；写榜与进度查询的唯一来源。
	if _account_server == null or not _account_server.has_method("current_user"):
		return ""
	return String(_account_server.current_user(peer))


func send_register(username: String, salt_b64: String, verifier_b64: String) -> void:
	if mode == Mode.CLIENT:
		_rpc_register.rpc_id(1, username, salt_b64, verifier_b64)


func send_login_begin(username: String) -> void:
	if mode == Mode.CLIENT:
		_rpc_login_begin.rpc_id(1, username)


func send_login_proof(proof_b64: String) -> void:
	if mode == Mode.CLIENT:
		_rpc_login_proof.rpc_id(1, proof_b64)


func send_logout() -> void:
	if mode == Mode.CLIENT:
		_rpc_logout.rpc_id(1)


func send_room_create() -> void:
	if mode == Mode.CLIENT:
		_rpc_room_create.rpc_id(1)


func send_room_join(code: String) -> void:
	if mode == Mode.CLIENT:
		_rpc_room_join.rpc_id(1, code)


func send_room_leave() -> void:
	if mode == Mode.CLIENT:
		_rpc_room_leave.rpc_id(1)


func send_room_start() -> void:
	if mode == Mode.CLIENT:
		_rpc_room_start.rpc_id(1)


func send_room_config(level_id: int, difficulty_id: int) -> void:
	## 房主选关/选难度（M7）：仅 CLIENT 上行，服务端校验房主身份。
	if mode == Mode.CLIENT:
		_rpc_room_config.rpc_id(1, level_id, difficulty_id)


func send_progress_request() -> void:
	## 拉取本人关卡解锁进度（M7）：仅 CLIENT 上行。
	if mode == Mode.CLIENT:
		_rpc_progress_request.rpc_id(1)


func send_leaderboard_request(board: int, difficulty_id: int) -> void:
	## 拉取榜单（M7）：仅 CLIENT 上行；board ∈ {BOARD_WAVE, BOARD_SKILL}。
	if mode == Mode.CLIENT:
		_rpc_leaderboard_request.rpc_id(1, board, difficulty_id)


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
	_idle_resets_seen = 0
	_declared.clear()
	_handshake_deadlines.clear()
	_input_queue.clear()
	_snap_queue.clear()
	mode = Mode.HOST
	local_id = 0 if as_dedicated else 1
	_send_accum = 0.0
	_snap_accum = 0.0
	set_physics_process(true)
	if not as_dedicated:
		# 主机本地玩家开局即获得默认构筑（技能树起点），并同步下发一次技能树状态
		_host.set_initial_build(1)
		_emit_local_skill_state()
		player_joined.emit(1)
	return OK


func set_host_run_config(level_id: int, difficulty_id: int) -> void:
	## HOST：CLI/专服 game 模式覆盖本机权威模拟的关卡与难度（M7）；非 HOST 无操作。
	if mode == Mode.HOST:
		_host.set_run_config(level_id, difficulty_id)


func server_start(port: int, bind_ip: String = "") -> Error:
	## 大厅专服：单进程多房间（M6.3）。与 host_start 的区别是客户端上限按 ROOMS_CAPACITY（16）
	## 且不预置本地玩家；房间表与 peer→房间 路由交给 LobbyServer。
	if mode != Mode.NONE:
		return ERR_ALREADY_IN_USE
	var peer: MultiplayerPeer = null
	var err := OK
	if transport_ws:
		var ws := WebSocketMultiplayerPeer.new()
		err = ws.create_server(port, "*" if bind_ip.is_empty() else bind_ip)
		peer = ws
	else:
		var enet := ENetMultiplayerPeer.new()
		if not bind_ip.is_empty():
			enet.set_bind_ip(bind_ip)
		err = enet.create_server(port, LobbyLib.ROOMS_CAPACITY, 2)
		peer = enet
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	dedicated = true
	_lobby = LobbyServer.new(_account_server)
	_known_peers.clear()
	_run_over_sent = false
	_idle_resets_seen = 0
	_declared.clear()
	_handshake_deadlines.clear()
	_input_queue.clear()
	_snap_queue.clear()
	mode = Mode.SERVER
	local_id = 0
	_send_accum = 0.0
	_snap_accum = 0.0
	set_physics_process(true)
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
	_declared.clear()
	_handshake_deadlines.clear()
	_snap_queue.clear()
	_skill_points = 0
	_skill_nodes = []


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
	_hello_deadline = -1
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
	_hello_deadline = -1
	_skill_points = 0
	_skill_nodes = []


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
		_check_handshakes()
		_drain_input_queue()
		if not dedicated:
			# 主机本地玩家的输入在这里采样：不依赖场景树中是否恰好存在玩家节点
			_host.local_move = _read_local_move()
			_host.local_buttons = _read_buttons()
		if not _host.run_over:
			_host.physics_step(delta)
			_dispatch_host_fx()
			_announce_idle_reset()
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
			if not _host.run_over:
				_dispatch_host_elements()
	elif mode == Mode.SERVER:
		# 大厅专服：一条 peer 连接按 peer→房间 路由输入/快照/升级/结算，逐房驱动
		_check_handshakes()
		_drain_input_queue()
		if _lobby != null:
			_lobby.step(delta)
			_dispatch_room_fx()
			_offer_to_rooms()
			_check_rooms_run_over()
			_snap_accum += delta
			if _snap_accum >= 1.0 / float(Protocol.SNAPSHOT_RATE):
				_snap_accum = 0.0
				_send_room_snapshots()
				_dispatch_room_elements()
	elif mode == Mode.CLIENT:
		_check_hello()
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


func _offer_to_rooms() -> void:
	## SERVER：逐房下发升级候选（每房独立 NetHostLogic）。
	for code in _lobby.running_rooms():
		var logic = _lobby.logic_of(String(code))
		if logic == null:
			continue
		for peer in logic.peer_ids():
			var choices: Array = logic.pending_offer(peer)
			if choices.is_empty():
				continue
			_rpc_upgrade_offer.rpc_id(peer, PackedInt32Array(choices))


func _announce_idle_reset() -> void:
	## M5.2：专用服务器空场超时归零只发生一次（幂等），这里按计数变化上报一次信号供运维日志使用。
	if not dedicated or _host.idle_resets == _idle_resets_seen:
		return
	_idle_resets_seen = _host.idle_resets
	run_reset.emit(_host.idle_reset_seconds)


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


func _check_rooms_run_over() -> void:
	for code in _lobby.running_rooms():
		_check_room_run_over(String(code))


func _check_room_run_over(code: String) -> void:
	var logic = _lobby.logic_of(code)
	if logic == null or not logic.run_over:
		return
	var ids: PackedInt32Array = logic.peer_ids()
	var sample := 0 if ids.is_empty() else int(ids[0])
	var sample_stats: Dictionary = logic.stats(sample) if logic.has_player(sample) else {}
	run_over.emit(logic.won, sample_stats)
	for peer in ids:
		var stats: Dictionary = logic.stats(peer)
		_rpc_run_over.rpc_id(
			peer,
			logic.won,
			int(stats["kills"]),
			int(stats["level"]),
			int(stats["boss_kills"]),
			float(stats["seconds"])
		)
	# 结算不拆连接：房间回 WAITING、保留成员、换新地图，房主可再开一局（根治 F11）
	var members: PackedInt32Array = _lobby.members_of(code)
	_record_room_scores(code, logic)
	_lobby.finish_run(code)
	for peer in members:
		_rpc_room_state.rpc_id(
			int(peer),
			code,
			_lobby.is_host(int(peer)),
			LobbyLib.STATE.WAITING,
			_lobby.names_of(code)
		)
	lobby_event.emit("finished", code, sample)


func _record_room_scores(code: String, logic) -> void:
	## M7：一局结算时逐成员写榜（仅经大厅的在线局）。空用户名（未登录 / 未启用账号）
	## 一律跳过，且不落盘。关卡进度与双榜（波次 / 技能）均在此一次性写入。
	if _score_board == null or logic == null:
		return
	var at := int(Time.get_unix_time_from_system())
	for peer in _lobby.members_of(code):
		var uname := _username_of(int(peer))
		if uname.is_empty() or not logic.has_player(int(peer)):
			continue
		var stats: Dictionary = logic.stats(int(peer))
		var st: Dictionary = logic.skill_state(int(peer))
		_score_board.record(
			uname,
			int(logic.level_id),
			int(logic.difficulty_id),
			int(logic.wave),
			int(stats["kills"]),
			float(stats["seconds"]),
			int(stats["boss_kills"]),
			(st["nodes"] as Array).size(),
			at
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


func _send_room_snapshots() -> void:
	for code in _lobby.running_rooms():
		_send_room_snapshot(String(code))


func _send_room_snapshot(code: String) -> void:
	## 逐房快照：AoI 中心与裁剪只在**本房成员**上计算，避免跨房玩家位置混入。
	var logic = _lobby.logic_of(code)
	if logic == null:
		return
	var players: Array = logic.player_states()
	var enemies: Array = logic.enemy_states()
	var loot: Array = logic.loot_states()
	var projs_all: Array = logic.projectile_states()
	for peer in logic.peer_ids():
		if not logic.players.has(peer):
			continue
		var meta: Dictionary = logic.meta(peer)
		var center: Vector2 = logic.players[peer]["pos"]
		var culled_enemies := AoI.cull(center, AoI.AOI_RADIUS, enemies)
		var culled_loot := AoI.cull(center, AoI.AOI_RADIUS, loot)
		var culled_proj := AoI.cull(center, AoI.AOI_RADIUS, projs_all)
		var payload := Protocol.encode_snapshot(
			logic.tick, meta, players, culled_enemies, culled_loot, culled_proj
		)
		_rpc_snapshot.rpc_id(peer, logic.tick, payload)
	logic.snapshot_count += 1


func _drain_input_queue() -> void:
	if _input_queue.is_empty():
		return
	var now := Time.get_ticks_msec()
	var keep: Array = []
	for it in _input_queue:
		if int(it["due"]) <= now:
			if mode == Mode.SERVER:
				_apply_server_input(int(it["sender"]), it["payload"])
			else:
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


func _apply_server_input(sender: int, payload: PackedByteArray) -> void:
	## SERVER：输入按 peer→房间 分发；非本房成员一律丢弃。
	if _lobby == null:
		return
	var code: String = _lobby.room_of(sender)
	if code.is_empty():
		return
	var logic = _lobby.logic_of(code)
	if logic == null:
		return
	var f := Protocol.decode_input(payload)
	logic.set_remote_input(sender, f["move"], f["buttons"])
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
	if not _is_host_like():
		return
	# M6.2：不再「连接即入局」——先下发 hello，等客户端 declare 通过后再按角色放行
	_rpc_hello.rpc_id(id, desired_version())
	_handshake_deadlines[id] = Time.get_ticks_msec() + HANDSHAKE_TIMEOUT_MS


func _on_peer_disconnected(id: int) -> void:
	if not _is_host_like():
		return
	_handshake_deadlines.erase(id)
	_declared.erase(id)
	if _account_server != null:
		_account_server.on_peer_left(id)
	if mode == Mode.SERVER:
		_handle_server_peer_left(id)
		return
	if _host.has_player(id):
		_host.remove_player(id)
		player_left.emit(id)
		_broadcast_peer_list()


func _handle_server_peer_left(id: int) -> void:
	## SERVER：peer 离线 → 按 peer→房间 处理。房主离线立即销毁房间并通知其余成员；否则刷新成员列表。
	if _lobby == null:
		return
	var ev: Dictionary = _lobby.on_peer_left(id)
	var destroyed := String(ev["destroyed"])
	var affected: PackedInt32Array = ev["affected"]
	player_left.emit(id)
	if destroyed.is_empty():
		var code := ""
		if not affected.is_empty():
			code = String(_lobby.room_of(int(affected[0])))
		if not code.is_empty():
			_broadcast_room_state(code)
		lobby_event.emit("left", code, id)
		return
	for peer in affected:
		_rpc_room_error.rpc_id(int(peer), LobbyLib.ERR.ROOM_NOT_FOUND)
		_rpc_room_state.rpc_id(int(peer), "", false, LobbyLib.STATE.WAITING, PackedStringArray())
	lobby_event.emit("destroyed", destroyed, id)


func _admit(id: int) -> void:
	## declare 校验通过后按角色放行：ROLE_PLAYER 入局，ROLE_LOBBY 只占连接。
	## SERVER（大厅）模式：declare 通过即占连接，等房间 RPC；不入任何房间、不下发墙体。
	if mode == Mode.SERVER:
		return
	var info: Dictionary = _declared.get(id, {})
	if int(info.get("role", Protocol.ROLE_PLAYER)) != Protocol.ROLE_PLAYER:
		return
	_host.add_player(id)
	_host.set_initial_build(id)
	_rpc_room.rpc_id(id, Protocol.encode_room(_host.room_walls))
	_send_skill_state(id)
	player_joined.emit(id)
	_broadcast_peer_list()


func _on_connected_to_server() -> void:
	local_id = multiplayer.get_unique_id()
	_hello_deadline = Time.get_ticks_msec() + HANDSHAKE_TIMEOUT_MS
	connected_ok.emit(local_id)


func _on_connection_failed() -> void:
	mode = Mode.NONE
	set_physics_process(false)
	multiplayer.multiplayer_peer = null
	_hello_deadline = -1
	connection_failed.emit()


func _on_server_disconnected() -> void:
	mode = Mode.NONE
	set_physics_process(false)
	multiplayer.multiplayer_peer = null
	_hello_deadline = -1
	disconnected.emit()


func _check_handshakes() -> void:
	if _handshake_deadlines.is_empty():
		return
	var now := Time.get_ticks_msec()
	for peer in _handshake_deadlines.keys():
		if now < int(_handshake_deadlines[peer]):
			continue
		printerr("[Net] declare timeout peer=%d" % peer)
		_handshake_deadlines.erase(peer)


func _check_hello() -> void:
	if _hello_deadline < 0 or Time.get_ticks_msec() < _hello_deadline:
		return
	_hello_deadline = -1
	printerr("[Net] hello timeout from server")
	_disconnect_after_mismatch()


func _disconnect_after_mismatch() -> void:
	## 延迟 0.5s 断开：给上行的 declare 留送达窗口，便于服务端日志取证。
	await get_tree().create_timer(0.5).timeout
	if mode == Mode.CLIENT:
		client_disconnect()


func _broadcast_peer_list() -> void:
	_rpc_peer_list.rpc(_host.peer_ids())


func _broadcast_room_state(code: String) -> void:
	## SERVER：把房间快照下发给房内全部成员（成员列表用大厅用户名，房主首位）。
	if _lobby == null or code.is_empty():
		return
	var members: PackedInt32Array = _lobby.members_of(code)
	if members.is_empty():
		return
	var names: PackedStringArray = _lobby.names_of(code)
	var state := int(_lobby.state_of(code))
	for peer in members:
		_rpc_room_state.rpc_id(int(peer), code, _lobby.is_host(int(peer)), state, names)


func _broadcast_room_config(code: String) -> void:
	## SERVER：把房间当前关卡/难度下发房内全部成员（M7）；不做任何二进制帧改动。
	if _lobby == null or code.is_empty():
		return
	var cfg: Dictionary = _lobby.config_of(code)
	for peer in _lobby.members_of(code):
		_rpc_room_config.rpc_id(int(peer), int(cfg["level_id"]), int(cfg["difficulty_id"]))


# ---------------- RPC ----------------

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _rpc_input(_tick_in: int, payload: PackedByteArray) -> void:
	if mode == Mode.SERVER:
		_rpc_input_server(payload)
		return
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


func _rpc_input_server(payload: PackedByteArray) -> void:
	var who := multiplayer.get_remote_sender_id()
	if who == 0:
		return
	if debug_latency_ms > 0:
		_input_queue.append(
			{"due": Time.get_ticks_msec() + debug_latency_ms, "payload": payload, "sender": who}
		)
		return
	_apply_server_input(who, payload)


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
	if mode != Mode.CLIENT or role != Protocol.ROLE_PLAYER:
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
	var sender := multiplayer.get_remote_sender_id()
	if mode == Mode.SERVER:
		if sender == 0 or _lobby == null:
			return
		var code: String = _lobby.room_of(sender)
		if code.is_empty():
			return
		var logic = _lobby.logic_of(code)
		if logic == null:
			return
		if logic.apply_choice(sender, card_id):
			player_upgrade.emit(sender, card_id)
		return
	if mode != Mode.HOST:
		return
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


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_hello(server_version: int) -> void:
	if mode != Mode.CLIENT:
		return
	_hello_deadline = -1
	if server_version != desired_version():
		printerr("[Net] version mismatch server=%d client=%d" % [server_version, desired_version()])
		version_mismatch.emit(server_version)
		_disconnect_after_mismatch()
		return
	_rpc_declare.rpc_id(1, desired_version(), role)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_login_challenge(salt_b64: String, nonce_b64: String, err_code: int) -> void:
	if mode != Mode.CLIENT:
		return
	if err_code != AccountLib.ERR.OK:
		auth_result.emit(false, "", err_code)
		return
	auth_challenge.emit(salt_b64, nonce_b64)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_auth_result(op: int, ok: bool, username: String, err_code: int) -> void:
	if mode != Mode.CLIENT:
		return
	match op:
		Protocol.OP_REGISTER:
			account_registered.emit(ok, err_code)
		Protocol.OP_LOGIN:
			auth_result.emit(ok, username, err_code)
		Protocol.OP_LOGOUT:
			account_session_closed.emit()


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_declare(client_version: int, peer_role: int) -> void:
	if not _is_host_like():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or sender == 1:
		return
	_handshake_deadlines.erase(sender)
	if client_version != desired_version():
		printerr(
			(
				"[Net] declare rejected peer=%d version=%d want=%d"
				% [sender, client_version, desired_version()]
			)
		)
		return
	_declared[sender] = {"version": client_version, "role": peer_role}
	_admit(sender)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_register(username: String, salt_b64: String, verifier_b64: String) -> void:
	if not _is_host_like():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or sender == 1:
		return
	var code := AccountLib.ERR.UNSUPPORTED
	if _account_server != null:
		code = _account_server.register(sender, username, salt_b64, verifier_b64)
	account_registered.emit(code == AccountLib.ERR.OK, code)  # 偏离 9：HOST 侧也发一份，供专服打日志
	_rpc_auth_result.rpc_id(sender, Protocol.OP_REGISTER, code == AccountLib.ERR.OK, username, code)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_login_begin(username: String) -> void:
	if not _is_host_like():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or sender == 1:
		return
	if _account_server == null:
		_rpc_login_challenge.rpc_id(sender, "", "", AccountLib.ERR.UNSUPPORTED)
		return
	var res: Dictionary = _account_server.begin_login(sender, username)
	if not bool(res["ok"]):
		_rpc_login_challenge.rpc_id(sender, "", "", int(res["err"]))
		return
	_rpc_login_challenge.rpc_id(
		sender, String(res["salt"]), String(res["nonce"]), AccountLib.ERR.OK
	)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_login_proof(proof_b64: String) -> void:
	if not _is_host_like():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or sender == 1:
		return
	var code := AccountLib.ERR.UNSUPPORTED
	var uname := ""
	if _account_server != null:
		var res: Dictionary = _account_server.finish_login(sender, proof_b64)
		code = int(res["err"])
		uname = String(res["username"])
	_rpc_auth_result.rpc_id(sender, Protocol.OP_LOGIN, code == AccountLib.ERR.OK, uname, code)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_logout() -> void:
	if not _is_host_like():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or sender == 1:
		return
	if _account_server != null:
		_account_server.logout(sender)
	account_session_closed.emit()  # 偏离 9：HOST 侧也发一份，供专服打日志
	_rpc_auth_result.rpc_id(sender, Protocol.OP_LOGOUT, true, "", AccountLib.ERR.OK)


# ---------------- 房间 RPC（大厅专服，M6.3） ----------------

@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_room_create() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if mode == Mode.HOST:
		if sender != 0:
			_rpc_room_error.rpc_id(sender, LobbyLib.ERR.UNSUPPORTED)
		return
	if mode != Mode.SERVER or sender == 0 or _lobby == null:
		return
	var res: Dictionary = _lobby.create_room(sender)
	if not bool(res["ok"]):
		_rpc_room_error.rpc_id(sender, int(res["err"]))
		return
	var code := String(res["code"])
	_broadcast_room_state(code)
	_broadcast_room_config(code)
	lobby_event.emit("created", code, sender)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_room_join(code: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if mode == Mode.HOST:
		if sender != 0:
			_rpc_room_error.rpc_id(sender, LobbyLib.ERR.UNSUPPORTED)
		return
	if mode != Mode.SERVER or sender == 0 or _lobby == null:
		return
	var res: Dictionary = _lobby.join_room(sender, code)
	if not bool(res["ok"]):
		_rpc_room_error.rpc_id(sender, int(res["err"]))
		return
	var joined := String(res["code"])
	var logic = _lobby.logic_of(joined)
	if logic != null:
		_rpc_room.rpc_id(sender, Protocol.encode_room(logic.room_walls))
	_broadcast_room_state(joined)
	_broadcast_room_config(joined)
	lobby_event.emit("joined", joined, sender)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_room_leave() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if mode == Mode.HOST:
		if sender != 0:
			_rpc_room_error.rpc_id(sender, LobbyLib.ERR.UNSUPPORTED)
		return
	if mode != Mode.SERVER or sender == 0 or _lobby == null:
		return
	var code: String = _lobby.room_of(sender)
	if code.is_empty():
		_rpc_room_error.rpc_id(sender, LobbyLib.ERR.NOT_IN_ROOM)
		return
	var was_host: bool = _lobby.is_host(sender)
	var others: PackedInt32Array = _lobby.members_of(code)
	_lobby.leave_room(sender)
	_rpc_room_state.rpc_id(sender, "", false, LobbyLib.STATE.WAITING, PackedStringArray())
	if was_host:
		for peer in others:
			if int(peer) == sender:
				continue
			_rpc_room_error.rpc_id(int(peer), LobbyLib.ERR.ROOM_NOT_FOUND)
			_rpc_room_state.rpc_id(
				int(peer), "", false, LobbyLib.STATE.WAITING, PackedStringArray()
			)
		lobby_event.emit("destroyed", code, sender)
	else:
		_broadcast_room_state(code)
		lobby_event.emit("left", code, sender)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_room_start() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if mode == Mode.HOST:
		if sender != 0:
			_rpc_room_error.rpc_id(sender, LobbyLib.ERR.UNSUPPORTED)
		return
	if mode != Mode.SERVER or sender == 0 or _lobby == null:
		return
	var res: Dictionary = _lobby.start_run(sender)
	if not bool(res["ok"]):
		_rpc_room_error.rpc_id(sender, int(res["err"]))
		return
	var code := String(res["code"])
	var logic = _lobby.logic_of(code)
	if logic != null:
		for peer in _lobby.members_of(code):
			logic.set_initial_build(int(peer))
			_rpc_room.rpc_id(int(peer), Protocol.encode_room(logic.room_walls))
			_send_room_skill_state(logic, int(peer))
	_broadcast_room_state(code)
	_broadcast_room_config(code)
	lobby_event.emit("started", code, sender)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_room_config(level_id: int, difficulty_id: int) -> void:
	## 复用为双向下发：SERVER 侧受理房主上行 → set_room_config → 广播；CLIENT 侧收到后 emit。
	if mode == Mode.CLIENT:
		room_config.emit(level_id, difficulty_id)
		return
	if mode != Mode.SERVER or _lobby == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	var res: Dictionary = _lobby.set_room_config(sender, level_id, difficulty_id)
	if not bool(res["ok"]):
		_rpc_room_error.rpc_id(sender, int(res["err"]))
		return
	_broadcast_room_config(String(res["code"]))
	lobby_event.emit("config", String(res["code"]), sender)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_room_state(code: String, is_host: bool, state: int, members: PackedStringArray) -> void:
	if mode != Mode.CLIENT:
		return
	if state == LobbyLib.STATE.RUNNING:
		# 结算不拆连接：新一局开局必须解除上一局的结算冻结，否则客户端不再上报输入、
		# 本地预测与弹丸也被 is_run_over() 冻结，第二局会整屏僵死
		_client.run_over = false
		_client.pending_move = Vector2.ZERO
		_client.pending_buttons = 0
	room_state.emit(code, is_host, state, members)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_room_error(err: int) -> void:
	if mode != Mode.CLIENT:
		return
	room_error.emit(err)


# ---------------- 榜单与关卡进度 RPC（M7，控制通道） ----------------

@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_progress_request() -> void:
	if mode != Mode.SERVER or _score_board == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	_send_progress(sender)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_progress_data(cleared: PackedInt32Array, best_wave: PackedInt32Array) -> void:
	if mode != Mode.CLIENT:
		return
	progress_data.emit(cleared, best_wave)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_leaderboard_request(board: int, difficulty_id: int) -> void:
	if mode != Mode.SERVER or _score_board == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	_send_leaderboard(sender, board, difficulty_id)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_leaderboard_data(board: int, difficulty_id: int, rows: Array) -> void:
	if mode != Mode.CLIENT:
		return
	leaderboard_data.emit(board, difficulty_id, rows)


func _send_progress(peer: int) -> void:
	var prog: Dictionary = _score_board.progress_of(_username_of(peer))
	_rpc_progress_data.rpc_id(peer, prog["cleared"], prog["best_wave"])


func _send_leaderboard(peer: int, board: int, difficulty_id: int) -> void:
	var rows: Array = []
	if board == Protocol.BOARD_SKILL:
		rows = _score_board.leaderboard_skill()
	elif board == Protocol.BOARD_WAVE:
		rows = _score_board.leaderboard_wave(difficulty_id)
	_rpc_leaderboard_data.rpc_id(peer, board, difficulty_id, rows)


# ---------------- 技能树与动态特效（子项目 5） ----------------


func local_skill_state() -> Dictionary:
	## UI 读取当前玩家的技能树状态：HOST 取权威，CLIENT 取最近一次下发副本。
	if mode == Mode.HOST:
		if _host.has_player(1):
			return _host.skill_state(1)
		return {"points": 0, "nodes": []}
	if mode == Mode.CLIENT:
		return {"points": _skill_points, "nodes": _skill_nodes.duplicate()}
	return {"points": 0, "nodes": []}


func send_skill_unlock(node_id: int) -> void:
	## UI 解锁技能节点：客户端上行请求，主机本地直接结算。
	if mode == Mode.CLIENT:
		_rpc_skill_unlock.rpc_id(1, node_id)
	elif mode == Mode.HOST:
		if _host.unlock_skill(1, node_id):
			_emit_local_skill_state()
			player_skill_unlock.emit(1, node_id)


func set_local_build(preset_id: String = "") -> void:
	## 更换本地玩家的初始构筑（技能树起点），仅 HOST 生效。
	if mode == Mode.HOST and _host.has_player(1):
		_host.set_initial_build(1, preset_id)
		_emit_local_skill_state()


func _emit_local_skill_state() -> void:
	var st := local_skill_state()
	skill_state_changed.emit(int(st["points"]), PackedInt32Array(st["nodes"]))


func _send_skill_state(peer: int) -> void:
	var st: Dictionary = _host.skill_state(peer)
	_rpc_skill_state.rpc_id(peer, int(st["points"]), PackedInt32Array(st["nodes"]))


func _send_room_skill_state(logic, peer: int) -> void:
	var st: Dictionary = logic.skill_state(peer)
	_rpc_skill_state.rpc_id(peer, int(st["points"]), PackedInt32Array(st["nodes"]))


func _dispatch_host_fx() -> void:
	## HOST：本帧特效本地直显（非专服）并广播给远端 peer。
	var evs := _host.take_fx_events()
	if evs.is_empty():
		return
	var alive := multiplayer.get_peers()  # 已断开的对端 ready_state != STATE_OPEN，发了会逐帧刷屏报错
	for ev in evs:
		var k := int(ev["kind"])
		var pos: Vector2 = ev["pos"]
		var radius := float(ev["radius"])
		var dir: Vector2 = ev.get("dir", Vector2.ZERO)  # 方向性特效（激光/吸血）用
		if not dedicated:
			fx.emit(k, pos, dir, radius)
		for peer in _host.peer_ids():
			if peer == 1 or not alive.has(peer):
				continue
			_rpc_fx.rpc_id(peer, k, pos, dir, radius)


func _dispatch_room_fx() -> void:
	## SERVER：逐房把本帧特效广播给房内全部成员。
	if _lobby == null:
		return
	var alive := multiplayer.get_peers()  # 已断开的对端 ready_state != STATE_OPEN，发了会逐帧刷屏报错
	for code in _lobby.running_rooms():
		var logic = _lobby.logic_of(String(code))
		if logic == null:
			continue
		var evs: Array = logic.take_fx_events()
		if evs.is_empty():
			continue
		var members: PackedInt32Array = _lobby.members_of(String(code))
		for peer in members:
			if peer == 1 or not alive.has(peer):
				continue
			for ev in evs:
				_rpc_fx.rpc_id(
					int(peer),
					int(ev["kind"]),
					ev["pos"],
					ev.get("dir", Vector2.ZERO),
					float(ev["radius"])
				)


func _dispatch_host_elements() -> void:
	## HOST：把元素状态同步给本机渲染（非专服）与远端 peer；空列表直接跳过，客户端靠 TTL 自行褪色。
	var ids := PackedInt32Array()
	var elems := PackedByteArray()
	for it in _host.element_states():
		ids.append(int(it["id"]))
		elems.append(int(it["elem"]))
	if ids.is_empty():
		return
	if not dedicated:
		enemy_elements.emit(ids, elems)
	var alive := multiplayer.get_peers()  # 已断开的对端发了会逐帧刷屏报错
	for peer in _host.peer_ids():
		if peer == 1 or not alive.has(peer):
			continue
		_rpc_enemy_elements.rpc_id(peer, ids, elems)


func _dispatch_room_elements() -> void:
	## SERVER：逐房把元素状态同步给房内成员（同样只在有元素时发）。
	if _lobby == null:
		return
	var alive := multiplayer.get_peers()
	for code in _lobby.running_rooms():
		var logic = _lobby.logic_of(String(code))
		if logic == null:
			continue
		var ids := PackedInt32Array()
		var elems := PackedByteArray()
		for it in logic.element_states():
			ids.append(int(it["id"]))
			elems.append(int(it["elem"]))
		if ids.is_empty():
			continue
		var members: PackedInt32Array = _lobby.members_of(String(code))
		for peer in members:
			if peer == 1 or not alive.has(peer):
				continue
			_rpc_enemy_elements.rpc_id(int(peer), ids, elems)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_skill_unlock(node_id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if mode == Mode.SERVER:
		if sender == 0 or _lobby == null:
			return
		var code: String = _lobby.room_of(sender)
		if code.is_empty():
			return
		var logic = _lobby.logic_of(code)
		if logic == null:
			return
		if logic.unlock_skill(sender, node_id):
			player_skill_unlock.emit(sender, node_id)
			_send_room_skill_state(logic, sender)
		return
	if mode != Mode.HOST:
		return
	if sender == 0 or sender == 1:
		return
	if _host.unlock_skill(sender, node_id):
		player_skill_unlock.emit(sender, node_id)
		_send_skill_state(sender)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_skill_state(points: int, nodes: PackedInt32Array) -> void:
	if mode != Mode.CLIENT:
		return
	_skill_points = points
	_skill_nodes = Array(nodes)
	skill_state_changed.emit(points, nodes)


@rpc("authority", "call_remote", "unreliable", 1)
func _rpc_fx(kind: int, pos: Vector2, dir: Vector2, radius: float) -> void:
	if mode != Mode.CLIENT:
		return
	fx.emit(kind, pos, dir, radius)


@rpc("authority", "call_remote", "unreliable", 1)
func _rpc_enemy_elements(ids: PackedInt32Array, elems: PackedByteArray) -> void:
	## 元素状态走独立稀疏通道（不动快照线格式）；丢包由「按快照节拍重发 + 客户端 TTL」自愈。
	if mode != Mode.CLIENT:
		return
	enemy_elements.emit(ids, elems)

# gdlint:ignore=max-file-lines
