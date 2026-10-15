extends RefCounted
## 快照编解码测试（M4）：元数据 + 玩家(含武器)/敌人(hp01)/掉落/弹丸四段 + 房间编解码 + u32 大 id 往返。

const Harness := preload("res://tools/tests/harness.gd")
const Protocol := preload("res://net/protocol.gd")


func run() -> int:
	var t := Harness.new()
	var big_id := 1420896317

	var meta: Dictionary = {"level": 3, "xp": 7, "kills": 42}
	var players: Array = [
		{"id": 1, "pos": Vector2(10.5, -20.25), "hp": 100, "status": 0, "revive01": 0, "weapon": 0},
		{
			"id": big_id,
			"pos": Vector2(0.0, 0.0),
			"hp": 42,
			"status": 1,
			"revive01": 255,
			"weapon": 2
		},
	]
	var enemies: Array = [
		{"id": 7, "pos": Vector2(-3.5, 8.0), "hp01": 255, "kind": 1},
	]
	var loot: Array = [
		{"id": 9, "pos": Vector2(100.0, 50.0), "kind": 1},
	]
	var projectiles: Array = [
		{"id": 11, "pos": Vector2(5.0, 6.0), "dir": Vector2.RIGHT, "kind": 2},
	]

	var bytes := Protocol.encode_snapshot(42, meta, players, enemies, loot, projectiles)
	t.eq(bytes.size(), Protocol.snapshot_size(2, 1, 1, 1), "长度 = snapshot_size(2,1,1,1)")
	t.eq(bytes.size(), 87, "长度硬校验 = 13 + 2*16 + 14 + 13 + 15 = 87")

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
	t.eq(d["players"][1]["weapon"], 2, "玩家 weapon 往返")
	t.check((d["players"][0]["pos"] - Vector2(10.5, -20.25)).length() < 0.001, "玩家 pos 往返")

	t.eq(d["enemies"].size(), 1, "敌人数往返")
	t.eq(d["enemies"][0]["id"], 7, "敌人 id 往返")
	t.eq(d["enemies"][0]["hp01"], 255, "敌人 hp01 往返（u8 无溢出）")
	t.eq(d["enemies"][0]["kind"], 1, "敌人 kind 往返")

	t.eq(d["loot"].size(), 1, "掉落数往返")
	t.eq(d["loot"][0]["id"], 9, "掉落 id 往返")
	t.eq(d["loot"][0]["kind"], 1, "掉落 kind 往返")

	t.eq(d["projectiles"].size(), 1, "弹丸数往返")
	t.eq(d["projectiles"][0]["id"], 11, "弹丸 id 往返")
	t.eq(d["projectiles"][0]["kind"], 2, "弹丸 kind 往返")
	t.check((d["projectiles"][0]["dir"] - Vector2.RIGHT).length() < 0.02, "弹丸 dir 往返（i8 量化）")
	t.check((d["projectiles"][0]["pos"] - Vector2(5.0, 6.0)).length() < 0.001, "弹丸 pos 往返")

	var empty := Protocol.decode_snapshot(Protocol.encode_snapshot(7, {}, []))
	t.eq(empty["tick"], 7, "空快照 tick 往返")
	t.eq(empty["meta"]["level"], 1, "空快照 level 默认 1")
	t.eq(empty["players"].size(), 0, "空快照玩家数 = 0")
	t.eq(empty["enemies"].size(), 0, "空快照敌人数 = 0")
	t.eq(empty["loot"].size(), 0, "空快照掉落数 = 0")
	t.eq(empty["projectiles"].size(), 0, "空快照弹丸数 = 0")
	t.eq(Protocol.encode_snapshot(7, {}, []).size(), 13, "空快照长度 = HEADER_BYTES")

	var rb := Protocol.encode_room([Rect2(10.0, -20.0, 30.0, 40.0)])
	t.eq(rb.size(), 17, "单墙编码 1 + 16 = 17 字节")
	var rw := Protocol.decode_room(rb)
	t.eq(rw.size(), 1, "墙体数往返")
	t.check(rw[0].position.distance_to(Vector2(10.0, -20.0)) < 0.001, "墙体位置往返")
	t.check(rw[0].size.distance_to(Vector2(30.0, 40.0)) < 0.001, "墙体尺寸往返")
	t.eq(Protocol.decode_room(Protocol.encode_room([])).size(), 0, "空房间往返")

	return t.report("ProtocolSnapshot")
