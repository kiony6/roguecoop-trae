extends RefCounted
## 条件/循环在权威侧的落地测试：_condition_ok 门禁、_apply_commands 循环重复、
## 最弱协议处决、超杀溢出转 AoE。全部走 NetHostLogic 纯逻辑，不依赖传输。

const Harness := preload("res://tools/tests/harness.gd")
const NetHostLogic := preload("res://net/net_host.gd")
const Progression := preload("res://sim/progression.gd")
const Combat := preload("res://sim/combat.gd")
const Skills := preload("res://sim/skills.gd")


func run() -> int:
	var t := Harness.new()

	# (1) 条件门禁：自身生命 ≤50% 才放行
	var h1 := NetHostLogic.new()
	h1.reset()
	h1.spawn_interval = 9999.0
	var p: Dictionary = h1.players[1]
	var full := int(Progression.max_hp(p["mods"]))
	var low_cmd := _cmd(Skills.EFF_CHIP, Skills.COND_LOW_HP, 50, 1)
	p["hp"] = full
	h1._apply_commands(1, [low_cmd])
	t.eq(h1.take_fx_events().size(), 0, "满血时低血量门禁拦下动作")
	p["hp"] = int(full * 0.4)
	h1._apply_commands(1, [low_cmd])
	t.eq(h1.take_fx_events().size(), 1, "残血时门禁放行")

	# (2) 无门禁动作不受条件影响
	p["hp"] = full
	h1._apply_commands(1, [_cmd(Skills.EFF_CHIP, Skills.COND_NONE, 0, 1)])
	t.eq(h1.take_fx_events().size(), 1, "无条件指令始终放行")

	# (3) 循环：同一动作执行 loops 次，且被 MAX_LOOPS 钳制
	var h2 := NetHostLogic.new()
	h2.reset()
	h2.spawn_interval = 9999.0
	h2._apply_commands(1, [_cmd(Skills.EFF_CHIP, Skills.COND_NONE, 0, 3)])
	t.eq(h2.take_fx_events().size(), 3, "循环 3 次产生 3 个特效事件")
	h2._apply_commands(1, [_cmd(Skills.EFF_CHIP, Skills.COND_NONE, 0, 99)])
	t.eq(h2.take_fx_events().size(), Skills.MAX_LOOPS, "循环次数被硬上限钳制")

	# (4) 最弱协议：处决血量比例最低的敌人，不动较硬的目标
	var h3 := NetHostLogic.new()
	h3.reset()
	h3.spawn_interval = 9999.0
	var strong := h3.spawn_enemy(Vector2(100, 0))
	var weak := h3.spawn_enemy(Vector2(200, 0))
	h3.enemies[weak]["hp"] = 3
	h3._apply_commands(1, [_cmd(Skills.EFF_WEAKEST, Skills.COND_NONE, 0, 1, 50)])
	t.check(not h3.enemies.has(weak), "血量比例最低的敌人被处决")
	t.check(h3.enemies.has(strong), "较硬的敌人未被误伤")

	# (5) 超杀：击杀时的溢出伤害炸成 AoE，波及邻近敌人
	var h4 := NetHostLogic.new()
	h4.reset()
	h4.spawn_interval = 9999.0
	h4.players[1]["skill_nodes"] = [46]  # 仅解锁「超杀」
	var near := h4.spawn_enemy(Vector2(140, 0))
	var far := h4.spawn_enemy(Vector2(100, 0))
	# 抬高邻近敌人的血量上限，确保只验证「掉血」而不被溢出伤害直接打死
	h4.enemies[near]["max_hp"] = 500
	h4.enemies[near]["hp"] = 500
	h4.enemies[far]["hp"] = -30  # 模拟被过量打死（溢出 30）
	h4._kill_enemy(far, 1)
	t.check(int(h4.enemies[near]["hp"]) < int(h4.enemies[near]["max_hp"]), "溢出伤害炸到半径 60 内的邻近敌人")

	# (6) 未解锁超杀时不产生溢出爆炸
	var h5 := NetHostLogic.new()
	h5.reset()
	h5.spawn_interval = 9999.0
	var near2 := h5.spawn_enemy(Vector2(140, 0))
	var far2 := h5.spawn_enemy(Vector2(100, 0))
	h5.enemies[far2]["hp"] = -30
	h5._kill_enemy(far2, 0)
	t.eq(int(h5.enemies[near2]["hp"]), int(h5.enemies[near2]["max_hp"]), "无超杀修饰时邻近敌人不受影响")

	return t.report("SkillLogic")


func _cmd(effect: int, cond: int, cond_value: int, loops: int, damage: int = 10) -> Dictionary:
	## 构造一条与 SkillRuntime 输出同形的动作指令。
	return {
		"effect": effect,
		"element": Skills.ELEM_PHYS,
		"elements": [Skills.ELEM_PHYS],
		"damage": damage,
		"damage_base": damage,
		"radius": 45.0,
		"count": 1,
		"ttl": 0.5,
		"speed": 0.0,
		"pierce": 0,
		"cond": cond,
		"cond_value": cond_value,
		"loops": loops,
		"wave_damage": 0,
	}
