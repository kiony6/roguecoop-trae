extends RefCounted
## 关卡与难度纯逻辑（子项目 6）：3 个「区域」+ 5 档难度。
## 只在 Waves 的基准倍率上做乘算覆盖，Waves / Combat 一字不改。
## 「关卡 0 + 难度 1（普通）」与原值逐位等价 → 既有单测与三条冒烟零回归。
## 地图几何不动：Rooms.generate 仍恒返回空数组，关卡差异只在配色与曲线/元素参数上。

const Waves := preload("res://sim/waves.gd")
const Combat := preload("res://sim/combat.gd")
const Skills := preload("res://sim/skills.gd")

const DEFAULT_LEVEL := 0
const DEFAULT_DIFFICULTY := 1  # 普通：所有倍率为原始值，保证零回归

## 3 个区域。element 为刷怪时的元素偏向（ELEM_PHYS 表示不带元素）。
const LEVELS: Array = [
	{
		"id": 0,
		"name": "数据荒原",
		"bg": Color("2a3550"),
		"border": Color("5566aa"),
		"element": Skills.ELEM_PHYS,
		"hp_mul": 1.0,
		"speed_mul": 1.0,
		"spawn_interval_mul": 1.0,
		"max_enemies_mul": 1.0,
		"clear_wave": 8
	},
	{
		"id": 1,
		"name": "熔核回廊",
		"bg": Color("3a2430"),
		"border": Color("b23b3b"),
		"element": Skills.ELEM_FIRE,
		"hp_mul": 1.1,
		"speed_mul": 1.03,
		"spawn_interval_mul": 0.96,
		"max_enemies_mul": 1.05,
		"clear_wave": 12
	},
	{
		"id": 2,
		"name": "超频深网",
		"bg": Color("1f2c44"),
		"border": Color("4aa3ff"),
		"element": Skills.ELEM_ELEC,
		"hp_mul": 1.22,
		"speed_mul": 1.06,
		"spawn_interval_mul": 0.90,
		"max_enemies_mul": 1.10,
		"clear_wave": 16
	},
]

## 5 档难度。第 1 档（普通）的三个倍率全为 1、boss_every_kills = Combat 原值、wave_offset = 0。
const DIFFICULTIES: Array = [
	{
		"id": 0,
		"name": "简单",
		"hp_mul": 0.75,
		"speed_mul": 0.90,
		"spawn_interval_mul": 1.20,
		"max_enemies_mul": 0.85,
		"boss_every_kills": 20,
		"wave_offset": 0
	},
	{
		"id": 1,
		"name": "普通",
		"hp_mul": 1.0,
		"speed_mul": 1.0,
		"spawn_interval_mul": 1.0,
		"max_enemies_mul": 1.0,
		"boss_every_kills": Combat.BOSS_EVERY_KILLS,
		"wave_offset": 0
	},
	{
		"id": 2,
		"name": "困难",
		"hp_mul": 1.30,
		"speed_mul": 1.06,
		"spawn_interval_mul": 0.88,
		"max_enemies_mul": 1.20,
		"boss_every_kills": 12,
		"wave_offset": 1
	},
	{
		"id": 3,
		"name": "噩梦",
		"hp_mul": 1.70,
		"speed_mul": 1.13,
		"spawn_interval_mul": 0.78,
		"max_enemies_mul": 1.40,
		"boss_every_kills": 9,
		"wave_offset": 2
	},
	{
		"id": 4,
		"name": "地狱",
		"hp_mul": 2.20,
		"speed_mul": 1.20,
		"spawn_interval_mul": 0.68,
		"max_enemies_mul": 1.60,
		"boss_every_kills": 6,
		"wave_offset": 3
	},
]


static func level_count() -> int:
	return LEVELS.size()


static func difficulty_count() -> int:
	return DIFFICULTIES.size()


static func is_valid_level(level_id: int) -> bool:
	return level_id >= 0 and level_id < LEVELS.size()


static func is_valid_difficulty(difficulty_id: int) -> bool:
	return difficulty_id >= 0 and difficulty_id < DIFFICULTIES.size()


static func level_by_id(level_id: int) -> Dictionary:
	return LEVELS[clampi(level_id, 0, LEVELS.size() - 1)]


static func difficulty_by_id(difficulty_id: int) -> Dictionary:
	return DIFFICULTIES[clampi(difficulty_id, 0, DIFFICULTIES.size() - 1)]


static func name_of_level(level_id: int) -> String:
	return String(level_by_id(level_id)["name"])


static func name_of_difficulty(difficulty_id: int) -> String:
	return String(difficulty_by_id(difficulty_id)["name"])


static func clear_wave(level_id: int) -> int:
	return int(level_by_id(level_id)["clear_wave"])


static func next_level(level_id: int) -> int:
	var n := level_id + 1
	return n if is_valid_level(n) else -1


static func element_bias(level_id: int) -> int:
	return int(level_by_id(level_id)["element"])


## 波次编号只受难度「起始波次偏移」影响；关卡不额外抬波次（首参保留以统一曲线 API 签名）。
static func wave_of(_level_id: int, difficulty_id: int, elapsed: float) -> int:
	return Waves.wave_index(elapsed) + int(difficulty_by_id(difficulty_id)["wave_offset"])


static func spawn_interval(level_id: int, difficulty_id: int, wave: int) -> float:
	var mul := _level_mul(level_id, "spawn_interval_mul")
	mul *= float(difficulty_by_id(difficulty_id)["spawn_interval_mul"])
	return maxf(Waves.SPAWN_INTERVAL_MIN, Waves.spawn_interval(wave) * mul)


static func max_enemies(level_id: int, difficulty_id: int, wave: int) -> int:
	var mul := _level_mul(level_id, "max_enemies_mul")
	mul *= float(difficulty_by_id(difficulty_id)["max_enemies_mul"])
	return mini(Waves.MAX_ENEMIES_CAP, roundi(float(Waves.max_enemies(wave)) * mul))


static func hp_mul(level_id: int, difficulty_id: int, wave: int) -> float:
	var mul := _level_mul(level_id, "hp_mul") * float(difficulty_by_id(difficulty_id)["hp_mul"])
	return Waves.hp_mul(wave) * mul


static func speed_mul(level_id: int, difficulty_id: int, wave: int) -> float:
	var mul := (
		_level_mul(level_id, "speed_mul") * float(difficulty_by_id(difficulty_id)["speed_mul"])
	)
	return minf(Waves.SPEED_MUL_CAP, Waves.speed_mul(wave) * mul)


static func enemy_hp(kind: int, level_id: int, difficulty_id: int, wave: int) -> int:
	return roundi(float(Combat.enemy_max_hp(kind)) * hp_mul(level_id, difficulty_id, wave))


static func enemy_speed(kind: int, level_id: int, difficulty_id: int, wave: int) -> float:
	return Combat.enemy_speed(kind) * speed_mul(level_id, difficulty_id, wave)


static func boss_every_kills(difficulty_id: int) -> int:
	return int(difficulty_by_id(difficulty_id)["boss_every_kills"])


static func _level_mul(level_id: int, key: String) -> float:
	return float(level_by_id(level_id)[key])
