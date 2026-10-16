extends RefCounted
## 技能运行时执行器测试（子项目 5）：事件→触发链→动作指令、跳数上限、每秒限频、修饰叠加。

const Harness := preload("res://tools/tests/harness.gd")
const Skills := preload("res://sim/skills.gd")
const Runtime := preload("res://sim/skill_runtime.gd")


func run() -> int:
	var t := Harness.new()

	t.eq(Runtime.MAX_CHAIN_JUMPS, 3, "链式跳数硬上限为 3")

	# —— 周期触发：字节农场每 2s 产币 ——
	var coin := [1]
	var st := Runtime.new_state()
	t.eq(Runtime.tick(st, coin, 1.0, 0.0).size(), 0, "1s 未到 2s 周期，不产出")
	var out := Runtime.tick(st, coin, 1.1, 1.1)
	t.eq(out.size(), 1, "累计 2.1s 产出 1 条指令")
	t.eq(int(out[0]["effect"]), Skills.EFF_SPAWN_BYTE, "指令为生成字节币")
	t.eq(int(out[0]["count"]), 1, "产出 1 枚字节币")

	# —— 「遍历」+「数据弹」：周期触发挂到命中挂钩的动作 ——
	# 数据弹挂在命中挂钩(2)上，遍历(0)是周期触发，故遍历不会直接带出数据弹
	var trig := [0, 2, 8]
	var st2 := Runtime.new_state()
	t.eq(Runtime.tick(st2, trig, 1.3, 0.0).size(), 0, "遍历后继为空（数据弹挂命中挂钩）")
	var ev := Runtime.dispatch(st2, trig, Skills.TRIG_HIT, 0.0)
	t.eq(ev.size(), 1, "命中事件触发 1 条动作指令")
	t.eq(int(ev[0]["node"]), 8, "命中触发的是数据弹")
	t.eq(int(ev[0]["damage"]), 14, "数据弹基础伤害 14")
	t.eq(bool(ev[0]["chained"]), false, "首跳非链式")

	# —— 每秒限频：同一触发节点在 1s 内第二次事件被吞掉 ——
	t.eq(Runtime.dispatch(st2, trig, Skills.TRIG_HIT, 0.5).size(), 0, "同一秒内重复触发被限频")
	t.eq(Runtime.dispatch(st2, trig, Skills.TRIG_HIT, 1.2).size(), 1, "超过 1s 后可再次触发")

	# —— 修饰叠加：溢出伤害 + 范围扩张 ——
	var buffed := [2, 8, 24, 26]
	var st3 := Runtime.new_state()
	var cmd := Runtime.dispatch(st3, buffed, Skills.TRIG_HIT, 0.0)
	t.eq(int(cmd[0]["damage"]), 18, "溢出伤害 +4 → 数据弹 18")
	t.check(absf(float(cmd[0]["radius"]) - 9.0 * 1.25) < 0.0001, "范围扩张作用于弹丸半径")

	# —— 元素修饰：灼烧附加火元素 ——
	var fiery := [2, 8, 29]
	var st4 := Runtime.new_state()
	var fcmd := Runtime.dispatch(st4, fiery, Skills.TRIG_HIT, 0.0)
	t.eq(int(fcmd[0]["element"]), Skills.ELEM_FIRE, "灼烧使攻击带火元素")
	t.check((fcmd[0]["elements"] as Array).has(Skills.ELEM_FIRE), "元素列表含火")

	# —— 链式：字节农场周期开火 → 字节风暴引爆 → 追加击杀事件 → 核打击 ——
	var storm := [1, 3, 10, 12]
	var st5 := Runtime.new_state()
	var out5 := Runtime.tick(st5, storm, 2.05, 2.05)
	var has_storm := false
	var has_nuke := false
	var max_chain := false
	for c in out5:
		if int(c["node"]) == 10:
			has_storm = true
		if int(c["node"]) == 12:
			has_nuke = true
			if bool(c["chained"]):
				max_chain = true
	t.check(has_storm, "周期开火带出字节风暴")
	t.check(has_nuke, "字节风暴链式再触发击杀挂钩→核打击")
	t.check(max_chain, "核打击经由链式（jump>0）产生")

	# 链式跳数上限：无「串联」时 2，解锁后 3
	t.eq(Runtime.chain_jumps([2, 8]), 2, "默认链式跳数上限 2")
	t.eq(Runtime.chain_jumps([2, 8, 32]), 3, "串联 → 上限 3")

	# —— 空节点/未知节点不产生指令 ——
	var st6 := Runtime.new_state()
	t.eq(Runtime.dispatch(st6, [], Skills.TRIG_HIT, 0.0).size(), 0, "无节点无指令")
	t.eq(Runtime.tick(st6, [999], 5.0, 5.0).size(), 0, "未知节点被忽略")

	# —— 条件分支：指令携带门禁，判定留给权威侧（runtime 不做状态判定） ——
	var cond_set := Runtime.new_state()
	var ccmd := Runtime.dispatch(cond_set, [5, 35, 40], Skills.TRIG_HURT, 0.0)
	t.eq(ccmd.size(), 1, "受击事件经条件分支带出空指针 1 条指令")
	t.eq(int(ccmd[0]["node"]), 40, "带出门禁后的动作 ID")
	t.eq(int(ccmd[0]["cond"]), Skills.COND_LOW_HP, "指令携带低血量门禁")
	t.eq(int(ccmd[0]["cond_value"]), 50, "门禁阈值 50")

	# —— 循环：指令携带重复次数 ——
	var loop_set := Runtime.new_state()
	var lcmd := Runtime.tick(loop_set, [0, 36, 42], 1.3, 1.3)
	t.eq(lcmd.size(), 1, "遍历经循环带出 1 条指令")
	t.eq(int(lcmd[0]["node"]), 42, "带出千兆攻击")
	t.eq(int(lcmd[0]["loops"]), 2, "指令携带循环次数 2")

	# —— 进化脉冲：指令携带每波次额外伤害，供权威侧按波次放大 ——
	var evo_set := Runtime.new_state()
	var ecmd := Runtime.dispatch(evo_set, [2, 8, 47], Skills.TRIG_HIT, 0.0)
	t.eq(int(ecmd[0]["wave_damage"]), 10, "进化脉冲随指令下发每波次伤害")

	return t.report("SkillRuntime")
