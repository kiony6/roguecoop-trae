extends RefCounted
## 关卡/难度接线到主机权威的单测（子项目 6 任务 3）：
## 默认档逐值等价（零回归）、难度倍率生效、起始波次偏移、关卡元素偏向、
## 难度不追改存量敌人、配置跨 reset 保留、非法 id 被钳制。

const Harness := preload("res://tools/tests/harness.gd")
const NetHostLogic := preload("res://net/net_host.gd")
const Combat := preload("res://sim/combat.gd")
const Waves := preload("res://sim/waves.gd")
const Levels := preload("res://sim/levels.gd")
const Skills := preload("res://sim/skills.gd")

const EPS := 0.0001


func run() -> int:
	var t := Harness.new()

	# (1) 默认配置 = 零回归（关卡 0 + 难度 1 与改动前逐值一致）
	var base := NetHostLogic.new()
	base.reset(false)
	t.eq(base.level_id, Levels.DEFAULT_LEVEL, "默认关卡 0")
	t.eq(base.difficulty_id, Levels.DEFAULT_DIFFICULTY, "默认难度 1（普通）")
	t.eq(base.wave, 1, "默认开局第 1 波")
	t.check(absf(base.spawn_interval - Waves.spawn_interval(1)) < EPS, "默认刷怪间隔 = Waves 原值")
	var nid := base.spawn_enemy(Vector2.ZERO)
	t.eq(
		int(base.enemies[nid]["max_hp"]),
		Combat.enemy_max_hp(Combat.ENEMY_KIND_NORMAL),
		"默认血量 = Combat 原值"
	)
	t.eq(
		int(base.enemies[nid]["max_hp"]), Waves.enemy_hp(Combat.ENEMY_KIND_NORMAL, 1), "= Waves 原值"
	)
	t.eq(int(base.enemies[nid]["element"]), Skills.ELEM_PHYS, "默认无元素偏向")
	t.eq(base.enemies[nid]["element_until"], 0.0, "默认无元素到期时间")

	# (2) 难度生效：起始波次偏移 + 刷怪间隔 / 血量按难度走高
	var hard := NetHostLogic.new()
	hard.reset(true)
	hard.set_run_config(0, 4)
	t.eq(hard.wave, 4, "地狱档开局第 4 波（偏移 3）")
	t.check(absf(hard.spawn_interval - Levels.spawn_interval(0, 4, 4)) < EPS, "间隔 = Levels 有效值")
	t.check(hard.spawn_interval < base.spawn_interval, "地狱档刷怪比默认档更密")
	var hid := hard.spawn_enemy(Vector2.ZERO)
	t.eq(
		int(hard.enemies[hid]["max_hp"]),
		Levels.enemy_hp(Combat.ENEMY_KIND_NORMAL, 0, 4, 4),
		"地狱档血量 = Levels 有效值"
	)
	t.check(int(hard.enemies[hid]["max_hp"]) > int(base.enemies[nid]["max_hp"]), "地狱档血量更高")

	# (3) 波次随时间按偏移推进（需有人接入，否则空场冻结）
	hard.add_player(2)
	hard.spawn_interval = 9999.0
	hard.physics_step(25.0)
	t.eq(hard.wave, 5, "地狱档 25s 进入第 5 波")

	# (4) Boss 频率随难度：普通档击杀 15 才出 Boss，地狱档 6 就出
	var default_boss := NetHostLogic.new()
	default_boss.reset(true)
	default_boss.add_player(2)
	default_boss.set_run_config(0, 1)
	default_boss.kills = Combat.BOSS_EVERY_KILLS - 1
	default_boss.physics_step(0.016)
	t.eq(default_boss.boss_id, 0, "普通档未到 15 杀不出 Boss")
	default_boss.kills = Combat.BOSS_EVERY_KILLS
	default_boss.physics_step(0.016)
	t.check(default_boss.boss_id != 0, "普通档到 15 杀出 Boss")

	var hell_boss := NetHostLogic.new()
	hell_boss.reset(true)
	hell_boss.add_player(2)
	hell_boss.set_run_config(0, 4)
	hell_boss.kills = Levels.boss_every_kills(4)
	hell_boss.physics_step(0.016)
	t.check(hell_boss.boss_id != 0, "地狱档 6 杀就出 Boss")
	t.eq(Levels.boss_every_kills(4), 6, "地狱档 Boss 频率 = 6")

	# (5) 关卡元素偏向：刷怪自带元素，默认关卡不带
	var fire := NetHostLogic.new()
	fire.reset(true)
	fire.set_run_config(1, 1)
	var fid := fire.spawn_enemy(Vector2.ZERO)
	t.eq(int(fire.enemies[fid]["element"]), Skills.ELEM_FIRE, "区域 2 刷怪自带火元素")
	t.check(fire.enemies[fid]["element_until"] > 0.0, "区域 2 元素有到期时间")
	t.eq(fire.enemies[fid]["element_until"], Skills.ELEMENT_SECONDS, "到期时间 = 元素 TTL")
	var elec := NetHostLogic.new()
	elec.reset(true)
	elec.set_run_config(2, 1)
	t.eq(
		int(elec.enemies[elec.spawn_enemy(Vector2.ZERO)]["element"]),
		Skills.ELEM_ELEC,
		"区域 3 刷怪自带电元素"
	)
	var plain := NetHostLogic.new()
	plain.reset(true)
	plain.set_run_config(0, 1)
	t.eq(
		int(plain.enemies[plain.spawn_enemy(Vector2.ZERO)]["element"]),
		Skills.ELEM_PHYS,
		"区域 1 刷怪不带元素"
	)

	# (6) 难度不追改场上存量敌人（避免中途改难度造成血条跳变）
	var mixed := NetHostLogic.new()
	mixed.reset(true)
	mixed.set_run_config(0, 4)
	var old_id := mixed.spawn_enemy(Vector2.ZERO)
	var old_hp := int(mixed.enemies[old_id]["max_hp"])
	mixed.set_run_config(0, 1)
	t.eq(int(mixed.enemies[old_id]["max_hp"]), old_hp, "存量敌人血量不被追改")
	var new_id := mixed.spawn_enemy(Vector2.ZERO)
	t.check(int(mixed.enemies[new_id]["max_hp"]) < old_hp, "改回普通档后新怪血量回落")

	# (7) 配置跨 reset 保留（专服空场归零后仍用同一关卡/难度）
	var kept := NetHostLogic.new()
	kept.reset(true)
	kept.set_run_config(2, 3)
	kept.reset(true)
	t.eq(kept.level_id, 2, "reset 后关卡保留")
	t.eq(kept.difficulty_id, 3, "reset 后难度保留")
	t.eq(kept.wave, 3, "reset 后波次按偏移回到第 3 波")
	t.eq(kept.spawn_interval, Levels.spawn_interval(2, 3, 3), "reset 后间隔按新配置重算")

	# (8) 非法 id 钳制，不崩溃
	var clamp_host := NetHostLogic.new()
	clamp_host.reset(true)
	clamp_host.set_run_config(99, 99)
	t.eq(clamp_host.level_id, Levels.level_count() - 1, "越界关卡钳到末关")
	t.eq(clamp_host.difficulty_id, Levels.difficulty_count() - 1, "越界难度钳到最高档")
	clamp_host.set_run_config(-5, -5)
	t.eq(clamp_host.level_id, 0, "负关卡钳到 0")
	t.eq(clamp_host.difficulty_id, 0, "负难度钳到 0")

	return t.report("RunConfig")
