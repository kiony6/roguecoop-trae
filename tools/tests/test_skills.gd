extends RefCounted
## 技能节点纯逻辑测试（子项目 5）：节点表、分层、解锁门禁、元素反应、初始构筑、弹丸半径。

const Harness := preload("res://tools/tests/harness.gd")
const Skills := preload("res://sim/skills.gd")
const Weapons := preload("res://sim/weapons.gd")


func run() -> int:
	var t := Harness.new()

	t.eq(Skills.count(), 43, "共 43 个技能节点")
	t.eq(Skills.nodes_of_layer(Skills.LAYER_TRIGGER).size(), 6, "触发层 6 个")
	t.eq(Skills.nodes_of_layer(Skills.LAYER_ACTION).size(), 22, "动作层 22 个")
	t.eq(Skills.nodes_of_layer(Skills.LAYER_LOGIC).size(), 2, "条件/循环层 2 个")
	t.eq(Skills.nodes_of_layer(Skills.LAYER_MOD).size(), 13, "修饰层 13 个")

	t.eq(Skills.name_of(1), "字节农场", "字节农场名称")
	t.eq(Skills.name_of(12), "核打击", "核打击名称")
	t.check(Skills.has_node(34), "拾取半径存在")
	t.check(not Skills.has_node(99), "未知节点不存在")
	t.check(Skills.by_id(99).is_empty(), "未知节点返回空字典")

	# 触发层的 trigger 字段自洽
	t.eq(int(Skills.by_id(0)["trigger"]), Skills.TRIG_INTERVAL, "遍历是周期触发")
	t.eq(int(Skills.by_id(3)["trigger"]), Skills.TRIG_KILL, "击杀挂钩是击杀触发")
	t.eq(int(Skills.by_id(1)["effect"]), Skills.EFF_SPAWN_BYTE, "字节农场效果为生成字节币")

	# 事件 → 触发节点
	t.eq(Skills.trigger_nodes_for(Skills.TRIG_KILL), [3], "击杀事件仅由击杀挂钩响应")
	var iv := Skills.trigger_nodes_for(Skills.TRIG_INTERVAL)
	t.check(iv.has(0) and iv.has(1), "周期事件由遍历与字节农场响应")

	# 解锁门禁
	t.check(Skills.can_unlock([], 0, 1), "有 1 点即可解锁遍历")
	t.check(not Skills.can_unlock([], 0, 0), "0 技能点不可解锁")
	t.check(not Skills.can_unlock([], 8, 5), "数据弹需前置命中挂钩")
	t.check(Skills.can_unlock([2], 8, 5), "解锁命中挂钩后可解锁数据弹")
	t.check(not Skills.can_unlock([], 24, 5), "修饰层需先解锁任一动作")
	t.check(Skills.can_unlock([8], 24, 5), "解锁动作后可解锁修饰层")
	t.check(not Skills.can_unlock([0], 0, 5), "重复解锁被拒绝")
	t.check(not Skills.can_unlock([], 42, 5), "未知节点不可解锁")

	var u := Skills.unlock([], 0)
	t.eq(u, [0], "unlock 返回追加后的新数组")
	t.eq(Skills.unlock([0], 1), [0, 1], "unlock 可连续追加")
	var granted := Skills.grant([], [0, 1, 9])
	t.eq(granted, [0, 1, 9], "构造授予跳过前置校验")
	t.eq(Skills.grant([0], [0, 1]), [0, 1], "构造授予去重")

	# 分层筛选
	t.eq(Skills.triggers_of([0, 8, 24]), [0], "触发层筛选")
	t.eq(Skills.actions_of([0, 8, 24]), [8], "动作层筛选")
	t.eq(Skills.mods_of([0, 8, 24]), [24], "修饰层筛选")
	t.eq(Skills.actions_for([2, 8, 14], 2), [8, 14], "挂载在命中挂钩下的动作")

	# 修饰聚合
	var m := Skills.modifiers([24, 26, 27, 29, 32, 33])
	t.eq(int(m["damage_add"]), 4, "溢出伤害 +4")
	t.check(absf(float(m["radius_scale"]) - 1.25) < 0.0001, "范围扩张 ×1.25")
	t.eq(int(m["pierce"]), 1, "穿透 +1")
	t.eq(int(m["chain_bonus"]), 1, "串联 +1")
	t.eq((m["elements"] as Array).size(), 1, "元素修饰聚合出 1 个元素")
	t.check(absf(float(m["byte_gain"]) - 1.25) < 0.0001, "字节币效益 ×1.25")
	var m2 := Skills.modifiers([25])
	t.check(absf(float(m2["cooldown_scale"]) - 0.85) < 0.0001, "超频 ×0.85")

	# 弹丸半径：武器沿用，技能弹查表
	t.check(absf(Skills.projectile_radius(Weapons.KIND_PISTOL) - 8.0) < 0.0001, "手枪半径沿用武器表")
	t.check(absf(Skills.projectile_radius(Weapons.KIND_SHOTGUN) - 7.0) < 0.0001, "霰弹枪半径沿用武器表")
	t.check(absf(Skills.projectile_radius(8) - 9.0) < 0.0001, "数据弹半径 9")

	# 元素反应
	var r1 := Skills.reaction(Skills.ELEM_FIRE, Skills.ELEM_FROST)
	t.eq(String(r1.get("name", "")), "蒸汽爆裂", "火+冰 → 蒸汽爆裂")
	var r1b := Skills.reaction(Skills.ELEM_FROST, Skills.ELEM_FIRE)
	t.eq(String(r1b.get("name", "")), "蒸汽爆裂", "元素对顺序无关")
	var r2 := Skills.reaction(Skills.ELEM_FROST, Skills.ELEM_ELEC)
	t.eq(String(r2.get("name", "")), "超导", "冰+电 → 超导")
	var r3 := Skills.reaction(Skills.ELEM_FIRE, Skills.ELEM_ELEC)
	t.eq(int(r3.get("damage", 0)), 50, "火+电 → 等离子 50 伤害")
	t.check(Skills.reaction(Skills.ELEM_PHYS, Skills.ELEM_FIRE).is_empty(), "物理参战无反应")
	t.check(Skills.reaction(Skills.ELEM_FIRE, Skills.ELEM_FIRE).is_empty(), "同元素无反应")

	# 初始构筑
	t.eq(Skills.presets().size(), 13, "13 个初始构筑（对齐原作 13 名 Hacker）")
	t.eq(Skills.preset_ids().size(), 13, "构筑 id 列表同为 13 个")
	t.eq(Skills.preset("COIN")["nodes"], [0, 1, 9], "字节币流起始节点")
	t.eq(Skills.default_preset(), "COIN", "默认构筑为字节币流")
	t.eq(Skills.preset("SPIKE")["nodes"], [2, 37, 27], "尖刺流起始节点")
	t.check(Skills.preset("NOPE").is_empty(), "未知构筑返回空")

	# 条件/循环层
	t.eq(int(Skills.by_id(35)["layer"]), Skills.LAYER_LOGIC, "条件分支在条件/循环层")
	t.eq(int(Skills.by_id(35)["cond"]), Skills.COND_LOW_HP, "条件分支按生命比例判定")
	t.eq(int(Skills.by_id(36)["effect"]), Skills.EFF_LOOP, "循环节点效果为 LOOP")
	t.eq(int(Skills.by_id(36)["count"]), 2, "循环重复 2 次")
	t.eq(Skills.MAX_LOOPS, 3, "循环硬上限 3")
	t.eq(Skills.trigger_nodes_for(Skills.TRIG_HURT), [5], "受击事件仍仅由受击挂钩响应")

	# 逻辑层门禁：动作要挂到条件/循环节点上，需先解锁该逻辑节点
	t.check(not Skills.can_unlock([], 35, 5), "条件分支需先解锁受击挂钩")
	t.check(Skills.can_unlock([5], 35, 5), "解锁受击挂钩后可解锁条件分支")
	t.check(not Skills.can_unlock([5], 40, 5), "空指针需先解锁条件分支")
	t.check(Skills.can_unlock([5, 35], 40, 5), "解锁条件分支后可解锁空指针")
	t.check(not Skills.can_unlock([0], 42, 5), "千兆攻击需先解锁循环")
	t.check(Skills.can_unlock([0, 36], 42, 5), "解锁循环后可解锁千兆攻击")

	# 「触发 →（条件/循环）→ 动作」的解析
	# 第二个参数是「触发挂钩节点 id」（0=遍历 … 5=受击），不是事件常量
	var direct := Skills.chain_for([0, 2, 8], 2)
	t.eq(direct.size(), 1, "直连触发的动作仅 1 步")
	t.eq(int(direct[0]["node"]), 8, "直连动作为挂在命中挂钩下的数据弹")
	t.eq(int(direct[0]["cond"]), Skills.COND_NONE, "直连动作无门禁")
	t.eq(int(direct[0]["loops"]), 1, "直连动作不循环")
	var gated := Skills.chain_for([5, 35, 40, 18], 5)
	t.eq(gated.size(), 2, "受击触发：直连防火墙 + 经条件分支的空指针")
	t.eq(int(gated[1]["node"]), 40, "第二步为空指针（挂在条件分支下）")
	t.eq(int(gated[1]["cond"]), Skills.COND_LOW_HP, "空指针带低血量条件门禁")
	t.eq(int(gated[1]["cond_value"]), 50, "条件阈值为 50%")
	t.eq(Skills.logic_for([5, 35, 40], 5).size(), 1, "条件分支挂在受击挂钩下")
	var looped := Skills.chain_for([0, 36, 42], 0)
	t.eq(looped.size(), 1, "遍历 → 循环 → 千兆攻击为 1 步")
	t.eq(int(looped[0]["loops"]), 2, "经循环的动作每次触发执行 2 遍")

	# 标志性节点与新增修饰聚合
	t.eq(Skills.name_of(39), "BUG 机制", "BUG 机制名称")
	t.eq(int(Skills.by_id(39)["element"]), Skills.ELEM_ELEC, "BUG 机制带电元素")
	t.eq(int(Skills.by_id(37)["effect"]), Skills.EFF_SPIKE, "尖刺数据包效果")
	t.eq(Skills.PROJ_SPIKE, 14, "尖刺弹 kind 为 14")
	t.check(absf(Skills.projectile_radius(Skills.PROJ_SPIKE) - 5.0) < 0.0001, "尖刺弹半径 5")
	var m3 := Skills.modifiers([46, 47])
	t.check(float(m3["overkill_radius"]) > 0.0, "超杀提供溢出伤害半径")
	t.eq(int(m3["wave_damage"]), 10, "进化脉冲提供每波次额外伤害")

	return t.report("Skills")
