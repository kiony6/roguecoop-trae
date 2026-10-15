extends RefCounted
## 移动步进测试：直线位移、斜向归一化、零输入静止。

const Harness := preload("res://tools/tests/harness.gd")
const Movement := preload("res://sim/movement.gd")
const Rooms := preload("res://sim/rooms.gd")
const Combat := preload("res://sim/combat.gd")


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

	# —— M4：墙体阻挡 / 沿墙滑动 / 竞技场边界 ——
	var walls: Array = [Rect2(60.0, -50.0, 40.0, 100.0)]
	var blocked := Movement.step(Vector2.ZERO, Vector2.RIGHT, 1.0, Movement.SPEED, walls)
	var wall_edge := 60.0 - Combat.PLAYER_RADIUS
	t.check(absf(blocked.x - wall_edge) < 0.001, "右移被墙体挡在墙前")
	t.check(absf(blocked.y) < 0.001, "被挡时 y 不漂移")

	var slide := Movement.step(Vector2(wall_edge, 0.0), Vector2(1, 1), 1.0, Movement.SPEED, walls)
	t.check(absf(slide.x - wall_edge) < 0.001, "贴墙时 x 被挡住")
	t.check(slide.y > 100.0, "贴墙时仍能沿墙下滑")

	var edge := Movement.step(Vector2.ZERO, Vector2.RIGHT, 100.0, Movement.SPEED, [])
	var arena_edge := Rooms.ARENA_HALF.x - Combat.PLAYER_RADIUS
	t.check(absf(edge.x - arena_edge) < 0.001, "越界被钳制到竞技场边界")

	return t.report("Movement")
