extends Node
## 账号门面（autoload 名 "Account"）：页面只认本单例的信号与状态。
## 本文件只调用 Net 的公开 API，自己绝不声明 RPC 方法 —— 保证 RPC 入口唯一在 autoload/net.gd。

signal lobby_connecting
signal lobby_connected
signal lobby_failed(reason: String)
signal register_ok(username: String)
signal register_failed(reason: String)
signal login_ok(username: String)
signal login_failed(reason: String)
signal logged_out
signal version_mismatch_detected

const Protocol := preload("res://net/protocol.gd")
const AccountLib := preload("res://net/account.gd")

const LOBBY_HOST := "play.simpfun.cn"
const LOBBY_PORT := 30470

var username := ""
var lobby_open := false  # 传输层已连上大厅

var _password := ""  # 登录时暂存明文，等挑战回来后立即派生 verifier 并清空
var _pending_user := ""
var _closing := false


func _ready() -> void:
	Net.connected_ok.connect(_on_connected)
	Net.connection_failed.connect(_on_connection_failed)
	Net.disconnected.connect(_on_disconnected)
	Net.auth_challenge.connect(_on_challenge)
	Net.auth_result.connect(_on_auth_result)
	Net.account_registered.connect(_on_registered)
	Net.account_session_closed.connect(_on_session_closed)
	Net.version_mismatch.connect(_on_version_mismatch)


func connect_lobby(address: String = LOBBY_HOST, port: int = LOBBY_PORT) -> void:
	## 连联机大厅：占 ROLE_LOBBY 角色，只走账号 RPC，不进对局。幂等（已连则直接返回）。
	if Net.is_client():
		return
	if Net.is_host():
		Net.host_stop()
	lobby_open = false
	_closing = false
	Net.set_websocket(true)
	Net.set_role(Protocol.ROLE_LOBBY)
	lobby_connecting.emit()
	var err := Net.client_connect(address, port)
	if err != OK:
		lobby_failed.emit("无法发起连接（错误码 %d）" % err)


func disconnect_lobby() -> void:
	## 名字避开 Object.disconnect()（见「必要偏离 5」）。
	_closing = true
	if Net.is_client():
		Net.client_disconnect()
	lobby_open = false
	username = ""
	_password = ""


func is_logged_in() -> bool:
	return not username.is_empty()


func register(user: String, password: String) -> void:
	if not Net.is_client():
		register_failed.emit(AccountLib.reason_text(AccountLib.ERR.NOT_CONNECTED))
		return
	if not AccountLib.validate_username(user):
		register_failed.emit(AccountLib.reason_text(AccountLib.ERR.USERNAME_INVALID))
		return
	if not AccountLib.validate_password(password):
		register_failed.emit(AccountLib.reason_text(AccountLib.ERR.PASSWORD_WEAK))
		return
	var salt := AccountLib.make_salt()
	var verifier := AccountLib.derive_verifier(password, salt, AccountLib.PBKDF2_ITER)
	_pending_user = user
	Net.send_register(user, AccountLib.to_b64(salt), AccountLib.to_b64(verifier))


func login(user: String, password: String) -> void:
	if not Net.is_client():
		login_failed.emit(AccountLib.reason_text(AccountLib.ERR.NOT_CONNECTED))
		return
	if not AccountLib.validate_username(user):
		login_failed.emit(AccountLib.reason_text(AccountLib.ERR.USERNAME_INVALID))
		return
	_pending_user = user
	_password = password
	Net.send_login_begin(user)


func logout() -> void:
	if Net.is_client():
		Net.send_logout()


func _on_connected(_local_id: int) -> void:
	if Net.role != Protocol.ROLE_LOBBY:
		return  # 直连通道的连接不算大厅
	lobby_open = true
	lobby_connected.emit()


func _on_connection_failed() -> void:
	if Net.role != Protocol.ROLE_LOBBY:
		return
	lobby_open = false
	lobby_failed.emit("连接大厅失败（服务未启动或网络不通）")


func _on_disconnected() -> void:
	if Net.role != Protocol.ROLE_LOBBY:
		return
	lobby_open = false
	username = ""
	if _closing:
		_closing = false
		return
	lobby_failed.emit("与大厅的连接已断开")


func _on_challenge(salt_b64: String, nonce_b64: String) -> void:
	var salt := AccountLib.from_b64(salt_b64)
	var nonce := AccountLib.from_b64(nonce_b64)
	var verifier := AccountLib.derive_verifier(_password, salt, AccountLib.PBKDF2_ITER)
	var proof := AccountLib.proof(verifier, nonce)
	_password = ""
	Net.send_login_proof(AccountLib.to_b64(proof))


func _on_registered(ok: bool, err_code: int) -> void:
	if ok:
		register_ok.emit(_pending_user)
	else:
		register_failed.emit(AccountLib.reason_text(err_code))


func _on_auth_result(ok: bool, uname: String, err_code: int) -> void:
	if ok:
		username = uname
		login_ok.emit(username)
	else:
		login_failed.emit(AccountLib.reason_text(err_code))


func _on_session_closed() -> void:
	username = ""
	logged_out.emit()


func _on_version_mismatch(_server_version: int) -> void:
	lobby_open = false
	version_mismatch_detected.emit()
