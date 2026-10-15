extends Node
## M6.3 大厅/组队码 E2E 冒烟 —— 客户端。
## 由 run_lobby_test.ps1（notlogged / badcode / host / seat / full）与
## run_lobby_concurrent_test.ps1（concurrent）逐阶段带参数启动。
## 固定走 WebSocket：Account.connect_lobby 内部即 Net.set_websocket(true)，故专服必须 --transport=ws。
## 所有自定义参数都读自 OS.get_cmdline_user_args()，必须写在独立 `--` 之后。

const LobbyLib := preload("res://net/lobby.gd")

const BAD_CANDIDATES := ["999999", "888888", "777777"]
const DEFAULT_TIMEOUT := 45.0
const HOST_TIMEOUT := 200.0  # host 要跑完一整局（含等队友 + 结算 + 再来一局）
# 每房地图种子随机 → 单局时长波动大；墙体移除后玩家不再被墙卡住、单局更易拖长，故预算留足
const DEFAULT_LINGER := 30.0  # seat 默认留房时长
const MEMBER_SETTLE := 2.5  # host 见到第 2 名队友后再等这么久，确保其余座位入房后才开局
const WAIT_GRACE := 1.5  # 结算后等 room_state 回落 WAITING 的宽限

var _stage := ""
var _ip := "127.0.0.1"
var _port := 0
var _user := ""
var _password := "pw123456"
var _code := ""
var _codefile := ""
var _expect := ""
var _linger := -1.0
var _delay := 0.0

var _t := 0.0
var _done := false
var _snaps := 0
var _wave_seen := false
var _walls_seen := false
var _saw_running := false
var _run_over := false
var _run_over_at := -1.0
var _self_pos := Vector2.ZERO
var _have_self := false
var _enemy_dir := Vector2.ZERO
var _second_start := Vector2.ZERO  # 第二局起点：仅靠位移能判别输入是否随新一局恢复
var _second_start_set := false
var _second_moved := false
var _second_at := -1.0

var _phase := 0
var _member_since := -1.0
var _bad_idx := 0
var _linger_until := -1.0
var _delay_until := -1.0
var _sent_join := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			_stage = a.substr(8)
		elif a.begins_with("--ip="):
			_ip = a.substr(5)
		elif a.begins_with("--port="):
			_port = int(a.substr(7))
		elif a.begins_with("--user="):
			_user = a.substr(7)
		elif a.begins_with("--pass="):
			_password = a.substr(7)
		elif a.begins_with("--code="):
			_code = a.substr(7)
		elif a.begins_with("--codefile="):
			_codefile = a.substr(11)
		elif a.begins_with("--expect="):
			_expect = a.substr(9)
		elif a.begins_with("--linger="):
			_linger = float(a.substr(9))
		elif a.begins_with("--delay="):
			_delay = float(a.substr(8))
	Net.connected_ok.connect(_on_connected)
	Net.connection_failed.connect(_on_connection_failed)
	Net.world_state.connect(_on_world_state)
	Net.run_over.connect(_on_run_over)
	Account.register_ok.connect(_on_register_ok)
	Account.register_failed.connect(_on_register_failed)
	Account.login_ok.connect(_on_login_ok)
	Account.login_failed.connect(_on_login_failed)
	Lobby.room_updated.connect(_on_room_updated)
	Account.connect_lobby(_ip, _port)


func _process(delta: float) -> void:
	_t += delta
	if _done:
		return
	if _t > _stage_timeout():
		_fail("timeout t=%.1f" % _t)
		return
	match _stage:
		"notlogged":
			_proc_notlogged()
		"badcode":
			_proc_badcode()
		"host":
			_proc_host()
		"seat":
			_proc_seat()
		"full":
			_proc_full()
		"concurrent":
			_proc_concurrent()


func _physics_process(_delta: float) -> void:
	## 自杀式冲锋：无输入时波次推进很慢，主动每帧向最近敌人移动可加速「跑完一局」。
	if _done or _run_over or not _have_self:
		return
	if _stage != "host" and _stage != "seat" and _stage != "concurrent":
		return
	Net.send_local_input(_enemy_dir, 0)


# ---------------- 连接 / 账号事件 ----------------


func _on_connected(_local_id: int) -> void:
	if _stage == "notlogged":
		Lobby.create_room()
	else:
		Account.register(_user, _password)


func _on_connection_failed() -> void:
	_fail("connection_failed")


func _on_register_ok(_uname: String) -> void:
	Account.login(_user, _password)


func _on_register_failed(reason: String) -> void:
	_fail("register_failed: %s" % reason)


