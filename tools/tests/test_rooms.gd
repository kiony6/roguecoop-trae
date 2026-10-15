extends RefCounted
## 房间纯逻辑测试（M4）：确定性生成、出生区无障碍、点-矩形碰撞、边界钳制。

const Harness := preload("res://tools/tests/harness.gd")
const Rooms := preload("res://sim/rooms.gd")


func run() -> int:
	var t := Harness.new()

	var a := Rooms.generate(20261015)
	var b := Rooms.generate(20261015)
	t.eq(a.size(), b.size(), "同种子生成墙体数量一致")
	t.eq(a, b, "同种子生成墙体完全一致")
	t.check(a.size() >= 1, "主机默认种子(20261015)至少生成一堵墙")

	var clear_ok := true
	for i in 16:
		var ang := TAU * float(i) / 16.0
		var p := Vector2.RIGHT.rotated(ang) * (Rooms.CLEAR_RADIUS * 0.9)
		if Rooms.blocked(a, p, 0.0):
			clear_ok = false
	t.check(clear_ok, "出生区（0.9*CLEAR_RADIUS 内）无障碍")

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
