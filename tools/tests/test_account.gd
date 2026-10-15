extends RefCounted
## 账号密码学测试：RFC 4231 向量 + PBKDF2-HMAC-SHA256 向量 + 校验规则 + 常量时间比较 + 性能。

const Harness := preload("res://tools/tests/harness.gd")
const AccountLib := preload("res://net/account.gd")


func run() -> int:
	var t := Harness.new()

	# (1) RFC 4231 Test Case 1：HMAC-SHA256
	var key := PackedByteArray()
	for _i in 20:
		key.append(0x0B)
	t.eq(
		_hex(AccountLib.hmac_sha256(key, "Hi There".to_utf8_buffer())),
		"b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
		"HMAC-SHA256 命中 RFC 4231 Test Case 1"
	)

	# (2) PBKDF2-HMAC-SHA256（P="password" S="salt" dkLen=32）
	var salt := "salt".to_utf8_buffer()
	t.eq(
		_hex(AccountLib.derive_verifier("password", salt, 1)),
		"120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b",
		"PBKDF2 c=1 向量"
	)
	t.eq(
		_hex(AccountLib.derive_verifier("password", salt, 2)),
		"ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43",
		"PBKDF2 c=2 向量"
	)
	t.eq(
		_hex(AccountLib.derive_verifier("password", salt, 4096)),
		"c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a",
		"PBKDF2 c=4096 向量"
	)

	# (3) 用户名/密码校验规则
	t.check(AccountLib.validate_username("abc"), "3 字符用户名合法")
	t.check(AccountLib.validate_username("Alice_01"), "字母+数字+下划线合法")
	t.check(not AccountLib.validate_username("ab"), "2 字符过短")
	t.check(not AccountLib.validate_username("abcdefghijklmnopq"), "17 字符过长")
	t.check(not AccountLib.validate_username("用户名"), "非 ASCII 非法")
	t.check(not AccountLib.validate_username("a b"), "含空格非法")
	t.check(AccountLib.validate_password("123456"), "6 字符密码合法")
	t.check(not AccountLib.validate_password("12345"), "5 字符密码过短")
	t.check(not AccountLib.validate_password("x".repeat(65)), "65 字符密码过长")

	# (4) salt / nonce 长度与随机性
	t.eq(AccountLib.make_salt().size(), 16, "salt 16 字节")
	t.eq(AccountLib.make_nonce().size(), 32, "nonce 32 字节")
	var salt_a := AccountLib.make_salt()
	var salt_b := AccountLib.make_salt()
	t.check(salt_a != salt_b, "两次 salt 不同")

	# (5) 挑战-响应往返
	var s := AccountLib.make_salt()
	var verifier := AccountLib.derive_verifier("hunter2", s, 1000)
	var nonce := AccountLib.make_nonce()
	var p := AccountLib.proof(verifier, nonce)
	t.check(AccountLib.verify_proof(verifier, nonce, p), "正确 proof 通过")
	var tampered := p.duplicate()
	tampered[0] = tampered[0] ^ 0xFF
	t.check(not AccountLib.verify_proof(verifier, nonce, tampered), "篡改 proof 被拒")
	t.check(not AccountLib.verify_proof(verifier, AccountLib.make_nonce(), p), "换 nonce 被拒")

	# (6) base64 往返
	t.eq(AccountLib.from_b64(AccountLib.to_b64(nonce)), nonce, "base64 往返一致")

	# (7) 常量时间比较
	t.check(AccountLib.secure_eq(nonce, nonce.duplicate()), "相同字节流相等")
	t.check(not AccountLib.secure_eq(nonce, AccountLib.make_nonce()), "不同字节流不等")
	t.check(not AccountLib.secure_eq(nonce, nonce.slice(0, 8)), "长度不同不等")

	# (8) 10 个错误码都有中文文案
	for code in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]:
		t.check(not AccountLib.reason_text(code).is_empty(), "错误码 %d 有文案" % code)

	# (9) PBKDF2 性能：目标 ≤50ms，硬门限 100ms
	var t0 := Time.get_ticks_msec()
	AccountLib.derive_verifier("benchmark_pw", s, AccountLib.PBKDF2_ITER)
	var elapsed := Time.get_ticks_msec() - t0
	print("[Account] PBKDF2 iter=%d elapsed=%dms" % [AccountLib.PBKDF2_ITER, elapsed])
	t.check(elapsed < 100, "PBKDF2 单次 < 100ms（否则把 PBKDF2_ITER 降到 10000）")

	return t.report("Account")


func _hex(b: PackedByteArray) -> String:
	var s := ""
	for v in b:
		s += "%02x" % v
	return s
