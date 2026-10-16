extends RefCounted  # gdlint:ignore=max-public-methods
## 大厅服务端（单进程多房间）纯逻辑：房间表 + peer→房间 路由 + 房间生命周期 +
## 每房独立 NetHostLogic 驱动。不含任何网络/磁盘依赖，也不发任何 RPC；
## 由 autoload/net.gd 在 SERVER 模式驱动，收发 RPC 与房间广播均由 net.gd 执行。
## 注：房间表查询/配置/生命周期等公共方法数必然超过 gdlint 默认上限 20，故第 1 行显式豁免。

const Lobby := preload("res://net/lobby.gd")
const Levels := preload("res://sim/levels.gd")
const NetHostLogic := preload("res://net/net_host.gd")
const Protocol := preload("res://net/protocol.gd")

const JOIN_FAIL_WINDOW_MS := 10000  # 入房失败计数滑窗
const JOIN_FAIL_LIMIT := 5  # 窗口内失败上限
const JOIN_COOLDOWN_MS := 30000  # 触发上限后的冷却时长（防组队码爆破）

var room_rng := RandomNumberGenerator.new()  # 生成组队码与房间种子；公开以便单测注入固定 seed 复现
var test_clock_ms := -1  # >= 0 时替代真实时钟（仅供单测注入）

var _rooms: Dictionary = {}  # code(String) -> {code, host, members, state, logic, empty_seconds}
var _peer_room: Dictionary = {}  # peer(int) -> code(String)
var _accounts = null  # 注入的账号服务（具备 current_user(peer)->String 即可）
var _join_fails: Dictionary = {}  # peer -> Array[int]（失败毫秒时间戳）
var _join_cooldown: Dictionary = {}  # peer -> int（冷却截止毫秒）
var _used_seeds: Dictionary = {}  # 保证同存房间种子互不相同


func _init(account_server = null) -> void:
	_accounts = account_server


func now_ms() -> int:
	return test_clock_ms if test_clock_ms >= 0 else Time.get_ticks_msec()


func create_room(peer: int) -> Dictionary:
	if _username(peer).is_empty():
		return {"ok": false, "err": Lobby.ERR.NOT_LOGGED_IN, "code": ""}
	if not room_of(peer).is_empty():
		return {"ok": false, "err": Lobby.ERR.ALREADY_IN_ROOM, "code": ""}
	if _rooms.size() >= Lobby.MAX_ROOMS:
		return {"ok": false, "err": Lobby.ERR.ROOM_LIMIT, "code": ""}
	var taken := {}
	for existing in _rooms:
		taken[existing] = true
	var code := Lobby.make_code(room_rng, taken)
	if code.is_empty():
		return {"ok": false, "err": Lobby.ERR.INTERNAL, "code": ""}
	var members: Array[int] = [peer]
	var room := {
		"code": code,
		"host": peer,
		"members": members,
		"state": Lobby.STATE.WAITING,
		"logic": null,
		"empty_seconds": 0.0,
		"level_id": Lobby.DEFAULT_LEVEL,
		"difficulty_id": Lobby.DEFAULT_DIFFICULTY,
	}
	_rooms[code] = room
	_peer_room[peer] = code
	_reset_room_logic(room)
	return {"ok": true, "err": Lobby.ERR.OK, "code": code}


func join_room(peer: int, code: String) -> Dictionary:
	if _username(peer).is_empty():
		return {"ok": false, "err": Lobby.ERR.NOT_LOGGED_IN, "limited": false}
	if not room_of(peer).is_empty():
		return {"ok": false, "err": Lobby.ERR.ALREADY_IN_ROOM, "limited": false}
	if _join_limited(peer):
		return {"ok": false, "err": Lobby.ERR.ROOM_NOT_FOUND, "limited": true}
	return _join_checked(peer, code)


func leave_room(peer: int) -> Dictionary:
	var code := room_of(peer)
	if code.is_empty():
		return {"ok": false, "err": Lobby.ERR.NOT_IN_ROOM, "code": ""}
	if is_host(peer):
		destroy_room(code, "host_leave")
		return {"ok": true, "err": Lobby.ERR.OK, "code": code}
	_remove_member(code, peer)
	return {"ok": true, "err": Lobby.ERR.OK, "code": code}


