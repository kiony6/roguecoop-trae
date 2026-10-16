extends RefCounted
## 特效传输链路测试：技能动作 → 特效事件（含方向）→ 派发载荷。
## 覆盖：_emit_fx 的 dir 透传、非方向性特效默认零向量、
##       EFF_LASER 产生带方向的 FX_LASER 亮束（束长取固定值而非弹丸半径）、
##       EFF_DRAIN 产生带方向的 FX_DRAIN 连线。

const Harness := preload("res://tools/tests/harness.gd")
const NetHostLogic := preload("res://net/net_host.gd")
const Combat := preload("res://sim/combat.gd")
const Skills := preload("res://sim/skills.gd")


func run() -> int:
	var t := Harness.new()

	# (1) _emit_fx 透传方向；非方向性特效方向为零向量
	var h1 := NetHostLogic.new()
	h1.reset()
	h1._emit_fx(Combat.FX_LASER, Vector2(5, 0), 260.0, Vector2.UP)
	h1._emit_fx(Combat.FX_HIT, Vector2(6, 0), 0.0)
	var evs: Array = h1.take_fx_events()
	t.eq(evs.size(), 2, "两个特效事件入队")
	t.eq(evs[0]["dir"], Vector2.UP, "方向性特效携带方向")
	t.eq(evs[1]["dir"], Vector2.ZERO, "非方向性特效方向为零向量")
	t.eq(h1.take_fx_events().size(), 0, "取走后队列清空")

	# (2) EFF_LASER：产生 FX_LASER 亮束，方向对准敌人，束长大于弹丸半径
	var h2 := NetHostLogic.new()
	h2.reset()
	h2.spawn_interval = 9999.0
	h2.spawn_enemy(Vector2(0, 120))  # 敌人在正下方 → 期望方向向下
	h2._apply_commands(1, [_cmd(Skills.EFF_LASER, 12.0)])
	var fx2: Array = h2.take_fx_events()
	t.eq(fx2.size(), 1, "激光技能产生 1 个特效事件")
	t.eq(int(fx2[0]["kind"]), Combat.FX_LASER, "特效种类为 FX_LASER（此前从未发出）")
	t.eq(fx2[0]["dir"], Vector2.DOWN, "亮束方向对准下方敌人")
	t.check(float(fx2[0]["radius"]) > 100.0, "亮束长度取固定值而非弹丸半径 12.0")

	# (3) EFF_DRAIN：产生带方向的 FX_DRAIN 连线
	var h3 := NetHostLogic.new()
	h3.reset()
	h3.spawn_interval = 9999.0
	h3.spawn_enemy(Vector2(0, 120))
	h3._apply_commands(1, [_cmd(Skills.EFF_DRAIN, 70.0)])
	var fx3: Array = h3.take_fx_events()
	t.eq(fx3.size(), 1, "吸血技能产生 1 个特效事件")
	t.eq(int(fx3[0]["kind"]), Combat.FX_DRAIN, "特效种类为 FX_DRAIN")
	t.eq(fx3[0]["dir"], Vector2.DOWN, "吸血连线方向对准下方敌人")

	# (4) 无敌人时方向退化，但特效事件仍发出（客户端不会因空方向而崩）
	var h4 := NetHostLogic.new()
	h4.reset()
	h4.spawn_interval = 9999.0
	h4._apply_commands(1, [_cmd(Skills.EFF_LASER, 12.0)])
	t.eq(h4.take_fx_events().size(), 1, "无敌人时仍产生 FX_LASER 事件")

	return t.report("FxChain")


func _cmd(effect: int, radius: float) -> Dictionary:
	## 构造一条与 SkillRuntime 输出同形的动作指令（此处只关心效果种类与半径）。
	return {
		"effect": effect,
		"element": Skills.ELEM_PHYS,
		"elements": [Skills.ELEM_PHYS],
		"damage": 10,
		"damage_base": 10,
		"radius": radius,
		"count": 1,
		"ttl": 0.5,
		"speed": 900.0,
		"pierce": 0,
	}
