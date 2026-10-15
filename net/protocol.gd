extends RefCounted
## 网络协议常量与二进制编解码（M4）。
## 全部静态方法，无实例状态。
## 输入帧：5 字节。
## 快照头：u32 tick | u8 level | u16 xp | u16 kills | u8 pc | u8 ec | u8 lc | u8 prc = 13 字节
## 玩家段：u32 id | f32 x | f32 y | u8 hp | u8 status | u8 revive01 | u8 weapon = 16 字节
## 敌人段：u32 id | f32 x | f32 y | u8 hp01 | u8 kind = 14 字节
## 掉落段：u32 id | f32 x | f32 y | u8 kind = 13 字节
## 弹丸段：u32 id | f32 x | f32 y | i8 dirx | i8 diry | u8 kind = 15 字节
## 房间：u8 wc | wc*(f32 x | f32 y | f32 w | f32 h) = 1 + 16*wc 字节
## 注意：ec/lc/prc 三个计数字节在布局上位于各自段之前（ec 紧接玩家段之后）。

const PROTOCOL_VERSION := 1
const DEFAULT_PORT := 25600
const MAX_PLAYERS := 4  # 协议上限（实际按 2 人验收）
const INPUT_RATE := 30  # 客户端输入上报 Hz
const SNAPSHOT_RATE := 20  # 主机快照广播 Hz
const CH_CONTROL := 0  # 可靠通道
const CH_DATA := 1  # 不可靠有序通道

const INPUT_BYTES := 5
const HEADER_BYTES := 13
const PLAYER_BYTES := 16
const ENEMY_BYTES := 14
const LOOT_BYTES := 13
const PROJ_BYTES := 15
const ROOM_BYTES := 16

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
# 布局: u32 tick | u8 level | u16 xp | u16 kills | u8 pc
#     | pc*(u32 id | f32 x | f32 y | u8 hp | u8 status | u8 revive01 | u8 weapon)
#     | u8 ec | ec*(u32 id | f32 x | f32 y | u8 hp01 | u8 kind)
#     | u8 lc | lc*(u32 id | f32 x | f32 y | u8 kind)
#     | u8 prc | prc*(u32 id | f32 x | f32 y | i8 dx | i8 dy | u8 kind)
# 注意：Godot 4 的对端 unique_id 为随机大整数（可达 2^31），实体 id 一律 u32。


static func encode_snapshot(
	tick: int,
	meta: Dictionary,
	players: Array,
	enemies: Array = [],
	loot: Array = [],
	projectiles: Array = []
) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(snapshot_size(players.size(), enemies.size(), loot.size(), projectiles.size()))
	b.encode_u32(0, tick)
	b[4] = int(meta.get("level", 1)) & 0xFF
	b.encode_u16(5, int(meta.get("xp", 0)))
	b.encode_u16(7, int(meta.get("kills", 0)))
	b[9] = players.size()
	var o := 10
	for p in players:
		b.encode_u32(o, int(p["id"]))
		b.encode_float(o + 4, float(p["pos"].x))
		b.encode_float(o + 8, float(p["pos"].y))
		b[o + 12] = int(p.get("hp", 100)) & 0xFF
		b[o + 13] = int(p.get("status", 0)) & 0xFF
		b[o + 14] = int(p.get("revive01", 0)) & 0xFF
		b[o + 15] = int(p.get("weapon", 0)) & 0xFF
		o += PLAYER_BYTES
	b[o] = enemies.size()
	o += 1
	for e in enemies:
		b.encode_u32(o, int(e["id"]))
		b.encode_float(o + 4, float(e["pos"].x))
		b.encode_float(o + 8, float(e["pos"].y))
		b[o + 12] = int(e.get("hp01", 255)) & 0xFF
		b[o + 13] = int(e.get("kind", 0)) & 0xFF
		o += ENEMY_BYTES
	b[o] = loot.size()
	o += 1
	for l in loot:
		b.encode_u32(o, int(l["id"]))
		b.encode_float(o + 4, float(l["pos"].x))
		b.encode_float(o + 8, float(l["pos"].y))
		b[o + 12] = int(l.get("kind", 0)) & 0xFF
		o += LOOT_BYTES
	b[o] = projectiles.size()
	o += 1
	for pj in projectiles:
		var dir: Vector2 = pj.get("dir", Vector2.RIGHT)
		b.encode_u32(o, int(pj["id"]))
		b.encode_float(o + 4, float(pj["pos"].x))
		b.encode_float(o + 8, float(pj["pos"].y))
		b[o + 12] = _quant8(dir.x)
		b[o + 13] = _quant8(dir.y)
		b[o + 14] = int(pj.get("kind", 0)) & 0xFF
		o += PROJ_BYTES
	return b


static func decode_snapshot(b: PackedByteArray) -> Dictionary:
	assert(b.size() >= HEADER_BYTES, "snapshot too short")
	var meta := {
		"level": b[4],
		"xp": b.decode_u16(5),
		"kills": b.decode_u16(7),
	}
	var players: Array = []
	var pc: int = b[9]
	var o := 10
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
					"status": b[o + 13],
					"revive01": b[o + 14],
					"weapon": b[o + 15],
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
						"hp01": b[o + 12],
						"kind": b[o + 13],
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
	var projectiles: Array = []
	if o < b.size():
		var prc: int = b[o]
		o += 1
		for _i in prc:
			if o + PROJ_BYTES > b.size():
				break
			(
				projectiles
				. append(
					{
						"id": b.decode_u32(o),
						"pos": Vector2(b.decode_float(o + 4), b.decode_float(o + 8)),
						"dir": Vector2(_dequant8(b[o + 12]), _dequant8(b[o + 13])),
						"kind": b[o + 14],
					}
				)
			)
			o += PROJ_BYTES
	return {
		"tick": b.decode_u32(0),
		"meta": meta,
		"players": players,
		"enemies": enemies,
		"loot": loot,
		"projectiles": projectiles,
	}


static func snapshot_size(pc: int, ec: int = 0, lc: int = 0, prc: int = 0) -> int:
	return HEADER_BYTES + pc * PLAYER_BYTES + ec * ENEMY_BYTES + lc * LOOT_BYTES + prc * PROJ_BYTES


# ---------------- 房间 ----------------
# 布局: u8 wc | wc*(f32 x | f32 y | f32 w | f32 h)


static func encode_room(walls: Array) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(1 + walls.size() * ROOM_BYTES)
	b[0] = walls.size()
	var o := 1
	for w in walls:
		var r: Rect2 = w
		b.encode_float(o, r.position.x)
		b.encode_float(o + 4, r.position.y)
		b.encode_float(o + 8, r.size.x)
		b.encode_float(o + 12, r.size.y)
		o += ROOM_BYTES
	return b


static func decode_room(b: PackedByteArray) -> Array:
	var walls: Array = []
	if b.size() < 1:
		return walls
	var wc: int = b[0]
	var o := 1
	for _i in wc:
		if o + ROOM_BYTES > b.size():
			break
		walls.append(
			Rect2(
				b.decode_float(o),
				b.decode_float(o + 4),
				b.decode_float(o + 8),
				b.decode_float(o + 12)
			)
		)
		o += ROOM_BYTES
	return walls


# ---------------- 量化辅助 ----------------


static func _quant8(v: float) -> int:
	# [-1, 1] -> [-127, 127]，再取低 8 位（PackedByteArray 为无符号）
	return clampi(roundi(clampf(v, -1.0, 1.0) * 127.0), -127, 127) & 0xFF


static func _dequant8(raw: int) -> float:
	var v: int = raw
	if v > 127:
		v -= 256
	return float(v) / 127.0