func _on_login_ok(_uname: String) -> void:
	match _stage:
		"badcode":
			_join_candidate()
		"host", "concurrent":
			Lobby.create_room()
		"seat":
			Lobby.join_room(_code)
		"full":
			_delay_until = _t + _delay
		_:
			pass


func _on_login_failed(reason: String) -> void:
	_fail("login_failed: %s" % reason)


func _on_room_updated() -> void:
	if Lobby.room_state == LobbyLib.STATE.RUNNING:
		_saw_running = true


func _on_world_state(
	_tick: int, meta: Dictionary, players: Array, enemies: Array, _loot: Array, _proj: Array
) -> void:
	_snaps += 1
	if int(meta.get("wave", 0)) >= 1:
		_wave_seen = true
	if Net.room_walls().is_empty():
		_walls_seen = true
	_have_self = false
	for p in players:
		if int(p["id"]) == Net.local_id:
			_self_pos = p["pos"]
			_have_self = true
	if _phase == 4 and _have_self:
		if not _second_start_set:
			_second_start = _self_pos
			_second_start_set = true
		elif _self_pos.distance_to(_second_start) > 24.0:
			_second_moved = true
	_enemy_dir = Vector2.ZERO
	if not _have_self or enemies.is_empty():
		return
	var best := INF
	var target := _self_pos
	for e in enemies:
		var d: float = _self_pos.distance_to(e["pos"])
		if d < best:
			best = d
			target = e["pos"]
	_enemy_dir = (target - _self_pos).normalized()


func _on_run_over(_won: bool, _stats: Dictionary) -> void:
	_run_over = true
	if _run_over_at < 0.0:
		_run_over_at = _t


# ---------------- 各 stage 处理 ----------------


func _proc_notlogged() -> void:
	if Lobby.last_error == LobbyLib.ERR.NOT_LOGGED_IN:
		_pass("notlogged")
	elif Lobby.last_error != 0:
		_fail("unexpected err=%d" % Lobby.last_error)


func _proc_badcode() -> void:
	if Lobby.last_error == LobbyLib.ERR.ROOM_NOT_FOUND:
		_pass("badcode candidate=%s" % BAD_CANDIDATES[_bad_idx])
	elif Lobby.in_room():
		Lobby.leave_room()
		_advance_candidate()
	elif Lobby.last_error != 0:
		_advance_candidate()


func _proc_host() -> void:
	match _phase:
		0:
			_host_wait_room()
		1:
			_host_wait_team()
		2:
			_host_wait_running()
		3:
			_host_wait_end()
		4:
			_host_wait_second()


func _proc_seat() -> void:
	if _phase == 0:
		_seat_wait_room()
	elif _phase == 1:
		_seat_wait_not_host()
	else:
		_seat_linger()


func _proc_full() -> void:
	if _delay_until >= 0.0 and _t >= _delay_until:
		if not _sent_join:
			_sent_join = true
			Lobby.join_room(_code)
		elif Lobby.last_error == LobbyLib.ERR.ROOM_FULL:
			_pass("full")
		elif Lobby.in_room():
			_fail("unexpectedly joined full room")
		elif Lobby.last_error != 0:
			_fail("unexpected err=%d" % Lobby.last_error)


func _proc_concurrent() -> void:
	match _phase:
		0:
			_conc_wait_room()
		1:
			_conc_wait_running()
		2:
			_conc_linger()


# ---------------- host 子阶段 ----------------


func _host_wait_room() -> void:
	if not Lobby.in_room():
		return
	var code := Lobby.room_code
	if not _valid_room_code(code):
		_fail("bad room_code=%s" % code)
	elif not Lobby.is_host:
		_fail("created room but is_host=false")
	elif Lobby.members.size() != 1:
		_fail("members=%d != 1" % Lobby.members.size())
	else:
		if not _codefile.is_empty():
			_write_code(code)
		_phase = 1


func _host_wait_team() -> void:
	var n := Lobby.members.size()
	if n >= 2 and _member_since < 0.0:
		_member_since = _t
	if n >= 4 or (n >= 2 and _member_since >= 0.0 and _t - _member_since >= MEMBER_SETTLE):
		Lobby.start_run()
		_phase = 2


func _host_wait_running() -> void:
	if Lobby.room_state == LobbyLib.STATE.RUNNING and _snaps >= 10 and _walls_seen and _wave_seen:
		_phase = 3
	elif _run_over:
		_fail(
			(
				"run_over before conditions snaps=%d walls=%s wave=%s"
				% [_snaps, _walls_seen, _wave_seen]
			)
		)


