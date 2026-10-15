extends RefCounted
## 波次难度曲线测试（M4）：档位推进、刷新间隔/同屏上限/血量/速度倍率，第 1 波与 M3 一致。

const Harness := preload("res://tools/tests/harness.gd")
const Waves := preload("res://sim/waves.gd")
const Combat := preload("res://sim/combat.gd")


func run() -> int:
	var t := Harness.new()

	t.eq(Waves.wave_index(0.0), 1, "开局为第 1 波")
	t.eq(Waves.wave_index(24.9), 1, "24.9s 仍为第 1 波")
	t.eq(Waves.wave_index(25.0), 2, "25s 进入第 2 波")
	t.eq(Waves.wave_index(50.0), 3, "50s 进入第 3 波")

	var i1 := Waves.spawn_interval(1)
	var i3 := Waves.spawn_interval(3)
	t.check(absf(i1 - Combat.SPAWN_INTERVAL) < 0.0001, "第 1 波刷新间隔 = 基础值")
	t.check(i3 < i1, "波次越高刷新越快")
	t.check(Waves.spawn_interval(999) >= Waves.SPAWN_INTERVAL_MIN, "刷新间隔有下限")

	t.eq(Waves.max_enemies(1), Combat.MAX_ENEMIES, "第 1 波敌人上限 = 基础值")
	t.check(Waves.max_enemies(3) > Combat.MAX_ENEMIES, "波次越高敌人上限越大")
	t.check(Waves.max_enemies(999) <= Waves.MAX_ENEMIES_CAP, "敌人上限有上限")

	t.check(absf(Waves.hp_mul(1) - 1.0) < 0.0001, "第 1 波血量倍率 = 1")
	t.eq(Waves.enemy_hp(Combat.ENEMY_KIND_NORMAL, 1), Combat.ENEMY_MAX_HP, "第 1 波普通怪血量 = 基础")
	t.check(Waves.enemy_hp(Combat.ENEMY_KIND_NORMAL, 5) > Combat.ENEMY_MAX_HP, "高波次血量更高")

	t.check(absf(Waves.speed_mul(1) - 1.0) < 0.0001, "第 1 波速度倍率 = 1")
	t.check(absf(Waves.speed_mul(999) - Waves.SPEED_MUL_CAP) < 0.0001, "速度倍率封顶")
	var s1 := Waves.enemy_speed(Combat.ENEMY_KIND_NORMAL, 1)
	t.check(absf(s1 - Combat.ENEMY_SPEED) < 0.0001, "第 1 波速度 = 基础")

	return t.report("Waves")
