extends RefCounted
## 主机权威战斗逻辑测试（纯逻辑，无传输）：
## 开火→命中→敌人死亡→掉落→磁吸拾取；敌人贴脸造成接触伤害；状态导出结构正确。

const Harness := preload("res://tools/tests/harness.gd")
const NetHostLogic := preload("res://net/net_host.gd")


func run() -> int:
	var t := Harness.new()

	# (1) 开火击杀 → 掉落 → 被玩家拾取
	var h := NetHostLogic.new()
	h.reset()
	h.spawn_interval = 9999.0  # 关闭自动生成，隔离本用例
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
	h2.loot[1] = {"pos": Vector2(40, 0), "kind": 0}
	for _i in range(60):
		h2.physics_step(0.016)
	t.eq(h2.loot.size(), 0, "磁吸范围内掉落被拾取")
	t.check(h2.players[1]["pickups"] >= 1, "拾取计数 +1")

	# (3) 敌人贴脸造成接触伤害
	var h3 := NetHostLogic.new()
	h3.reset()
	h3.spawn_interval = 9999.0
	h3.spawn_enemy(Vector2(0, 0))
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
	t.eq(h4.enemy_states().size(), 1, "enemy_states 含 1 敌")
	t.eq(h4.loot_states().size(), 0, "loot_states 初始为空")

	return t.report("NetHostCombat")
