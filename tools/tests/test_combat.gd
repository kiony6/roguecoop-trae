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

	return t.report("Combat")
