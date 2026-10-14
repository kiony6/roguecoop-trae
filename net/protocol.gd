extends RefCounted
## 网络协议常量与二进制编解码（M1）。全部静态方法，无实例状态。
## 输入帧：5 字节。快照：5 + N*10 字节。

const PROTOCOL_VERSION := 1
const DEFAULT_PORT := 25600
const MAX_PLAYERS := 4        # 协议上限（M1 实际按 2 人验收）
const INPUT_RATE := 30        # 客户端输入上报 Hz
const SNAPSHOT_RATE := 20     # 主机快照广播 Hz
const CH_CONTROL := 0         # 可靠通道
const CH_DATA := 1            # 不可靠有序通道

const INPUT_BYTES := 5
const PLAYER_BYTES := 10


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
# 布局: u32 tick | u8 count | count * (u16 id | f32 x | f32 y)

static func encode_snapshot(tick: int, players: Array) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(snapshot_size(players.size()))
	b.encode_u32(0, tick)
	b[4] = players.size()
	var o := 5
	for p in players:
		b.encode_u16(o, int(p["id"]))
		b.encode_float(o + 2, float(p["pos"].x))
		b.encode_float(o + 6, float(p["pos"].y))
		o += PLAYER_BYTES
	return b


static func decode_snapshot(b: PackedByteArray) -> Dictionary:
	assert(b.size() >= 5, "snapshot too short")
	var out: Array = []
	var count: int = b[4]
	var o := 5
	for _i in count:
		if o + PLAYER_BYTES > b.size():
			break
		out.append({
			"id": b.decode_u16(o),
			"pos": Vector2(b.decode_float(o + 2), b.decode_float(o + 6)),
		})
		o += PLAYER_BYTES
	return {"tick": b.decode_u32(0), "players": out}


static func snapshot_size(count: int) -> int:
	return 5 + count * PLAYER_BYTES


# ---------------- 量化辅助 ----------------

static func _quant8(v: float) -> int:
	# [-1, 1] -> [-127, 127]，再取低 8 位（PackedByteArray 为无符号）
	return clampi(roundi(clampf(v, -1.0, 1.0) * 127.0), -127, 127) & 0xFF


static func _dequant8(raw: int) -> float:
	var v: int = raw
	if v > 127:
		v -= 256
	return float(v) / 127.0
