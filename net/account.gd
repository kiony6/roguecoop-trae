extends RefCounted
## 账号密码学与校验（纯函数、无状态、可被无头单测直接断言）。
## 安全契约（spec §4.1）：明文密码与 verifier 都不过网线；注册只上传 salt 与 verifier；
## 登录用挑战-响应 HMAC-SHA256(verifier, nonce)。已知局限：verifier 泄露等价于口令泄露。

enum ERR {
	OK = 0,
	BAD_CREDENTIALS = 1,
	USERNAME_TAKEN = 2,
	USERNAME_INVALID = 3,
	PASSWORD_WEAK = 4,
	RATE_LIMITED = 5,
	UNSUPPORTED = 6,
	PROTOCOL = 7,
	INTERNAL = 8,
	NOT_CONNECTED = 9,
}

const PBKDF2_ITER := 10000  # 迭代次数；Step 4 实测单次耗时后按需下调
const HMAC_BLOCK := 64  # SHA-256 的 HMAC 密钥块长度（RFC 2104）
const SALT_BYTES := 16
const NONCE_BYTES := 32
const DK_LEN := 32  # PBKDF2-HMAC-SHA256 单块输出的长度（= SHA-256 摘要长度）
const USERNAME_MIN := 3
const USERNAME_MAX := 16
const PASSWORD_MIN := 6
const PASSWORD_MAX := 64


static func hmac_sha256(key: PackedByteArray, msg: PackedByteArray) -> PackedByteArray:
	var c := Crypto.new()
	return c.hmac_digest(HashingContext.HASH_SHA256, key, msg)


static func derive_verifier(
	password: String, salt: PackedByteArray, iterations: int, dk_len: int = DK_LEN
) -> PackedByteArray:
	## RFC 8018 PBKDF2-HMAC-SHA256 单块实现：dk_len <= 32 时只需 1 个块。
	## 迭代次数很高，故预展开 ipad/opad 并复用同一对 HashingContext，
	## 消除每轮 HMAC 的对象分配；输出与逐轮 hmac_sha256 完全一致。
	var pwd := password.to_utf8_buffer()
	var key_block := _key_block(pwd)
	var ipad := key_block.duplicate()
	var opad := key_block.duplicate()
	for i in HMAC_BLOCK:
		ipad[i] = ipad[i] ^ 0x36
		opad[i] = opad[i] ^ 0x5C
	var h_in := HashingContext.new()
	var h_out := HashingContext.new()
	var block := salt.duplicate()
	block.append_array(_be32(1))
	var u := _hmac_reuse(h_in, h_out, ipad, opad, block)
	var t := u.duplicate()
	for _i in range(1, iterations):
		u = _hmac_reuse(h_in, h_out, ipad, opad, u)
		for j in u.size():
			t[j] = t[j] ^ u[j]
	return t.slice(0, mini(dk_len, t.size()))


static func _hmac_reuse(
	h_in: HashingContext,
	h_out: HashingContext,
	ipad: PackedByteArray,
	opad: PackedByteArray,
	msg: PackedByteArray
) -> PackedByteArray:
	## RFC 2104 HMAC：复用同一对上下文对象，避免每轮新建。start() 可重复调用。
	h_in.start(HashingContext.HASH_SHA256)
	h_in.update(ipad)
	h_in.update(msg)
	var inner := h_in.finish()
	h_out.start(HashingContext.HASH_SHA256)
	h_out.update(opad)
	h_out.update(inner)
	return h_out.finish()


static func _key_block(key: PackedByteArray) -> PackedByteArray:
	## HMAC 密钥预处理：超块先摘要，再右侧补零到 64 字节。
	var k := key
	if k.size() > HMAC_BLOCK:
		var h := HashingContext.new()
		h.start(HashingContext.HASH_SHA256)
		h.update(k)
		k = h.finish()
	var out := PackedByteArray()
	out.resize(HMAC_BLOCK)
	out.fill(0)
	for i in k.size():
		out[i] = k[i]
	return out


static func proof(verifier: PackedByteArray, nonce: PackedByteArray) -> PackedByteArray:
	return hmac_sha256(verifier, nonce)


static func verify_proof(
	verifier: PackedByteArray, nonce: PackedByteArray, candidate: PackedByteArray
) -> bool:
	return secure_eq(proof(verifier, nonce), candidate)


static func secure_eq(a: PackedByteArray, b: PackedByteArray) -> bool:
	## 常量时间比较：长度不同立即返回 false，长度相同则整段异或累计。
	if a.size() != b.size():
		return false
	var diff := 0
	for i in a.size():
		diff |= a[i] ^ b[i]
	return diff == 0


static func make_salt() -> PackedByteArray:
	return Crypto.new().generate_random_bytes(SALT_BYTES)


static func make_nonce() -> PackedByteArray:
	return Crypto.new().generate_random_bytes(NONCE_BYTES)


static func to_b64(b: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(b)


static func from_b64(s: String) -> PackedByteArray:
	return Marshalls.base64_to_raw(s)


static func validate_username(u: String) -> bool:
	if u.length() < USERNAME_MIN or u.length() > USERNAME_MAX:
		return false
	for i in u.length():
		var c := u.unicode_at(i)
		var is_digit := c >= 0x30 and c <= 0x39
		var is_upper := c >= 0x41 and c <= 0x5A
		var is_lower := c >= 0x61 and c <= 0x7A
		if not (is_digit or is_upper or is_lower or c == 0x5F):
			return false
	return true


static func validate_password(p: String) -> bool:
	return p.length() >= PASSWORD_MIN and p.length() <= PASSWORD_MAX


static func reason_text(err: int) -> String:
	match err:
		ERR.OK:
			return "成功"
		ERR.BAD_CREDENTIALS:
			return "用户名或密码错误"
		ERR.USERNAME_TAKEN:
			return "该用户名已被注册"
		ERR.USERNAME_INVALID:
			return "用户名需为 3–16 位字母、数字或下划线"
		ERR.PASSWORD_WEAK:
			return "密码需为 6–64 位"
		ERR.RATE_LIMITED:
			return "操作过于频繁，请稍后再试"
		ERR.UNSUPPORTED:
			return "当前主机不支持账号服务"
		ERR.PROTOCOL:
			return "客户端与服务端版本不一致"
		ERR.INTERNAL:
			return "服务端内部错误"
		ERR.NOT_CONNECTED:
			return "尚未连接联机大厅"
	return "未知错误"


static func _be32(n: int) -> PackedByteArray:
	## RFC 8018 要求 INT(1) 采用大端；Godot 的 encode_u32 默认小端，故手工写入。
	var b := PackedByteArray()
	b.resize(4)
	b[0] = (n >> 24) & 0xFF
	b[1] = (n >> 16) & 0xFF
	b[2] = (n >> 8) & 0xFF
	b[3] = n & 0xFF
	return b
