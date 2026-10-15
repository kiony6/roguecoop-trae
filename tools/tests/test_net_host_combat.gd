extends RefCounted
## 主机权威逻辑测试（纯逻辑，无传输）。
## 覆盖：开火击杀→掉落→拾取、接触伤害、每人独立经验升级→每人独立选卡、
## 倒地→救援→复苏、无存活玩家→失败结算（M4.3 起不再有永久阵亡）、Boss 生成、Boss 数达标→胜利结算。

const Harness := preload("res://tools/tests/harness.gd")
const NetHostLogic := preload("res://net/net_host.gd")
const Combat := preload("res://sim/combat.gd")
const Progression := preload("res://sim/progression.gd")
const Weapons := preload("res://sim/weapons.gd")
const Waves := preload("res://sim/waves.gd")
const Rooms := preload("res://sim/rooms.gd")


func run() -> int:
	var t := Harness.new()

	# (1) 开火击杀 → 掉落 → 被玩家拾取
	var h := NetHostLogic.new()
	h.reset()
	h.spawn_interval = 9999.0
	h.add_player(2)
	h.set_remote_input(2, Vector2.ZERO, 0)
	h.spawn_enemy(Vector2(120, 0))
	h.local_buttons = 1
	for _i in range(90):
		h.physics_step(0.016)
	t.eq(h.enemies.size(), 0, "持续开火后敌人被击杀")
	t.check(h.players[1]["pickups"] >= 1, "击杀掉落被玩家磁吸拾取")

	# (2) 掉落磁吸：远处掉落被拉近并拾取
	var h2 := NetHostLogic.new()
	h2.reset()
	h2.spawn_interval = 9999.0
	h2.loot[1] = {"pos": Vector2(40, 0), "kind": Combat.LOOT_KIND_XP}
	for _i in range(60):
		h2.physics_step(0.016)
	t.eq(h2.loot.size(), 0, "磁吸范围内掉落被拾取")
	t.check(h2.players[1]["pickups"] >= 1, "拾取计数 +1")

	# (3) 敌人贴脸造成接触伤害
	var h3 := NetHostLogic.new()
	h3.reset()
	h3.spawn_interval = 9999.0
	var eid3 := h3.spawn_enemy(Vector2(0, 0))
	h3.enemies[eid3]["hp"] = 999999
	var hp0: int = h3.players[1]["hp"]
	for _i in range(30):
		h3.physics_step(0.016)
	t.check(h3.players[1]["hp"] < hp0, "贴脸敌人造成伤害")

	# (4) 状态导出结构
	var h4 := NetHostLogic.new()
	h4.reset()
	h4.spawn_interval = 9999.0
	h4.spawn_enemy(Vector2(10, 10))
	var ps: Array = h4.player_states()
	t.eq(ps.size(), 1, "player_states 含 1 人")
	t.check(ps[0].has("hp"), "player_states 含 hp")
	t.check(ps[0].has("status"), "player_states 含 status")
	t.eq(h4.enemy_states().size(), 1, "enemy_states 含 1 敌")
	t.eq(h4.loot_states().size(), 0, "loot_states 初始为空")

	# (5) 共享经验池 → 升级 → 每人独立候选 → 选卡生效
	var h5 := NetHostLogic.new()
	h5.reset()
	h5.spawn_interval = 9999.0
	h5.loot[1] = {"pos": Vector2(10, 0), "kind": Combat.LOOT_KIND_XP}
	h5.loot[2] = {"pos": Vector2(14, 0), "kind": Combat.LOOT_KIND_XP}
	for _i in range(20):
		h5.physics_step(0.016)
	t.check(int(h5.players[1]["level"]) >= 2, "拾取 2 个碎片（共 10 经验）后升到 2 级")
	var offers := h5.pending_offer(1)
	t.eq(offers.size(), 3, "升级后产生 3 张候选卡")
	t.eq(h5.pending_offer(1).size(), 0, "同一升级的候选只下发一次")
	t.check(not h5.apply_choice(1, 999), "不在候选中的卡被拒绝")
	t.check(h5.apply_choice(1, int(offers[0])), "候选中的卡被接受")
	var changed: bool = (
		h5.players[1]["mods"] != Progression.default_modifiers()
		or int(h5.players[1]["weapon"]) != Weapons.default_id()
	)
	t.check(changed, "选卡后玩家状态发生变化（修饰或武器）")
	t.eq(h5.apply_choice(1, int(offers[0])), false, "同一张卡不能重复选")

	# (6) 倒地：无人救援时被打入倒地状态
	var h6 := NetHostLogic.new()
	h6.reset()
	h6.spawn_interval = 9999.0
	h6.add_player(2)
	h6.set_remote_input(2, Vector2.ZERO, 0)
	h6.players[2]["pos"] = Vector2(1000, 0)
	var eid6 := h6.spawn_enemy(Vector2(0, 0))
	h6.enemies[eid6]["hp"] = 999999
	for _i in range(480):
		h6.physics_step(0.016)
	t.eq(h6.players[1]["status"], Combat.PLAYER_DOWNED, "血量归零进入倒地")

	# (7) 救援：队友贴近 2 秒完成复苏
	h6.players[2]["pos"] = Vector2(0, 20)
	for _i in range(140):
		h6.physics_step(0.016)
	t.eq(h6.players[1]["status"], Combat.PLAYER_ALIVE, "队友贴近后完成救援")
	t.eq(h6.players[1]["hp"], Combat.REVIVE_HP, "救起后恢复到固定血量")

	# (8) 单人倒地无人可救 → 立即判负；且不再发生永久阵亡
	var h8 := NetHostLogic.new()
	h8.reset()
	h8.spawn_interval = 9999.0
	var eid8 := h8.spawn_enemy(Vector2(0, 0))
	h8.enemies[eid8]["hp"] = 999999
	for _i in range(480):
		h8.physics_step(0.016)
	t.eq(h8.players[1]["status"], Combat.PLAYER_DOWNED, "单人倒地保持倒地（不再永久阵亡）")
	t.check(h8.run_over and not h8.won, "无存活玩家 → 立即结算失败")
	for _i in range(1400):
		h8.physics_step(0.016)
	t.eq(h8.players[1]["status"], Combat.PLAYER_DOWNED, "长时间无人救仍为倒地，非永久阵亡")

	# (9) Boss：击杀数达阈值刷新 Boss
	var h9 := NetHostLogic.new()
	h9.reset()
	h9.spawn_interval = 9999.0
	h9.kills = Combat.BOSS_EVERY_KILLS
	h9.physics_step(0.016)
	t.check(h9.boss_id != 0, "击杀数达阈值后生成 Boss")
	t.eq(h9.enemies[h9.boss_id]["kind"], Combat.ENEMY_KIND_BOSS, "生成的敌人 kind = Boss")
	t.eq(h9.enemies[h9.boss_id]["hp"], Combat.BOSS_MAX_HP, "Boss 初始满血")

	# (10) Boss 数达标 → 胜利结算
	var h10 := NetHostLogic.new()
	h10.reset()
	h10.spawn_interval = 9999.0
	h10.boss_kills = Combat.WIN_BOSS_KILLS
	h10.physics_step(0.016)
	t.check(h10.run_over and h10.won, "击败足够 Boss → 结算胜利")

	# (11) 元数据与统计导出
	var h11 := NetHostLogic.new()
	h11.reset()
	t.eq(h11.meta(1)["level"], 1, "初始等级 1")
	t.check(h11.stats(1).has("seconds"), "stats 含存活时长")

	# (12) 武器：霰弹枪一次开火产生多枚弹丸，且可导出弹丸状态
	var h12 := NetHostLogic.new()
	h12.reset()
	h12.spawn_interval = 9999.0
	h12.spawn_enemy(Vector2(120, 0))
	h12.players[1]["weapon"] = Weapons.KIND_SHOTGUN
	h12.local_buttons = 1
	h12.physics_step(0.016)
	var want := Weapons.projectile_count(Weapons.KIND_SHOTGUN, h12.players[1]["mods"])
	t.eq(h12.projectiles.size(), want, "霰弹枪一次开火产生多枚弹丸")
	t.eq(h12.projectile_states().size(), want, "projectile_states 与内部弹丸数一致")
	var st: Array = h12.projectile_states()
	t.check(st[0].has("dir") and st[0].has("kind"), "弹丸状态含 dir/kind")

	# (13) 波次：存活时长推进档位并缩短刷新间隔
	var h13 := NetHostLogic.new()
	h13.reset()
	h13.spawn_interval = 9999.0
	h13.elapsed = Waves.WAVE_DURATION * 2.0 + 1.0
	h13.physics_step(0.016)
	t.eq(h13.wave, 3, "存活时长推进波次到 3")
	t.check(h13.spawn_interval < Combat.SPAWN_INTERVAL, "高波次刷新间隔更短")

	# (14) 墙体：玩家被墙挡住不再靠近
	var h14 := NetHostLogic.new()
	h14.reset()
	h14.spawn_interval = 9999.0
	h14.room_walls = [Rect2(60.0, -50.0, 40.0, 100.0)]
	h14.local_move = Vector2.RIGHT
	for _i in range(120):
		h14.physics_step(0.016)
	var limit := 60.0 - Combat.PLAYER_RADIUS + 0.001
	t.check(h14.players[1]["pos"].x <= limit, "玩家被墙挡住不再靠近")
	t.check(h14.players[1]["pos"].x > 0.0, "玩家确实向右移动了一段")

	# (15) 敌人血量归一化：满血 hp01 = 255，与波次放大解耦（第 3 波 Boss 绝对 260 > u8）
	var h15 := NetHostLogic.new()
	h15.reset()
	h15.spawn_interval = 9999.0
	h15.elapsed = Waves.WAVE_DURATION * 2.0 + 1.0
	h15.physics_step(0.016)
	var eid15 := h15.spawn_boss()
	t.eq(int(h15.enemies[eid15]["hp"]), 260, "第 3 波 Boss 绝对血量 260（超出 u8 范围）")
	var full15 := false
	for s in h15.enemy_states():
		if int(s["id"]) == eid15:
			full15 = int(s["hp01"]) == 255
	t.check(full15, "满血 Boss hp01 = 255")
	h15.enemies[eid15]["hp"] = 130
	var half15 := false
	for s in h15.enemy_states():
		if int(s["id"]) == eid15:
			half15 = int(s["hp01"]) == 128
	t.check(half15, "半血 Boss hp01 = 128（130/260）")

	# (16) 掉落生命周期：超出 TTL 未被拾取则自动消失（消除无界累积）
	var h16 := NetHostLogic.new()
	h16.reset()
	h16.spawn_interval = 9999.0
	h16.loot[1] = {"pos": Vector2(3000, 3000), "kind": Combat.LOOT_KIND_XP, "ttl": Combat.LOOT_TTL}
	t.eq(h16.loot.size(), 1, "掉落初始存在")
	var steps := int(ceilf(Combat.LOOT_TTL / 0.016)) + 5
	for _i in range(steps):
		h16.physics_step(0.016)
	t.eq(h16.loot.size(), 0, "超过 TTL 的掉落被自动清除")

	# (17) 掉落硬上限：满员时新增掉落淘汰最旧（id 最小者）
	var h17 := NetHostLogic.new()
	h17.reset()
	h17.spawn_interval = 9999.0
	for i in range(Combat.MAX_LOOT):
		h17.loot[100 + i] = {"pos": Vector2(3000, 3000), "kind": Combat.LOOT_KIND_XP}
	var eid17 := h17.spawn_enemy(Vector2(3000, 3000))
	h17._kill_enemy(eid17)
	t.eq(h17.loot.size(), Combat.MAX_LOOT, "掉落数被硬上限约束")
	t.check(not h17.loot.has(100), "超限时淘汰最旧掉落")

	# (18) 全员倒地（无人可施救）→ 当帧判负
	var h18 := NetHostLogic.new()
	h18.reset()
	h18.spawn_interval = 9999.0
	h18.add_player(2)
	h18.set_remote_input(2, Vector2.ZERO, 0)
	h18.players[1]["status"] = Combat.PLAYER_DOWNED
	h18.players[2]["status"] = Combat.PLAYER_DOWNED
	h18.physics_step(0.016)
	t.check(h18.run_over and not h18.won, "全员倒地无人可救 → 立即判负")

	# (19) 仍有存活队友 → 不判负，倒地者可被反复救起
	var h19 := NetHostLogic.new()
	h19.reset()
	h19.spawn_interval = 9999.0
	h19.add_player(2)
	h19.set_remote_input(2, Vector2.ZERO, 0)
	h19.players[1]["status"] = Combat.PLAYER_DOWNED
	h19.players[2]["pos"] = Vector2(0, 20)
	for _i in range(140):
		h19.physics_step(0.016)
	t.eq(h19.players[1]["status"], Combat.PLAYER_ALIVE, "队友存活时倒地者被救起")
	t.check(not h19.run_over, "仍有存活玩家 → 不判负")

	return t.report("NetHostCombat")
