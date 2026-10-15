extends RefCounted
## 账号服务测试：注册 / 大小写归一 / 防枚举 / 挑战一次性与 TTL / 限流 / 断线清会话 / 重载持久化。

const Harness := preload("res://tools/tests/harness.gd")
const AccountLib := preload("res://net/account.gd")
const AccountServer := preload("res://net/account_server.gd")

const DIR := "user://test_acct_srv"
const PATH := DIR + "/accounts.json"


func run() -> int:
	var t := Harness.new()
	_cleanup()
	DirAccess.make_dir_recursive_absolute(DIR)

	var srv := AccountServer.new(PATH)
	var salt := AccountLib.make_salt()
	var verifier := AccountLib.derive_verifier("hunter2", salt, 1000)

	# (1) 注册成功 + 表内归一
	t.eq(
		srv.register(1, "Alice", AccountLib.to_b64(salt), AccountLib.to_b64(verifier)),
		AccountLib.ERR.OK,
		"注册成功"
	)
	t.eq(srv.count(), 1, "账号表 1 条")
	t.check(srv.has_account("alice"), "小写键可查到")
	t.check(srv.has_account("ALICE"), "has_account 大小写归一")

	# (2) 用户名占用（大小写归一）
	t.eq(
		srv.register(2, "alice", AccountLib.to_b64(salt), AccountLib.to_b64(verifier)),
		AccountLib.ERR.USERNAME_TAKEN,
		"同名（不同大小写）被拒"
	)

	# (3) 非法用户名 / salt 长度不符
	t.eq(
		srv.register(3, "ab", AccountLib.to_b64(salt), AccountLib.to_b64(verifier)),
		AccountLib.ERR.USERNAME_INVALID,
		"过短用户名被拒"
	)
	t.eq(
		srv.register(
			4, "Bob", AccountLib.to_b64(PackedByteArray([1, 2, 3, 4])), AccountLib.to_b64(verifier)
		),
		AccountLib.ERR.PROTOCOL,
		"salt 长度不符被拒"
	)

	# (4) 注册限流：同 peer 30s 冷却
	t.eq(
		srv.register(1, "Carol", AccountLib.to_b64(salt), AccountLib.to_b64(verifier)),
		AccountLib.ERR.RATE_LIMITED,
		"同 peer 二次注册被限流"
	)

	# (5) 挑战-响应登录成功
	var ch1: Dictionary = srv.begin_login(5, "Alice")
	t.eq(int(ch1["err"]), AccountLib.ERR.OK, "begin_login 成功")
	t.eq(String(ch1["salt"]), AccountLib.to_b64(salt), "下发的是已存 salt")
	var nonce := AccountLib.from_b64(String(ch1["nonce"]))
	t.eq(
		int(srv.finish_login(5, AccountLib.to_b64(AccountLib.proof(verifier, nonce)))["err"]),
		AccountLib.ERR.OK,
		"正确 proof 登录成功"
	)
	t.eq(srv.current_user(5), "Alice", "会话记录原始大小写用户名")

	# (6) 防枚举：未知用户名也下发非空 salt+nonce，且失败码与错密码完全一致
	var ch2: Dictionary = srv.begin_login(6, "Ghost")
	t.eq(int(ch2["err"]), AccountLib.ERR.OK, "未知用户名 begin_login 仍返回 OK")
	t.check(not String(ch2["salt"]).is_empty(), "未知用户名下发非空 salt")
	t.check(not String(ch2["nonce"]).is_empty(), "未知用户名下发非空 nonce")
	var ghost_code := int(srv.finish_login(6, AccountLib.to_b64(AccountLib.make_nonce()))["err"])
	t.eq(ghost_code, AccountLib.ERR.BAD_CREDENTIALS, "未知用户名失败码 = BAD_CREDENTIALS")
	srv.begin_login(7, "Alice")
	var wrong_code := int(srv.finish_login(7, AccountLib.to_b64(AccountLib.make_nonce()))["err"])
	t.eq(wrong_code, ghost_code, "错密码与未知用户名返回同一码（防枚举）")

	# (7) 挑战一次性：同 peer 未重新 begin 再提交 → 失败
	t.eq(
		int(srv.finish_login(5, AccountLib.to_b64(AccountLib.make_nonce()))["err"]),
		AccountLib.ERR.BAD_CREDENTIALS,
		"挑战一次性：二次提交被拒"
	)

	# (8) 挑战 TTL：注入时钟越过 30s 后失效
	srv.test_clock_ms = 0
	srv.begin_login(8, "Alice")
	srv.test_clock_ms = 30001
	t.eq(
		int(srv.finish_login(8, AccountLib.to_b64(AccountLib.make_nonce()))["err"]),
		AccountLib.ERR.BAD_CREDENTIALS,
		"挑战过 TTL 后失效"
	)
	srv.test_clock_ms = -1

	# (9) 登录失败限流：窗口内连续失败达上限 → 冷却，begin_login 直接 RATE_LIMITED
	var peer_f := 9
	for _i in range(AccountServer.FAIL_LIMIT):
		srv.begin_login(peer_f, "Alice")
		srv.finish_login(peer_f, AccountLib.to_b64(AccountLib.make_nonce()))
	t.eq(
		int(srv.begin_login(peer_f, "Alice")["err"]),
		AccountLib.ERR.RATE_LIMITED,
		"失败达上限后 begin_login 被限流"
	)

	# (10) logout 清会话
	srv.logout(5)
	t.eq(srv.current_user(5), "", "logout 后无会话")

	# (11) 断线清全部本 peer 状态：清会话 + 解除注册冷却
	srv.on_peer_left(1)
	srv.on_peer_left(peer_f)
	t.eq(
		srv.register(1, "Dave", AccountLib.to_b64(salt), AccountLib.to_b64(verifier)),
		AccountLib.ERR.OK,
		"断线后同 peer 可立即再注册（冷却已清）"
	)

	# (12) 重载持久化
	var srv2 := AccountServer.new(PATH)
	srv2.load_from_disk()
	t.eq(srv2.count(), 2, "重载读到 2 条（Alice + Dave）")
	t.check(srv2.has_account("dave"), "重载含 Dave")

	_cleanup()
	return t.report("AccountServer")


func _cleanup() -> void:
	for p in [PATH, PATH + ".tmp", PATH + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
