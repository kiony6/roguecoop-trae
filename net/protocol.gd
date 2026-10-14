extends RefCounted
## 网络协议常量与二进制编解码（M2）。
## 全部静态方法，无实例状态。
## 输入帧：5 字节。
## 快照：u32 tick | u8 pc | pc*13 | u8 ec | ec*13 | u8 lc | lc*13 = 7 + pc*13 + ec*13 + lc*13。

const PROTOCOL_VERSION := 1
const DEFAULT_PORT := 25600
const MAX_PLAYERS := 4  # 协议上限（M1/M2 实际按 2 人验收）
const INPUT_RATE := 30  # 客户端输入上报 Hz
const SNAPSHOT_RATE := 20  # 主机快照广播 Hz
const CH_CONTROL := 0  # 可靠通道
const CH_DATA := 1  # 不可靠有序通道

const INPUT_BYTES := 5
const PLAYER_BYTES := 13  # u32 id | f32 x | f32 y | u8 hp
const ENEMY_BYTES := 13  # u32 id | f32 x | f32 y | u8 hp
const LOOT_BYTES := 13  # u32 id | f32 x | f32 y | u8 kind

# ---------------- 输入帧 ----------------
# 布局: i8 move_x | i8 move_y | i8 aim_x | i8 aim_y | u8 buttons


static func encode_input(move: Vector2, aim: Vector2, buttons: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(INPUT_BYTES)
	b[0] = _quant8(move.x)
	b[1] = _quant8(move.y)
	b[2] = _quant8(aim.x)
	b[3] = _quant8(aim.y)
	b[4] = buttons & 0xFF
	return b


static func decode_input(b: PackedByteArray) -> Dictionary:
	assert(b.size() >= INPUT_BYTES, "input frame too short")
	return {
		"move": Vector2(_dequant8(b[0]), _dequant8(b[1])),
		"aim": Vector2(_dequant8(b[2]), _dequant8(b[3])),
		"buttons": b[4],
	}


# ---------------- 快照 ----------------
# 布局: u32 tick
#     | u8 pc | pc*(u32 id | f32 x | f32 y | u8 hp)
#     | u8 ec | ec*(u32 id | f32 x | f32 y | u8 hp)
#     | u8 lc | lc*(u32 id | f32 x | f32 y | u8 kind)
# 注意：Godot 4 的对端 unique_id 为随机大整数（可达 2^31），实体 id 一律 u32。


static func encode_snapshot(
	tick: int, players: Array, enemies: Array = [], loot: Array = []
) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(snapshot_size(players.size(), enemies.size(), loot.size()))
	b.encode_u32(0, tick)
	b[4] = players.size()
	var o := 5
	for p in players:
		b.encode_u32(o, int(p["id"]))
		b.encode_float(o + 4, float(p["pos"].x))
		b.encode_float(o + 8, float(p["pos"].y))
		b[o + 12] = int(p.get("hp", 100)) & 0xFF
		o += PLAYER_BYTES
	b[o] = enemies.size()
	o += 1
	for e in enemies:
		b.encode_u32(o, int(e["id"]))
		b.encode_float(o + 4, float(e["pos"].x))
		b.encode_float(o + 8, float(e["pos"].y))
		b[o + 12] = int(e.get("hp", 0)) & 0xFF
		o += ENEMY_BYTES
	b[o] = loot.size()
	o += 1
	for l in loot:
		b.encode_u32(o, int(l["id"]))
		b.encode_float(o + 4, float(l["pos"].x))
		b.encode_float(o + 8, float(l["pos"].y))
		b[o + 12] = int(l.get("kind", 0)) & 0xFF
		o += LOOT_BYTES
	return b


static func decode_snapshot(b: PackedByteArray) -> Dictionary:
	assert(b.size() >= 5, "snapshot too short")
	var players: Array = []
	var pc: int = b[4]
	var o := 5
	for _i in pc:
		if o + PLAYER_BYTES > b.size():
			break
		(
			players
			. append(
				{
					"id": b.decode_u32(o),
					"pos": Vector2(b.decode_float(o + 4), b.decode_float(o + 8)),
					"hp": b[o + 12],
				}
			)
		)
		o += PLAYER_BYTES
	var enemies: Array = []
	if o < b.size():
		var ec: int = b[o]
		o += 1
		for _i in ec:
			if o + ENEMY_BYTES > b.size():
				break
			(
				enemies
				. append(
					{
						"id": b.decode_u32(o),
						"pos": Vector2(b.decode_float(o + 4), b.decode_float(o + 8)),
						"hp": b[o + 12],
					}
				)
			)
			o += ENEMY_BYTES
	var loot: Array = []
	if o < b.size():
		var lc: int = b[o]
		o += 1
		for _i in lc:
			if o + LOOT_BYTES > b.size():
				break
			(
				loot
				. append(
					{
						"id": b.decode_u32(o),
						"pos": Vector2(b.decode_float(o + 4), b.decode_float(o + 8)),
						"kind": b[o + 12],
					}
				)
			)
			o += LOOT_BYTES
	return {"tick": b.decode_u32(0), "players": players, "enemies": enemies, "loot": loot}


static func snapshot_size(pc: int, ec: int = 0, lc: int = 0) -> int:
	return 7 + pc * PLAYER_BYTES + ec * ENEMY_BYTES + lc * LOOT_BYTES


# ---------------- 量化辅助 ----------------


static func _quant8(v: float) -> int:
	# [-1, 1] -> [-127, 127]，再取低 8 位（PackedByteArray 为无符号）
	return clampi(roundi(clampf(v, -1.0, 1.0) * 127.0), -127, 127) & 0xFF


static func _dequant8(raw: int) -> float:
	var v: int = raw
	if v > 127:
		v -= 256
	return float(v) / 127.0
