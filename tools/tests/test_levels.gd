extends RefCounted
## 关卡/难度表与有效曲线单测（子项目 6 任务 1）：
## 表尺寸、默认档与 Waves/Combat 逐值等价（零回归）、难度单调性、起始波次偏移、
## 关卡单调性与解锁链、元素偏向、协议常量不变。

const Harness := preload("res://tools/tests/harness.gd")
const Levels := preload("res://sim/levels.gd")
const Waves := preload("res://sim/waves.gd")
const Combat := preload("res://sim/combat.gd")
const Skills := preload("res://sim/skills.gd")
const Protocol := preload("res://net/protocol.gd")

const EPS := 0.0001


func run() -> int:
	var t := Harness.new()

	# (1) 表尺寸与默认值
	t.eq(Levels.level_count(), 3, "3 个区域")
	t.eq(Levels.difficulty_count(), 5, "5 档难度")
	t.eq(Levels.DEFAULT_LEVEL, 0, "默认关卡 = 0")
	t.eq(Levels.DEFAULT_DIFFICULTY, 1, "默认难度 = 1（普通）")
	t.eq(Levels.name_of_difficulty(Levels.DEFAULT_DIFFICULTY), "普通", "默认难度名为普通")
	t.check(Levels.is_valid_level(2) and not Levels.is_valid_level(3), "关卡 id 合法性")
	t.check(Levels.is_valid_difficulty(4) and not Levels.is_valid_difficulty(5), "难度 id 合法性")

	# (2) 默认档逐值等价（零回归）：关卡 0 + 难度 1 必须等于 Waves / Combat 原值
	t.eq(Levels.wave_of(0, 1, 25.0), Waves.wave_index(25.0), "默认档 wave_of 等价")
	t.check(
		_close(Levels.spawn_interval(0, 1, 3), Waves.spawn_interval(3)), "默认档 spawn_interval 等价"
	)
	t.eq(Levels.max_enemies(0, 1, 3), Waves.max_enemies(3), "默认档 max_enemies 等价")
	t.eq(Levels.max_enemies(0, 1, 999), Waves.max_enemies(999), "默认档 max_enemies 封顶等价")
	t.check(_close(Levels.hp_mul(0, 1, 3), Waves.hp_mul(3)), "默认档 hp_mul 等价")
	t.check(_close(Levels.speed_mul(0, 1, 3), Waves.speed_mul(3)), "默认档 speed_mul 等价")
	t.eq(
		Levels.enemy_hp(Combat.ENEMY_KIND_NORMAL, 0, 1, 5),
		Waves.enemy_hp(Combat.ENEMY_KIND_NORMAL, 5),
		"默认档 enemy_hp 等价"
	)
	t.check(
		_close(
			Levels.enemy_speed(Combat.ENEMY_KIND_NORMAL, 0, 1, 5),
			Waves.enemy_speed(Combat.ENEMY_KIND_NORMAL, 5)
		),
		"默认档 enemy_speed 等价"
	)
	t.eq(Levels.boss_every_kills(1), Combat.BOSS_EVERY_KILLS, "默认档 Boss 频率 = Combat 原值")
	t.eq(Levels.element_bias(0), Skills.ELEM_PHYS, "默认关卡无元素偏向")

	# (3) 难度单调性：血/上限随难度递增，刷怪间隔随难度递减
	for d in range(1, Levels.difficulty_count()):
		t.check(Levels.hp_mul(0, d, 1) > Levels.hp_mul(0, d - 1, 1), "难度 %d 血量倍率更高" % d)
		t.check(
			Levels.spawn_interval(0, d, 1) < Levels.spawn_interval(0, d - 1, 1), "难度 %d 刷怪更快" % d
		)
		t.check(Levels.max_enemies(0, d, 5) >= Levels.max_enemies(0, d - 1, 5), "难度 %d 同屏上限不降" % d)
		t.check(Levels.boss_every_kills(d) < Levels.boss_every_kills(d - 1), "难度 %d Boss 更频繁" % d)
	t.check(Levels.max_enemies(0, 4, 5) > Levels.max_enemies(0, 0, 5), "简单档上限低于地狱档")
	t.check(Levels.spawn_interval(0, 4, 1) >= Waves.SPAWN_INTERVAL_MIN, "刷怪间隔仍有下限")

	# (4) 起始波次偏移
	t.eq(Levels.wave_of(0, 1, 0.0), 1, "普通档开局第 1 波")
	t.eq(Levels.wave_of(0, 4, 0.0), 4, "地狱档开局第 4 波（偏移 3）")
	t.eq(Levels.wave_of(0, 4, 25.0), 5, "地狱档 25s 进入第 5 波")

	# (5) 关卡曲线覆盖与通关波次
	t.eq(Levels.clear_wave(0), 8, "区域 1 通关波次 8")
	t.check(
		Levels.clear_wave(0) < Levels.clear_wave(1) and Levels.clear_wave(1) < Levels.clear_wave(2),
		"通关波次逐关递增"
	)
	t.eq(Levels.next_level(0), 1, "区域 1 解锁区域 2")
	t.eq(Levels.next_level(1), 2, "区域 2 解锁区域 3")
	t.eq(Levels.next_level(2), -1, "末关无后继")
	t.check(Levels.hp_mul(2, 1, 1) > Levels.hp_mul(0, 1, 1), "关卡 2 血量基准更高")
	t.check(Levels.speed_mul(1, 1, 1) > Levels.speed_mul(0, 1, 1), "关卡 1 速度基准更高")
	t.check(Levels.spawn_interval(2, 1, 1) < Levels.spawn_interval(0, 1, 1), "关卡 2 刷怪更密（曲线覆盖）")
	t.check(Levels.max_enemies(2, 1, 5) > Levels.max_enemies(0, 1, 5), "关卡 2 同屏上限更高（曲线覆盖）")

	# (6) 元素偏向
	t.eq(Levels.element_bias(1), Skills.ELEM_FIRE, "区域 2 火偏向")
	t.eq(Levels.element_bias(2), Skills.ELEM_ELEC, "区域 3 电偏向")

	# (7) 主题配色可直接用于绘制
	t.check(Levels.level_by_id(0)["bg"] is Color, "主题底色为 Color")
	t.check(Levels.level_by_id(2)["border"] is Color, "主题边框为 Color")

	# (8) 协议不变式：版本与 7 个二进制段常量一个字节不改
	t.eq(Protocol.PROTOCOL_VERSION, 4, "PROTOCOL_VERSION = 4")
	t.eq(Protocol.HEADER_BYTES, 14, "HEADER_BYTES = 14")
	t.eq(Protocol.PLAYER_BYTES, 16, "PLAYER_BYTES = 16")
	t.eq(Protocol.ENEMY_BYTES, 14, "ENEMY_BYTES = 14")
	t.eq(Protocol.LOOT_BYTES, 13, "LOOT_BYTES = 13")
	t.eq(Protocol.PROJ_BYTES, 15, "PROJ_BYTES = 15")
	t.eq(Protocol.ROOM_BYTES, 16, "ROOM_BYTES = 16")
	t.eq(Protocol.INPUT_BYTES, 5, "INPUT_BYTES = 5")

	return t.report("Levels")


func _close(a: float, b: float) -> bool:
	return absf(a - b) < EPS
