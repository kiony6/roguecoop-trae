extends RefCounted
## AOI 裁剪测试：半径内保留、半径外剔除、空集合、远心为空。

const Harness := preload("res://tools/tests/harness.gd")
const AoI := preload("res://net/aoi.gd")


func run() -> int:
	var t := Harness.new()

	var ents: Array = [
		{"id": 1, "pos": Vector2(0, 0)},
		{"id": 2, "pos": Vector2(500, 0)},
		{"id": 3, "pos": Vector2(900, 0)},
	]
	var c := AoI.cull(Vector2.ZERO, 720.0, ents)
	t.eq(c.size(), 2, "半径 720 内保留 2 个")
	t.eq(c[0]["id"], 1, "保留 id=1")
	t.eq(c[1]["id"], 2, "保留 id=2")

	t.eq(AoI.cull(Vector2(5000, 0), 720.0, ents).size(), 0, "远离全部 → 空")
	t.eq(AoI.cull(Vector2.ZERO, 720.0, []).size(), 0, "空集合 → 空")

	return t.report("AoI")
