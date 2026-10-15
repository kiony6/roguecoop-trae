extends RefCounted
## 专服兼任的账号服务（内存态 + 磁盘持久化），不含任何网络依赖：
## 注册 / 挑战-响应登录 / 会话 / 限流 / 挑战 TTL。由 autoload/net.gd 在 HOST 模式下驱动。

const AccountLib := preload("res://net/account.gd")
const Store := preload("res://disk/store.gd")

const REGISTER_COOLDOWN_MS := 30000  # 同 peer 注册冷却
const FAIL_WINDOW_MS := 60000  # 失败计数窗口
const FAIL_LIMIT := 5  # 窗口内失败上限
const COOLDOWN_MS := 60000  # 触发上限后的冷却时长
const CHALLENGE_TTL_MS := 30000  # 挑战有效期

var accounts: Dictionary = {}  # lower(username) -> {name, salt, verifier, created}
var sessions: Dictionary = {}  # peer -> 原始大小写用户名
var test_clock_ms := -1  # >= 0 时替代真实时钟（仅供单测注入）

var _path := ""
var _pending: Dictionary = {}  # peer -> {key, known, nonce, expires}
var _fails: Dictionary = {}  # peer -> Array[int]（毫秒时间戳）
var _cooldown: Dictionary = {}  # peer -> int（冷却截止毫秒）
var _last_register: Dictionary = {}  # peer -> int（最近注册毫秒）


func _init(store_path: String) -> void:
	_path = store_path


func now_ms() -> int:
	return test_clock_ms if test_clock_ms >= 0 else Time.get_ticks_msec()


func load_from_disk() -> void:
	accounts = Store.load_accounts(_path)


func count() -> int:
	return accounts.size()


func has_account(username: String) -> bool:
	return accounts.has(username.to_lower())


func current_user(peer: int) -> String:
	return String(sessions.get(peer, ""))


func register(peer: int, user: String, salt_b64: String, verifier_b64: String) -> int:
	if not _rate_ok_register(peer):
		return AccountLib.ERR.RATE_LIMITED
	if not AccountLib.validate_username(user):
		return AccountLib.ERR.USERNAME_INVALID
	var salt := AccountLib.from_b64(salt_b64)
	var verifier := AccountLib.from_b64(verifier_b64)
	if salt.size() != AccountLib.SALT_BYTES or verifier.size() != AccountLib.DK_LEN:
		return AccountLib.ERR.PROTOCOL
	_last_register[peer] = now_ms()
	var key := user.to_lower()
	if accounts.has(key):
		return AccountLib.ERR.USERNAME_TAKEN
	accounts[key] = {
		"name": user,
		"salt": salt_b64,
		"verifier": verifier_b64,
		"created": int(Time.get_unix_time_from_system()),
	}
	if Store.save_accounts(_path, accounts) != OK:
		accounts.erase(key)
		return AccountLib.ERR.INTERNAL
	return AccountLib.ERR.OK


func begin_login(peer: int, user: String) -> Dictionary:
	## 未知用户名也下发同形随机 salt + nonce，防用户名枚举（spec §4.3）。
	if _cooldown_active(peer):
		return {"ok": false, "err": AccountLib.ERR.RATE_LIMITED, "salt": "", "nonce": ""}
	var key := user.to_lower()
	var known := accounts.has(key)
	var salt_b64 := (
		String(accounts[key]["salt"]) if known else AccountLib.to_b64(AccountLib.make_salt())
	)
	var nonce_b64 := AccountLib.to_b64(AccountLib.make_nonce())
	_pending[peer] = {
		"key": key, "known": known, "nonce": nonce_b64, "expires": now_ms() + CHALLENGE_TTL_MS
	}
	return {"ok": true, "err": AccountLib.ERR.OK, "salt": salt_b64, "nonce": nonce_b64}


func finish_login(peer: int, proof_b64: String) -> Dictionary:
	var bad := {"ok": false, "err": AccountLib.ERR.BAD_CREDENTIALS, "username": ""}
	var ch: Dictionary = _pending.get(peer, {})
	_pending.erase(peer)
	if ch.is_empty() or now_ms() > int(ch["expires"]):
		return bad
	if not bool(ch["known"]):
		_record_fail(peer)
		return bad
	var rec: Dictionary = accounts[ch["key"]]
	var verifier := AccountLib.from_b64(String(rec["verifier"]))
	var nonce := AccountLib.from_b64(String(ch["nonce"]))
	if AccountLib.secure_eq(AccountLib.proof(verifier, nonce), AccountLib.from_b64(proof_b64)):
		sessions[peer] = String(rec["name"])
		return {"ok": true, "err": AccountLib.ERR.OK, "username": String(rec["name"])}
	_record_fail(peer)
	return bad


func logout(peer: int) -> void:
	sessions.erase(peer)
	_pending.erase(peer)


func on_peer_left(peer: int) -> void:
	## peer 断开无条件清除全部本 peer 状态（spec §4.4）。
	sessions.erase(peer)
	_pending.erase(peer)
	_fails.erase(peer)
	_cooldown.erase(peer)
	_last_register.erase(peer)


func _rate_ok_register(peer: int) -> bool:
	if not _last_register.has(peer):
		return true
	return now_ms() - int(_last_register[peer]) >= REGISTER_COOLDOWN_MS


func _cooldown_active(peer: int) -> bool:
	return _cooldown.has(peer) and now_ms() < int(_cooldown[peer])


func _record_fail(peer: int) -> void:
	var now := now_ms()
	var keep: Array = []
	for ts in _fails.get(peer, []):
		if now - int(ts) <= FAIL_WINDOW_MS:
			keep.append(ts)
	keep.append(now)
	if keep.size() >= FAIL_LIMIT:
		_cooldown[peer] = now + COOLDOWN_MS
		_fails[peer] = []
	else:
		_fails[peer] = keep
