extends RefCounted
## 敌人 AI 测试：追击方向、按速度步进、零方向静止。

const Harness := preload("res://tools/tests/harness.gd")
const EnemyAI := preload("res://sim/enemy_ai.gd")
const Combat := preload("res://sim/combat.gd")


func run() -> int:
	var t := Harness.new()

	var targets: Array = [
		{"pos": Vector2(60, 0)},
		{"pos": Vector2(0, 90)},
	]
	var dir := EnemyAI.chase_dir(Vector2.ZERO, targets)
	t.check((dir - Vector2.RIGHT).length() < 0.001, "追最近的玩家（右侧）")

	var p := EnemyAI.step(Vector2.ZERO, Vector2.RIGHT, 1.0)
	t.check(absf(p.x - Combat.ENEMY_SPEED) < 0.001, "步进 x = ENEMY_SPEED*dt")
	t.check(absf(p.y) < 0.001, "步进 y 不变")

	var stay := EnemyAI.step(Vector2(5, 5), Vector2.ZERO, 1.0)
	t.eq(stay, Vector2(5, 5), "零方向原地不动")

	var slow := EnemyAI.step(Vector2.ZERO, Vector2.RIGHT, 1.0, 50.0)
	t.check(absf(slow.x - 50.0) < 0.001, "显式 speed 覆盖默认速度（x）")
	t.check(absf(slow.y) < 0.001, "显式 speed 覆盖默认速度（y 不变）")

	return t.report("EnemyAI")
