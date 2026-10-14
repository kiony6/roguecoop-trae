extends RefCounted
## 快照编解码测试（M2）：玩家/敌人/掉落三段、长度公式、大 id（u32）往返。

const Harness := preload("res://tools/tests/harness.gd")
const Protocol := preload("res://net/protocol.gd")


func run() -> int:
	var t := Harness.new()
	var big_id := 1420896317

	var players: Array = [
		{"id": 1, "pos": Vector2(10.5, -20.25), "hp": 100},
		{"id": big_id, "pos": Vector2(0.0, 0.0), "hp": 42},
	]
	var enemies: Array = [
		{"id": 7, "pos": Vector2(-3.5, 8.0), "hp": 30},
	]
	var loot: Array = [
		{"id": 9, "pos": Vector2(100.0, 50.0), "kind": 2},
	]

	var bytes := Protocol.encode_snapshot(42, players, enemies, loot)
	t.eq(bytes.size(), Protocol.snapshot_size(2, 1, 1), "长度 = snapshot_size(2,1,1)")
	t.eq(bytes.size(), 59, "长度硬校验 = 7 + 2*13 + 13 + 13 = 59")

	var d := Protocol.decode_snapshot(bytes)
	t.eq(d["tick"], 42, "tick 往返")
	t.eq(d["players"].size(), 2, "玩家数往返")
	t.eq(d["players"][0]["id"], 1, "玩家 id[0] 往返")
	t.eq(d["players"][1]["id"], big_id, "大 id 往返（u32 不截断）")
	t.eq(d["players"][1]["hp"], 42, "玩家 hp 往返")
	t.check((d["players"][0]["pos"] - Vector2(10.5, -20.25)).length() < 0.001, "玩家 pos 往返")

	t.eq(d["enemies"].size(), 1, "敌人数往返")
	t.eq(d["enemies"][0]["id"], 7, "敌人 id 往返")
	t.eq(d["enemies"][0]["hp"], 30, "敌人 hp 往返")
	t.check((d["enemies"][0]["pos"] - Vector2(-3.5, 8.0)).length() < 0.001, "敌人 pos 往返")

	t.eq(d["loot"].size(), 1, "掉落数往返")
	t.eq(d["loot"][0]["id"], 9, "掉落 id 往返")
	t.eq(d["loot"][0]["kind"], 2, "掉落 kind 往返")
	t.check((d["loot"][0]["pos"] - Vector2(100.0, 50.0)).length() < 0.001, "掉落 pos 往返")

	var empty := Protocol.decode_snapshot(Protocol.encode_snapshot(7, []))
	t.eq(empty["tick"], 7, "空快照 tick 往返")
	t.eq(empty["players"].size(), 0, "空快照玩家数 = 0")
	t.eq(empty["enemies"].size(), 0, "空快照敌人数 = 0")
	t.eq(empty["loot"].size(), 0, "空快照掉落数 = 0")

	return t.report("ProtocolSnapshot")