func start_run(peer: int) -> Dictionary:
	var code := room_of(peer)
	if code.is_empty():
		return {"ok": false, "err": Lobby.ERR.NOT_IN_ROOM, "code": ""}
	if not is_host(peer):
		return {"ok": false, "err": Lobby.ERR.NOT_HOST, "code": code}
	var room: Dictionary = _rooms[code]
	if int(room["state"]) != Lobby.STATE.WAITING:
		return {"ok": false, "err": Lobby.ERR.BAD_STATE, "code": code}
	_reset_room_logic(room)
	var logic: NetHostLogic = room["logic"]
	for id in room["members"]:
		logic.add_player(int(id))
	room["state"] = Lobby.STATE.RUNNING
	return {"ok": true, "err": Lobby.ERR.OK, "code": code}


func finish_run(code: String) -> void:
	## 供 net.gd 在发完 _rpc_run_over 后调用：结算不拆连接，只把房间置回 WAITING 并换新地图。
	if not _rooms.has(code):
		return
	var room: Dictionary = _rooms[code]
	room["state"] = Lobby.STATE.FINISHED
	_reset_room_logic(room)
	room["state"] = Lobby.STATE.WAITING


func room_of(peer: int) -> String:
	return String(_peer_room.get(peer, ""))


func set_room_config(peer: int, new_level_id: int, new_difficulty_id: int) -> Dictionary:
	## 房主在等待期选择关卡与难度；开局后锁定（BAD_STATE），避免局中改配置造成数值跳变。
	var code := room_of(peer)
	if code.is_empty():
		return {"ok": false, "err": Lobby.ERR.NOT_IN_ROOM, "code": ""}
	if not is_host(peer):
		return {"ok": false, "err": Lobby.ERR.NOT_HOST, "code": code}
	if not Levels.is_valid_level(new_level_id) or not Levels.is_valid_difficulty(new_difficulty_id):
		return {"ok": false, "err": Lobby.ERR.INTERNAL, "code": code}
	var room: Dictionary = _rooms[code]
	if int(room["state"]) != Lobby.STATE.WAITING:
		return {"ok": false, "err": Lobby.ERR.BAD_STATE, "code": code}
	room["level_id"] = new_level_id
	room["difficulty_id"] = new_difficulty_id
	var logic: NetHostLogic = room["logic"]
	if logic != null:
		logic.set_run_config(new_level_id, new_difficulty_id)
	return {"ok": true, "err": Lobby.ERR.OK, "code": code}


func level_of(code: String) -> int:
	if not _rooms.has(code):
		return Lobby.DEFAULT_LEVEL
	return int(_rooms[code]["level_id"])


func difficulty_of(code: String) -> int:
	if not _rooms.has(code):
		return Lobby.DEFAULT_DIFFICULTY
	return int(_rooms[code]["difficulty_id"])


func config_of(code: String) -> Dictionary:
	if not _rooms.has(code):
		return {"level_id": Lobby.DEFAULT_LEVEL, "difficulty_id": Lobby.DEFAULT_DIFFICULTY}
	return {"level_id": level_of(code), "difficulty_id": difficulty_of(code)}


func is_host(peer: int) -> bool:
	var code := room_of(peer)
	if code.is_empty() or not _rooms.has(code):
		return false
	return int(_rooms[code]["host"]) == peer


func state_of(code: String) -> int:
	if not _rooms.has(code):
		return -1
	return int(_rooms[code]["state"])


func members_of(code: String) -> PackedInt32Array:
	return _members_packed(code)


