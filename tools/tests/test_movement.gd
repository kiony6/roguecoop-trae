extends RefCounted
## 移动步进测试：直线位移、斜向归一化、零输入静止。

const Harness := preload("res://tools/tests/harness.gd")
const Movement := preload("res://sim/movement.gd")


func run() -> int:
	var t := Harness.new()

	var p := Movement.step(Vector2.ZERO, Vector2(1, 0), 0.5)
	t.check(absf(p.x - Movement.SPEED * 0.5) < 0.001, "右移一步 x = SPEED*dt")
	t.check(absf(p.y) < 0.001, "右移一步 y 不变")

	var q := Movement.step(Vector2.ZERO, Vector2(1, 1), 1.0)
	t.check(absf(q.length() - Movement.SPEED) < 0.001, "斜向输入被归一化")

	var z := Movement.step(Vector2(5, 5), Vector2.ZERO, 1.0)
	t.eq(z, Vector2(5, 5), "零输入原地不动")

	var half := Movement.step(Vector2.ZERO, Vector2(0.5, 0), 1.0)
	t.check(absf(half.x - Movement.SPEED * 0.5) < 0.001, "半速输入不被放大")

	var fast := Movement.step(Vector2.ZERO, Vector2.RIGHT, 1.0, 100.0)
	t.check(absf(fast.x - 100.0) < 0.001, "显式 speed 覆盖默认速度")

	return t.report("Movement")
