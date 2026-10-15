extends RefCounted
## 房间纯逻辑测试：墙体已移除（generate 恒空）、点-矩形碰撞、边界钳制。

const Harness := preload("res://tools/tests/harness.gd")
const Rooms := preload("res://sim/rooms.gd")


func run() -> int:
	var t := Harness.new()

	t.check(Rooms.generate(20261015).is_empty(), "主机默认种子(20261015)不生成任何墙体")

	var one: Array = [Rect2(10.0, 10.0, 20.0, 20.0)]
	t.check(Rooms.blocked(one, Vector2(20.0, 20.0), 0.0), "点在墙内")
	t.check(not Rooms.blocked(one, Vector2(40.0, 20.0), 0.0), "点在墙外")

	var ar := Rooms.arena_rect()
	t.check(absf(ar.position.x + Rooms.ARENA_HALF.x) < 0.001, "竞技场左上角 = -半宽")
	t.check(absf(ar.size.x - Rooms.ARENA_HALF.x * 2.0) < 0.001, "竞技场宽度 = 2*半宽")
	t.eq(
		Rooms.clamp_inside(Vector2(99999.0, -99999.0), 0.0),
		Rooms.ARENA_HALF * Vector2(1, -1),
		"越界点钳制到竞技场角"
	)
	t.eq(Rooms.clamp_inside(Vector2(10.0, 20.0), 0.0), Vector2(10.0, 20.0), "场内点不变")

	return t.report("Rooms")