func _host_wait_end() -> void:
	if not _run_over:
		return
	if not Lobby.in_room():
		_fail("not in room after run")
	elif Lobby.room_state == LobbyLib.STATE.WAITING:
		Lobby.start_run()
		_run_over = false  # 第二局重开：本客户端的冲锋门控与位移采样一起复位
		_run_over_at = -1.0
		_second_start_set = false
		_second_moved = false
		_second_at = -1.0
		_phase = 4
	elif _t - _run_over_at >= WAIT_GRACE:
		_fail("state=%d not WAITING" % Lobby.room_state)


func _host_wait_second() -> void:
	if Lobby.room_state != LobbyLib.STATE.RUNNING:
		return
	# 第二局必须真的能走：武器是自动攻击，所以"一局能结束"无法证明输入已随新局恢复
	if _second_at < 0.0:
		_second_at = _t
	if _second_moved:
		_pass(
			(
				"host snaps=%d wave=%d walls=%d members=%d second_moved=1 code=%s"
				% [
					_snaps,
					1 if _wave_seen else 0,
					1 if _walls_seen else 0,
					Lobby.members.size(),
					Lobby.room_code,
				]
			)
		)
	elif _run_over:
		_fail("second run ended with zero local movement (input not resumed)")
	elif _t - _second_at >= 6.0:
		_fail("no local movement in second run within 6s (input not resumed)")


# ---------------- seat / concurrent 子阶段 ----------------


func _seat_wait_room() -> void:
	if not Lobby.in_room():
		return
	if not Lobby.members.has(_user):
		_fail("self %s not in members" % _user)
	elif _expect == "not_host":
		Lobby.start_run()
		_phase = 1
	else:
		_phase = 2


func _seat_wait_not_host() -> void:
	if Lobby.last_error == LobbyLib.ERR.NOT_HOST:
		_phase = 2
	elif Lobby.last_error != 0:
		_fail("expect not_host but err=%d" % Lobby.last_error)


func _seat_linger() -> void:
	var linger := DEFAULT_LINGER if _linger <= 0.0 else _linger
	if _linger_until < 0.0:
		_linger_until = _t + linger
	if _t >= _linger_until:
		if not _saw_running:
			_fail("never saw RUNNING")
		elif _snaps < 10:
			_fail("snaps=%d < 10" % _snaps)
		else:
			_pass(
				"seat snaps=%d running=%d linger=%.0f" % [_snaps, 1 if _saw_running else 0, linger]
			)


func _conc_wait_room() -> void:
	if Lobby.in_room() and Lobby.is_host:
		Lobby.start_run()
		_phase = 1


func _conc_wait_running() -> void:
	if Lobby.room_state != LobbyLib.STATE.RUNNING:
		return
	if _snaps < 10 or not _walls_seen or not _wave_seen:
		return
	if _linger > 0.0:
		_linger_until = _t + _linger
		_phase = 2
	else:
		_pass(
			(
				"concurrent snaps=%d wave=%d walls=%d"
				% [_snaps, 1 if _wave_seen else 0, 1 if _walls_seen else 0]
			)
		)


func _conc_linger() -> void:
	if _t >= _linger_until:
		_pass(
			(
				"concurrent snaps=%d wave=%d walls=%d"
				% [_snaps, 1 if _wave_seen else 0, 1 if _walls_seen else 0]
			)
		)


# ---------------- 辅助 ----------------


func _join_candidate() -> void:
	Lobby.last_error = 0
	Lobby.join_room(BAD_CANDIDATES[_bad_idx])


func _advance_candidate() -> void:
	_bad_idx += 1
	Lobby.last_error = 0
	if _bad_idx >= BAD_CANDIDATES.size():
		_fail("no candidate returned ROOM_NOT_FOUND")
	else:
		Lobby.join_room(BAD_CANDIDATES[_bad_idx])


func _valid_room_code(code: String) -> bool:
	return code.length() == 6 and code[0] != "0" and LobbyLib.is_valid_code(code)


func _write_code(code: String) -> void:
	var f := FileAccess.open(_codefile, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(code)
	f.flush()
	f.close()


func _stage_timeout() -> float:
	return HOST_TIMEOUT if _stage == "host" else DEFAULT_TIMEOUT


func _pass(label: String) -> void:
	_done = true
	print("[LobbyTest] PASS stage=%s %s" % [_stage, label])
	get_tree().quit(0)


func _fail(reason: String) -> void:
	_done = true
	printerr("[LobbyTest] FAIL stage=%s reason=%s" % [_stage, reason])
	get_tree().quit(1)
