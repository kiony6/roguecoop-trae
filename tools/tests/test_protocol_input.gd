extends RefCounted
## 输入帧编解码测试：长度固定、往返精度、越界夹紧。

const Harness := preload("res://tools/tests/harness.gd")
const Protocol := preload("res://net/protocol.gd")


func run() -> int:
	var t := Harness.new()

	t.eq(
		Protocol.encode_input(Vector2.ZERO, Vector2.RIGHT, 0).size(),
		Protocol.INPUT_BYTES,
		"输入帧长度 = 5"
	)

	var f := Protocol.decode_input(Protocol.encode_input(Vector2(1, 0), Vector2(0, -1), 3))
	t.check(absf(f["move"].x - 1.0) < 0.01, "move.x 往返 ≈ 1.0")
	t.check(absf(f["move"].y) < 0.01, "move.y 往返 ≈ 0.0")
	t.check(absf(f["aim"].y + 1.0) < 0.01, "aim.y 往返 ≈ -1.0")
	t.eq(f["buttons"], 3, "buttons 往返")

	var g := Protocol.decode_input(Protocol.encode_input(Vector2(9.0, -9.0), Vector2.ZERO, 0))
	t.check(g["move"].x > 0.99, "超范围 move.x 夹到 +1")
	t.check(g["move"].y < -0.99, "超范围 move.y 夹到 -1")

	return t.report("ProtocolInput")
