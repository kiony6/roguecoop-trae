extends RefCounted
## 快照编解码测试：长度公式、tick/id 往返、浮点位置往返。

const Harness := preload("res://tools/tests/harness.gd")
const Protocol := preload("res://net/protocol.gd")


func run() -> int:
	var t := Harness.new()

	var players: Array = [
		{"id": 1, "pos": Vector2(10.5, -20.25)},
		{"id": 3, "pos": Vector2(0.0, 0.0)},
	]

	var bytes := Protocol.encode_snapshot(42, players)
	t.eq(bytes.size(), Protocol.snapshot_size(2), "快照长度 = 5 + 2*10")
	t.eq(bytes.size(), 25, "快照长度硬校验 = 25")

	var d := Protocol.decode_snapshot(bytes)
	t.eq(d["tick"], 42, "tick 往返")
	t.eq(d["players"].size(), 2, "玩家数往返")
	t.eq(d["players"][0]["id"], 1, "id[0] 往返")
	t.check((d["players"][0]["pos"] - Vector2(10.5, -20.25)).length() < 0.001, "pos[0] 往返")
	t.eq(d["players"][1]["id"], 3, "id[1] 往返")

	var empty := Protocol.decode_snapshot(Protocol.encode_snapshot(7, []))
	t.eq(empty["players"].size(), 0, "空快照玩家数 = 0")
	t.eq(empty["tick"], 7, "空快照 tick 往返")

	return t.report("ProtocolSnapshot")
