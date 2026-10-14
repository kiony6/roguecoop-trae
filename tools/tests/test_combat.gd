extends RefCounted
## 战斗纯函数测试：自动瞄准方向、圆-圆命中判定。

const Harness := preload("res://tools/tests/harness.gd")
const Combat := preload("res://sim/combat.gd")


func run() -> int:
	var t := Harness.new()

	t.eq(Combat.aim_dir(Vector2.ZERO, []), Vector2.ZERO, "无敌人时瞄准方向为零向量")

	var enemies: Array = [
		{"pos": Vector2(100, 0)},
		{"pos": Vector2(10, 0)},
	]
	var d := Combat.aim_dir(Vector2.ZERO, enemies)
	t.check((d - Vector2.RIGHT).length() < 0.001, "瞄向最近的敌人（右侧）")

	var up := Combat.aim_dir(Vector2.ZERO, [{"pos": Vector2(0, -50)}])
	t.check((up - Vector2.UP).length() < 0.001, "瞄向上方敌人")

	t.check(Combat.circle_hit(Vector2.ZERO, 10.0, Vector2(15, 0), 5.0), "相切（距离=半径和）判为命中")
	t.check(not Combat.circle_hit(Vector2.ZERO, 10.0, Vector2(16, 0), 5.0), "略微分离判为不命中")

	# —— M3：按 kind 派生敌人属性 + 掉落经验值 ——
	t.eq(Combat.enemy_max_hp(Combat.ENEMY_KIND_NORMAL), 30, "普通怪最大血量 30")
	t.eq(Combat.enemy_max_hp(Combat.ENEMY_KIND_BOSS), 200, "Boss 最大血量 200")
	t.eq(Combat.enemy_radius(Combat.ENEMY_KIND_BOSS), 28.0, "Boss 半径 28")
	t.eq(Combat.enemy_speed(Combat.ENEMY_KIND_BOSS), 70.0, "Boss 速度 70")
	t.eq(Combat.enemy_touch_damage(Combat.ENEMY_KIND_BOSS), 20, "Boss 接触伤害 20")
	t.eq(Combat.loot_xp(Combat.LOOT_KIND_XP), 5, "普通碎片经验 5")
	t.eq(Combat.loot_xp(Combat.LOOT_KIND_BIG), 25, "Boss 大碎片经验 25")

	return t.report("Combat")
