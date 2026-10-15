extends Node
## 账号 E2E 冒烟 —— 客户端。三阶段（register / badpass / mismatch），由 run_account_test.ps1 逐阶段启动。
## 依赖专用服务器（--transport=ws --data=<tmp>/accounts.json）。

const Protocol := preload("res://net/protocol.gd")

const STAGE_TIMEOUT := 15.0
const MISMATCH_LINGER := 0.5  # 版本不符时多留 0.5s 便于服务端日志取证

var _stage := "register"
var _ip := ""  # 留空则交 Account 按 `--lobby=` 覆盖 / 默认大厅地址解析（偏离 11）
var _port := 0
var _user := ""
var _password := ""
var _t := 0.0
var _done := false
var _register_ok := false
var _login_ok := false
var _fail_count := 0
var _reason_first := ""
var _reason_same := true
var _mismatch := false
var _mismatch_age := 0.0


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
	Net.connected_ok.connect(_on_connected)
	Net.connection_failed.connect(_on_failed)
	Net.version_mismatch.connect(_on_version_mismatch)
	Account.register_ok.connect(_on_register_ok)
	Account.register_failed.connect(_on_register_failed)
	Account.login_ok.connect(_on_login_ok)
	Account.login_failed.connect(_on_login_failed)
	Account.version_mismatch_detected.connect(_on_account_mismatch)
	if _stage == "mismatch":
		Net.set_forced_version(Protocol.PROTOCOL_VERSION - 1)
	Account.connect_lobby(_ip, _port)


func _on_connected(_local_id: int) -> void:
	match _stage:
		"register":
			Account.register(_user, _password)
		"badpass":
			Account.login(_user, "definitely_wrong_1")
		_:
			pass  # mismatch：等 version_mismatch


func _on_register_ok(_uname: String) -> void:
	_register_ok = true
	Account.login(_user, _password)


func _on_register_failed(reason: String) -> void:
	_fail("register_failed: %s" % reason)


func _on_login_ok(_uname: String) -> void:
	_login_ok = true


func _on_login_failed(reason: String) -> void:
	_fail_count += 1
	if _fail_count == 1:
		_reason_first = reason
		Account.login("nosuchuser_zzz", "whatever_pw_1")  # 防枚举：未知用户名也走同一条失败路径
	else:
		_reason_same = reason == _reason_first


func _on_version_mismatch(_server_version: int) -> void:
	_mismatch = true


func _on_account_mismatch() -> void:
	_mismatch = true


func _on_failed() -> void:
	_fail("connection_failed")


func _process(delta: float) -> void:
	_t += delta
	if _done:
		return
	if _mismatch:
		_mismatch_age += delta
	if _t > STAGE_TIMEOUT:
		_fail("timeout t=%.1f" % _t)
		return
	match _stage:
		"register":
			if _register_ok and _login_ok:
				_pass("register_then_login")
		"badpass":
			if _fail_count >= 2:
				if _reason_same:
					_pass("badpass_and_unknown_same_reason")
				else:
					_fail("unknown user differs from wrong password (枚举风险)")
		"mismatch":
			if _mismatch and _mismatch_age >= MISMATCH_LINGER:
				_pass("version_mismatch_rejected")


func _pass(label: String) -> void:
	_done = true
	print("[AcctTest] PASS stage=%s %s" % [_stage, label])
	get_tree().quit(0)


func _fail(reason: String) -> void:
	_done = true
	printerr("[AcctTest] FAIL stage=%s reason=%s" % [_stage, reason])
	get_tree().quit(1)