func names_of(code: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not _rooms.has(code):
		return out
	for id in _rooms[code]["members"]:
		out.append(_username(int(id)))
	return out


func destroy_room(code: String, _reason: String = "") -> void:
	## _reason 仅保留供上层日志使用，本模块不打印；清房间时同步清所有 peer→code 映射。
	if not _rooms.has(code):
		return
	_rooms.erase(code)
	for peer in _peer_room.keys():
		if String(_peer_room[peer]) == code:
			_peer_room.erase(peer)


func on_peer_left(peer: int) -> Dictionary:
	var code := room_of(peer)
	if code.is_empty():
		return {"destroyed": "", "affected": PackedInt32Array()}
	var room: Dictionary = _rooms[code]
	if int(room["host"]) == peer:
		var affected := PackedInt32Array()
		for id in room["members"]:
			if int(id) != peer:
				affected.append(int(id))
		destroy_room(code, "host_left")
		return {"destroyed": code, "affected": affected}
	_remove_member(code, peer)
	return {"destroyed": "", "affected": _members_packed(code)}


func step(delta: float) -> void:
	var codes := _rooms.keys()
	for code in codes:
		var room: Dictionary = _rooms[code]
		if int(room["state"]) == Lobby.STATE.RUNNING and room["logic"] != null:
			var logic: NetHostLogic = room["logic"]
			if not logic.run_over:
				logic.physics_step(delta)
		if room["members"].is_empty():
			room["empty_seconds"] = float(room["empty_seconds"]) + delta
			if float(room["empty_seconds"]) >= Lobby.EMPTY_ROOM_TTL_S:
				destroy_room(String(code), "empty")
		else:
			room["empty_seconds"] = 0.0


func running_rooms() -> Array:
	var out: Array[String] = []
	for code in _rooms:
		if int(_rooms[code]["state"]) == Lobby.STATE.RUNNING:
			out.append(String(code))
	return out


func logic_of(code: String):
	if not _rooms.has(code):
		return null
	return _rooms[code]["logic"]


func room_count() -> int:
	return _rooms.size()


func _username(peer: int) -> String:
	if _accounts == null or not _accounts.has_method("current_user"):
		return ""
	return String(_accounts.current_user(peer))


func _reset_room_logic(room: Dictionary) -> void:
	var logic: NetHostLogic = NetHostLogic.new()
	logic.reset(true, _new_seed())
	logic.set_run_config(int(room["level_id"]), int(room["difficulty_id"]))
	room["logic"] = logic


func _new_seed() -> int:
	var seed := room_rng.randi()
	while _used_seeds.has(seed):
		seed = room_rng.randi()
	_used_seeds[seed] = true
	return seed


func _remove_member(code: String, peer: int) -> void:
	if not _rooms.has(code):
		return
	var members: Array[int] = _rooms[code]["members"]
	members.erase(peer)
	_peer_room.erase(peer)


func _members_packed(code: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not _rooms.has(code):
		return out
	for id in _rooms[code]["members"]:
		out.append(int(id))
	return out


func _join_checked(peer: int, code: String) -> Dictionary:
	if not Lobby.is_valid_code(code):
		_record_join_fail(peer)
		return {"ok": false, "err": Lobby.ERR.BAD_CODE, "limited": false}
	if not _rooms.has(code):
		_record_join_fail(peer)
		return {"ok": false, "err": Lobby.ERR.ROOM_NOT_FOUND, "limited": false}
	var room: Dictionary = _rooms[code]
	if room["members"].size() >= Protocol.MAX_PLAYERS:
		return {"ok": false, "err": Lobby.ERR.ROOM_FULL, "limited": false}
	room["members"].append(peer)
	_peer_room[peer] = code
	return {"ok": true, "err": Lobby.ERR.OK, "code": code, "limited": false}


func _join_limited(peer: int) -> bool:
	return _join_cooldown.has(peer) and now_ms() < int(_join_cooldown[peer])


func _record_join_fail(peer: int) -> void:
	var now := now_ms()
	var keep: Array = []
	for ts in _join_fails.get(peer, []):
		if now - int(ts) <= JOIN_FAIL_WINDOW_MS:
			keep.append(ts)
	keep.append(now)
	if keep.size() >= JOIN_FAIL_LIMIT:
		_join_cooldown[peer] = now + JOIN_COOLDOWN_MS
		_join_fails[peer] = []
	else:
		_join_fails[peer] = keep
