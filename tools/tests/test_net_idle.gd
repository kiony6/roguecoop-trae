extends RefCounted
## M5.2 专用服务器空场生命周期测试（纯逻辑，无传输）。
## 覆盖：空场不推进波次、有人游玩时推进不受影响、空场超时整局归零、归零后新玩家拿到全新开局。

const Harness := preload("res://tools/tests/harness.gd")
const NetHostLogic := preload("res://net/net_host.gd")
const Combat := preload("res://sim/combat.gd")


func run() -> int:
	var t := Harness.new()

	# (1) 空场（专用服务器刚起、无人接入）不推进波次：elapsed/tick/wave 全部冻结
	var h1 := NetHostLogic.new()
	h1.reset(true)
	for _i in range(1000):  # 16 秒，远超 IDLE_RESET_SECONDS
		h1.physics_step(0.016)
	t.eq(h1.elapsed, 0.0, "空场：elapsed 不累加")
	t.eq(h1.tick, 0, "空场：tick 不递增")
	t.eq(h1.wave, 1, "空场：波次停在 1（不再随时间膨胀）")
	t.eq(h1.idle_resets, 0, "从未被玩过的服务器不加复位（幂等保护）")

	# (2) 有人游玩时推进不受影响（零回归）：非专用主机 players 恒非空
	var h2 := NetHostLogic.new()
	h2.reset(false)
	h2.spawn_interval = 9999.0
	for _i in range(60):
		h2.physics_step(0.016)
	t.eq(h2.tick, 60, "有人游玩：tick 正常递增")
	t.check(h2.elapsed > 0.9 and h2.elapsed < 1.0, "有人游玩：elapsed 正常推进")
	t.check(h2.players.has(1), "非专用主机玩家 1 始终在场")

	# (3) 玩过之后空场：未超时冻结、超时整局归零
	var h3 := NetHostLogic.new()
	h3.reset(true)
	h3.add_player(2)
	h3.spawn_interval = 9999.0
	h3.loot[1] = {
		"pos": Vector2(900, 0), "kind": Combat.LOOT_KIND_XP, "owner": 0, "ttl": Combat.LOOT_TTL
	}
	for _i in range(90):  # 游玩 1.44 秒
		h3.physics_step(0.016)
	t.check(h3.elapsed > 0.0, "有人接入：elapsed 正常推进")
	t.check(h3.loot.size() >= 1, "游玩中场上留有掉落")
	var played := h3.elapsed

	h3.remove_player(2)
	for _i in range(400):  # 空置 6.4 秒 < 10 秒
		h3.physics_step(0.016)
	t.eq(h3.elapsed, played, "空置未超时：elapsed 冻结")
	t.check(h3.loot.size() >= 1, "空置未超时：场上状态保留")

	for _i in range(700):  # 累计空置 17.6 秒 >= 10 秒
		h3.physics_step(0.016)
	t.eq(h3.elapsed, 0.0, "空置超时：elapsed 归零")
	t.eq(h3.wave, 1, "空置超时：回到第 1 波")
	t.eq(h3.tick, 0, "空置超时：tick 归零")
	t.eq(h3.loot.size(), 0, "空置超时：掉落清空")
	t.eq(h3.run_over, false, "空置超时走的是整局归零，而不是结算")
	t.eq(h3.idle_resets, 1, "空置超时计数器 +1（供运维日志观测）")
	t.check(h3.idle_reset_seconds >= NetHostLogic.IDLE_RESET_SECONDS, "记录复位时的空置时长")

	# (4) 复位后重连：新玩家面对全新开局，而不是被打残的残局
	h3.add_player(9)
	for _i in range(30):
		h3.physics_step(0.016)
	t.check(h3.players.has(9), "复位后玩家可正常接入")
	t.eq(h3.boss_kills, 0, "重连玩家面对全新计分（boss_kills=0）")
	t.check(h3.players[9]["level"] == 1, "重连玩家从 1 级开始")

	return t.report("NetIdle")
