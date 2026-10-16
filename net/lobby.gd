extends RefCounted
## 联机大厅/房间的纯逻辑（无 IO、无 Net、可被无头单测直接断言）。
## 只提供组队码生成/校验、房间状态机取值与错误码文案；房间存储与网络收发由上层负责。

enum STATE {
	WAITING = 0,
	RUNNING = 1,
	FINISHED = 2,
}

enum ERR {
	OK = 0,
	ROOM_NOT_FOUND = 1,
	ROOM_FULL = 2,
	ALREADY_IN_ROOM = 3,
	NOT_IN_ROOM = 4,
	NOT_HOST = 5,
	ROOM_LIMIT = 6,
	BAD_STATE = 7,
	BAD_CODE = 8,
	NOT_LOGGED_IN = 9,
	UNSUPPORTED = 10,
	INTERNAL = 11,
}

const Protocol := preload("res://net/protocol.gd")
const Levels := preload("res://sim/levels.gd")
const MAX_ROOMS := 4  # 单进程房间上限
const ROOM_CODE_MIN := 100000
const ROOM_CODE_MAX := 999999  # 6 位数字码，首位非 0
const EMPTY_ROOM_TTL_S := 120.0  # 房内无成员持续这么久即销毁
const ROOMS_CAPACITY := MAX_ROOMS * Protocol.MAX_PLAYERS  # 传给 create_server 的客户端上限（=16）
const DEFAULT_LEVEL := Levels.DEFAULT_LEVEL  # 新房间默认关卡（区域 1）
const DEFAULT_DIFFICULTY := Levels.DEFAULT_DIFFICULTY  # 新房间默认难度（普通）
const _CODE_RANDOM_TRIES := 64


static func is_valid_code(s: String) -> bool:
	if s.length() != 6:
		return false
	if s[0] == "0":
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 0x30 or c > 0x39:
			return false
	return true


static func make_code(rng: RandomNumberGenerator, taken: Dictionary) -> String:
	for _i in _CODE_RANDOM_TRIES:
		var picked := rng.randi_range(ROOM_CODE_MIN, ROOM_CODE_MAX)
		var text := str(picked)
		if not taken.has(text):
			return text
	for code in range(ROOM_CODE_MIN, ROOM_CODE_MAX + 1):
		var fallback := str(code)
		if not taken.has(fallback):
			return fallback
	return ""


static func reason_text(err: int) -> String:
	match err:
		ERR.OK:
			return "成功"
		ERR.ROOM_NOT_FOUND:
			return "组队码不存在或房间已关闭"
		ERR.ROOM_FULL:
			return "房间人数已满"
		ERR.ALREADY_IN_ROOM:
			return "你已在某个房间内"
		ERR.NOT_IN_ROOM:
			return "你不在任何房间内"
		ERR.NOT_HOST:
			return "只有房主可以开始游戏"
		ERR.ROOM_LIMIT:
			return "大厅房间数已达上限，请稍后再试"
		ERR.BAD_STATE:
			return "当前房间状态不允许该操作"
		ERR.BAD_CODE:
			return "组队码需为 6 位数字"
		ERR.NOT_LOGGED_IN:
			return "请先登录联机大厅"
		ERR.UNSUPPORTED:
			return "当前对端不支持大厅房间功能"
		ERR.INTERNAL:
			return "服务端内部错误"
	return "未知错误"
