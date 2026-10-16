extends RefCounted
## 敌人元素状态测试（纯逻辑，无传输）。
## 覆盖：元素附着 / 稀疏载荷构造 / 元素反应吃掉状态 / 到期自动清除 / 击杀即消失 /
## 载荷条目上限 / 物理弹不产生状态 / 快照敌人段不含 element（线格式未变）。

const Harness := preload("res://tools/tests/harness.gd")
const NetHostLogic := preload("res://net/net_host.gd")
const Skills := preload("res://sim/skills.gd")


func run() -> int:
	var t := Harness.new()

	# (1) 物理弹不附着元素：稀疏载荷始终为空
	var h1 := NetHostLogic.new()
	h1.reset()
	h1.spawn_interval = 9999.0
	var eid1 := h1.spawn_enemy(Vector2(120, 0))
	h1.enemies[eid1]["hp"] = 999999
	_inject(h1, eid1, Skills.ELEM_PHYS)
	h1.physics_step(0.016)
	t.eq(int(h1.enemies[eid1]["element"]), Skills.ELEM_PHYS, "物理弹不附着元素")
	t.eq(h1.element_states().size(), 0, "物理状态下稀疏载荷为空")

	# (2) 火弹点燃敌人：状态落到敌人身上，且进入稀疏载荷
	var h2 := NetHostLogic.new()
	h2.reset()
	h2.spawn_interval = 9999.0
	var eid2 := h2.spawn_enemy(Vector2(120, 0))
	h2.enemies[eid2]["hp"] = 999999
	_inject(h2, eid2, Skills.ELEM_FIRE)
	h2.physics_step(0.016)
	t.eq(int(h2.enemies[eid2]["element"]), Skills.ELEM_FIRE, "火弹把敌人点燃")
	var es2: Array = h2.element_states()
	t.eq(es2.size(), 1, "稀疏载荷含 1 条元素状态")
	t.eq(int(es2[0]["id"]), eid2, "载荷 id 与被点燃敌人一致")
	t.eq(int(es2[0]["elem"]), Skills.ELEM_FIRE, "载荷元素为火")
	t.check(not h2.enemy_states()[0].has("element"), "快照敌人段不含 element 字段（线格式未变）")

	# (3) 元素反应吃掉状态：火 + 冰 → 反应后元素清空、稀疏载荷不再上报
	var h3 := NetHostLogic.new()
	h3.reset()
	h3.spawn_interval = 9999.0
	var eid3 := h3.spawn_enemy(Vector2(120, 0))
	h3.enemies[eid3]["hp"] = 999999
	_inject(h3, eid3, Skills.ELEM_FIRE)
	h3.physics_step(0.016)
	t.eq(int(h3.enemies[eid3]["element"]), Skills.ELEM_FIRE, "先挂上火元素")
	_inject(h3, eid3, Skills.ELEM_FROST)
	h3.physics_step(0.016)
	t.eq(int(h3.enemies[eid3]["element"]), Skills.ELEM_PHYS, "火冰反应后元素被吃掉")
	t.eq(h3.element_states().size(), 0, "反应后不再上报该敌元素")

	# (4) 元素到期自动清除：3 秒后元素归零
	var h4 := NetHostLogic.new()
	h4.reset()
	h4.spawn_interval = 9999.0
	var eid4 := h4.spawn_enemy(Vector2(3000, 3000))
	h4.enemies[eid4]["hp"] = 999999
	_inject(h4, eid4, Skills.ELEM_FROST)
	h4.physics_step(0.016)
	t.eq(h4.element_states().size(), 1, "冰元素刚附着时在载荷内")
	var steps := int(ceilf(Skills.ELEMENT_SECONDS / 0.016)) + 20
	for _i in range(steps):
		h4.physics_step(0.016)
	t.eq(int(h4.enemies[eid4]["element"]), Skills.ELEM_PHYS, "超过时长后元素被清除")
	t.eq(h4.element_states().size(), 0, "到期后稀疏载荷为空")

	# (5) 击杀即消失：敌人被击杀后载荷不再含该敌
	var h5 := NetHostLogic.new()
	h5.reset()
	h5.spawn_interval = 9999.0
	var eid5 := h5.spawn_enemy(Vector2(3000, 3000))
	h5.enemies[eid5]["hp"] = 999999
	_inject(h5, eid5, Skills.ELEM_ELEC)
	h5.physics_step(0.016)
	t.eq(h5.element_states().size(), 1, "电元素附着后进入载荷")
	h5._kill_enemy(eid5)
	t.eq(h5.element_states().size(), 0, "击杀后元素状态随敌人一起消失")

	# (6) 载荷条目上限：超出 MAX_ELEMENT_SYNC 的条目被截断
	var h6 := NetHostLogic.new()
	h6.reset()
	h6.spawn_interval = 9999.0
	for i in range(Skills.MAX_ELEMENT_SYNC + 8):
		var eid := h6.spawn_enemy(Vector2(3000 + float(i), 3000))
		h6.enemies[eid]["element"] = Skills.ELEM_FIRE
		h6.enemies[eid]["element_until"] = h6.elapsed + Skills.ELEMENT_SECONDS
	t.eq(
		h6.element_states().size(),
		Skills.MAX_ELEMENT_SYNC,
		"稀疏载荷被上限 %d 截断" % Skills.MAX_ELEMENT_SYNC
	)

	return t.report("EnemyElement")


func _inject(h, eid: int, elem: int) -> void:
	## 在敌人位置注入一枚零伤害弹丸，驱动 _resolve_element 走元素附着路径。
	h.projectiles[9999] = {
		"pos": h.enemies[eid]["pos"],
		"vel": Vector2.ZERO,
		"ttl": 1.0,
		"dmg": 0,
		"owner": 1,
		"kind": Skills.PROJ_DATA,
		"elements": [elem],
	}
