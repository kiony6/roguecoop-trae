extends RefCounted
## 快照编解码测试（M3）：队伍元数据 + 玩家/敌人/掉落三段 + 大 id（u32）往返。

const Harness := preload("res://tools/tests/harness.gd")
const Protocol := preload("res://net/protocol.gd")


func run() -> int:
	var t := Harness.new()
	var big_id := 1420896317

	var meta: Dictionary = {"level": 3, "xp": 7, "kills": 42}
	var players: Array = [
		{"id": 1, "pos": Vector2(10.5, -20.25), "hp": 100, "status": 0, "revive01": 0},
		{"id": big_id, "pos": Vector2(0.0, 0.0), "hp": 42, "status": 1, "revive01": 255},
	]
	var enemies: Array = [
		{"id": 7, "pos": Vector2(-3.5, 8.0), "hp": 200, "kind": 1},
	]
	var loot: Array = [
		{"id": 9, "pos": Vector2(100.0, 50.0), "kind": 1},
	]

	var bytes := Protocol.encode_snapshot(42, meta, players, enemies, loot)
	t.eq(bytes.size(), Protocol.snapshot_size(2, 1, 1), "长度 = snapshot_size(2,1,1)")
	t.eq(bytes.size(), 69, "长度硬校验 = 12 + 2*15 + 14 + 13 = 69")

	var d := Protocol.decode_snapshot(bytes)
	t.eq(d["tick"], 42, "tick 往返")
	t.eq(d["meta"]["level"], 3, "level 往返")
	t.eq(d["meta"]["xp"], 7, "xp 往返")
	t.eq(d["meta"]["kills"], 42, "kills 往返")

	t.eq(d["players"].size(), 2, "玩家数往返")
	t.eq(d["players"][0]["id"], 1, "玩家 id[0] 往返")
	t.eq(d["players"][1]["id"], big_id, "大 id 往返（u32 不截断）")
	t.eq(d["players"][1]["hp"], 42, "玩家 hp 往返")
	t.eq(d["players"][1]["status"], 1, "玩家 status 往返")
	t.eq(d["players"][1]["revive01"], 255, "玩家 revive01 往返")
	t.check((d["players"][0]["pos"] - Vector2(10.5, -20.25)).length() < 0.001, "玩家 pos 往返")

	t.eq(d["enemies"].size(), 1, "敌人数往返")
	t.eq(d["enemies"][0]["id"], 7, "敌人 id 往返")
	t.eq(d["enemies"][0]["hp"], 200, "敌人 hp 往返")
	t.eq(d["enemies"][0]["kind"], 1, "敌人 kind 往返")
	t.check((d["enemies"][0]["pos"] - Vector2(-3.5, 8.0)).length() < 0.001, "敌人 pos 往返")

	t.eq(d["loot"].size(), 1, "掉落数往返")
	t.eq(d["loot"][0]["id"], 9, "掉落 id 往返")
	t.eq(d["loot"][0]["kind"], 1, "掉落 kind 往返")
	t.check((d["loot"][0]["pos"] - Vector2(100.0, 50.0)).length() < 0.001, "掉落 pos 往返")

	var empty := Protocol.decode_snapshot(Protocol.encode_snapshot(7, {}, []))
	t.eq(empty["tick"], 7, "空快照 tick 往返")
	t.eq(empty["meta"]["level"], 1, "空快照 level 默认 1")
	t.eq(empty["players"].size(), 0, "空快照玩家数 = 0")
	t.eq(empty["enemies"].size(), 0, "空快照敌人数 = 0")
	t.eq(empty["loot"].size(), 0, "空快照掉落数 = 0")

	return t.report("ProtocolSnapshot")
