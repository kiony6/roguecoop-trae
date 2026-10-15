extends RefCounted
## 大厅组队码纯逻辑测试：常量/枚举、组队码校验与生成、碰撞重试、错误码文案。

const Harness := preload("res://tools/tests/harness.gd")
const Lobby := preload("res://net/lobby.gd")


func run() -> int:
	var t := Harness.new()

	# (1) 常量
	t.eq(Lobby.MAX_ROOMS, 4, "房间上限 4")
	t.eq(Lobby.EMPTY_ROOM_TTL_S, 120.0, "空房 TTL 120s")
	t.eq(Lobby.ROOMS_CAPACITY, 16, "客户端上限 = 4*4 = 16")
	t.eq(Lobby.ROOM_CODE_MIN, 100000, "组队码下界")
	t.eq(Lobby.ROOM_CODE_MAX, 999999, "组队码上界")

	# (2) 房间状态机取值
	t.eq(Lobby.STATE.WAITING, 0, "WAITING=0")
	t.eq(Lobby.STATE.RUNNING, 1, "RUNNING=1")
	t.eq(Lobby.STATE.FINISHED, 2, "FINISHED=2")

	# (3) is_valid_code 正负例
	t.check(Lobby.is_valid_code("123456"), "常规 6 位码合法")
	t.check(Lobby.is_valid_code("100000"), "首位非 0 合法")
	t.check(not Lobby.is_valid_code("012345"), "首位为 0 非法")
	t.check(not Lobby.is_valid_code("12345"), "5 位非法")
	t.check(not Lobby.is_valid_code("1234567"), "7 位非法")
	t.check(not Lobby.is_valid_code("abc123"), "含字母非法")
	t.check(not Lobby.is_valid_code("12345a"), "末位字母非法")
	t.check(not Lobby.is_valid_code(""), "空串非法")

	# (4) make_code 基本性质（空 taken）
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var code := Lobby.make_code(rng, {})
	t.check(Lobby.is_valid_code(code), "空 taken 生成合法码")
	t.eq(code.length(), 6, "生成的码长度 6")

	# (5) 码碰撞重试：被占码不再返回
	var probe := RandomNumberGenerator.new()
	probe.seed = 12345
	var occupied := str(probe.randi_range(Lobby.ROOM_CODE_MIN, Lobby.ROOM_CODE_MAX))
	var taken := {occupied: true}
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 12345
	var picked := Lobby.make_code(rng_b, taken)
	t.check(Lobby.is_valid_code(picked), "碰撞后仍返回合法码")
	t.check(picked != occupied, "碰撞后不复用已占用码")
	t.check(not taken.has(picked), "返回码不在 taken 中")

	# (6) 12 个错误码都有中文文案
	for code_idx in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]:
		t.check(not Lobby.reason_text(code_idx).is_empty(), "错误码 %d 有文案" % code_idx)

	return t.report("Lobby")
