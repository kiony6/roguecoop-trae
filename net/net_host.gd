extends RefCounted  # gdlint:ignore=max-public-methods
## 主机权威模拟（纯逻辑，不含传输）。由 autoload Net 驱动。
## M3：在 M2 战斗之上叠加每人独立经验与等级+每人独立选卡、倒地/救援/阵亡、Boss 与结算判定。

const Movement := preload("res://sim/movement.gd")
const Combat := preload("res://sim/combat.gd")
const EnemyAI := preload("res://sim/enemy_ai.gd")
const Progression := preload("res://sim/progression.gd")
const Weapons := preload("res://sim/weapons.gd")
const Rooms := preload("res://sim/rooms.gd")
const Waves := preload("res://sim/waves.gd")
const Levels := preload("res://sim/levels.gd")
const Skills := preload("res://sim/skills.gd")
const SkillRuntime := preload("res://sim/skill_runtime.gd")
const IDLE_RESET_SECONDS := 10.0  # 空场（无人接入）持续这么久且上一局被玩过 → 整局状态归零
const MAX_FX_EVENTS := 64  # 单帧待广播特效上限（防刷屏/防累积）
const MAX_SKILL_EVENTS := 64  # 单帧待处理技能事件上限（防爆发拖垮主机）

var tick := 0
var snapshot_count := 0
var local_move := Vector2.ZERO
var local_buttons := 0
var spawn_interval := Waves.spawn_interval(1)
var wave := 1
var room_walls: Array = []

# —— 队伍成长与结算 ——
var kills := 0
var boss_kills := 0
var elapsed := 0.0
var run_over := false
var won := false
var boss_id := 0
var level_id := Levels.DEFAULT_LEVEL  # 关卡（区域）：只影响配色/元素偏向/曲线覆盖
var difficulty_id := Levels.DEFAULT_DIFFICULTY  # 难度档位：默认「普通」= 原始数值，零回归

var players := {}  # id -> {pos, move, buttons, hp, status, fire_cd, invuln,
# revive_progress, pickups, mods, level, xp}
var enemies := {}  # id -> {pos, hp, kind, touch_cd}
var loot := {}  # id -> {pos, kind, owner, ttl}
var projectiles := {}  # id -> {pos, vel, ttl, dmg, owner}
var idle_resets := 0  # 累计「空场超时归零」次数，供运维日志观测
var idle_reset_seconds := 0.0  # 最近一次复位时的空置时长
var fx_events: Array = []  # 本帧产生的特效事件（kind/pos/dir/radius），由 Net 取走后广播

var _events: Array = []  # 本帧待处理的技能触发事件（player/event/pos）

var _next_id := 1
var _spawn_accum := 0.0
var _next_boss_at := Combat.BOSS_EVERY_KILLS
var _offer := {}  # id -> Array[card_id]，本升级的候选卡
var _offer_sent := {}  # id -> bool，候选是否已下发
var _rng := RandomNumberGenerator.new()
var _dedicated := false
var _idle_seconds := 0.0


func reset(dedicated: bool = false, seed_value: int = 20261015) -> void:
	## dedicated=true 时不预置本地玩家（专服）；seed_value 决定地图与 RNG 种子，
	## 默认值 20261015 保证既有 HOST / game 模式行为逐位不变，SERVER 每房传独立随机种子。
	tick = 0
	snapshot_count = 0
	local_move = Vector2.ZERO
	local_buttons = 0
	wave = Levels.wave_of(level_id, difficulty_id, 0.0)
	spawn_interval = Levels.spawn_interval(level_id, difficulty_id, wave)
	room_walls = Rooms.generate(seed_value)
	kills = 0
	boss_kills = 0
	elapsed = 0.0
	run_over = false
	won = false
	boss_id = 0
	players = {} if dedicated else {1: _new_player()}
	enemies = {}
	loot = {}
	projectiles = {}
	fx_events = []
	_events = []
	_next_id = 1
	_spawn_accum = 0.0
	_next_boss_at = Levels.boss_every_kills(difficulty_id)
	_offer = {}
	_offer_sent = {}
	_rng.seed = seed_value
	_dedicated = dedicated
	_idle_seconds = 0.0


func set_run_config(new_level_id: int, new_difficulty_id: int) -> void:
	## 关卡/难度配置（开局前由房主/专服写入）。只影响之后刷出的敌人与波次间隔，
	## 不追改场上存量敌人（避免中途改难度造成血条跳变）。关卡/难度跨 reset 保留。
	level_id = clampi(new_level_id, 0, Levels.level_count() - 1)
	difficulty_id = clampi(new_difficulty_id, 0, Levels.difficulty_count() - 1)
	wave = Levels.wave_of(level_id, difficulty_id, elapsed)
	spawn_interval = Levels.spawn_interval(level_id, difficulty_id, wave)
	if kills == 0:
		_next_boss_at = Levels.boss_every_kills(difficulty_id)


func add_player(id: int) -> void:
	players[id] = _new_player()


func remove_player(id: int) -> void:
	players.erase(id)
	_offer.erase(id)
	_offer_sent.erase(id)


func has_player(id: int) -> bool:
	return players.has(id)


func set_remote_input(id: int, move: Vector2, buttons: int) -> void:
	if players.has(id):
		players[id]["move"] = move
		players[id]["buttons"] = buttons


func spawn_enemy(pos: Vector2, kind: int = Combat.ENEMY_KIND_NORMAL) -> int:
	var eid := _alloc_id()
	var full := Levels.enemy_hp(kind, level_id, difficulty_id, wave)
	var elem := Levels.element_bias(level_id)
	var elem_until := 0.0
	if elem != Skills.ELEM_PHYS:
		elem_until = elapsed + Skills.ELEMENT_SECONDS  # 关卡元素偏向：开局自带元素
	enemies[eid] = {
		"pos": pos,
		"hp": full,
		"max_hp": full,
		"kind": kind,
		"touch_cd": 0.0,
		"element": elem,
		"element_until": elem_until,
	}
	return eid


func spawn_boss() -> int:
	var anchor := _random_player_pos()
	var angle := _rng.randf_range(0.0, TAU)
	var at := anchor + Vector2.RIGHT.rotated(angle) * Combat.SPAWN_RADIUS
	var eid := spawn_enemy(Rooms.clamp_inside(at, Combat.BOSS_RADIUS), Combat.ENEMY_KIND_BOSS)
	boss_id = eid
	return eid


func physics_step(delta: float) -> void:
	if run_over:
		return
	# M5.2：无人接入时不推进模拟（tick/elapsed 全冻结），避免空置时长把波次难度无限抬高
	if players.is_empty():
		_step_idle(delta)
		return
	_idle_seconds = 0.0
	tick += 1
	elapsed += delta
	var w := Levels.wave_of(level_id, difficulty_id, elapsed)
	if w != wave:
		wave = w
		spawn_interval = Levels.spawn_interval(level_id, difficulty_id, w)
	if players.has(1):
		players[1]["move"] = local_move
		players[1]["buttons"] = local_buttons
	_step_players(delta)
	_step_firing()
	_step_projectiles(delta)
	_step_enemies(delta)
	_step_downed(delta)
	_step_loot(delta)
	_step_skills(delta)
	_step_spawner(delta)
	_check_run_over()


func meta(id: int) -> Dictionary:
	var p: Dictionary = players[id]
	return {
		"level": int(p["level"]),
		"xp": int(p["xp"]),
		"kills": kills,
		"boss_kills": boss_kills,
		"wave": wave
	}


func stats(id: int) -> Dictionary:
	var p: Dictionary = players[id]
	return {"kills": kills, "level": int(p["level"]), "boss_kills": boss_kills, "seconds": elapsed}


func player_states() -> Array:
	var out: Array = []
	for id in peer_ids():
		var p: Dictionary = players[id]
		(
			out
			. append(
				{
					"id": id,
					"pos": p["pos"],
					"hp": p["hp"],
					"status": p["status"],
					"revive01": _revive01(p),
					"weapon": p["weapon"],
				}
			)
		)
	return out


func enemy_states() -> Array:
	var out: Array = []
	for id in enemies:
		(
			out
			. append(
				{
					"id": id,
					"pos": enemies[id]["pos"],
					"hp01": _hp01(enemies[id]),
					"kind": enemies[id]["kind"],
				}
			)
		)
	return out


func element_states() -> Array:
	## 元素状态的稀疏同步载荷：只列出「带非物理元素 + 仍在有效期内」的敌人，上限 MAX_ELEMENT_SYNC。
	var out: Array = []
	for id in enemies:
		if out.size() >= Skills.MAX_ELEMENT_SYNC:
			break
		var e: Dictionary = enemies[id]
		var elem := int(e.get("element", Skills.ELEM_PHYS))
		if elem == Skills.ELEM_PHYS:
			continue
		if float(e.get("element_until", 0.0)) <= elapsed:
			continue
		out.append({"id": id, "elem": elem})
	return out


func loot_states() -> Array:
	var out: Array = []
	for id in loot:
		out.append({"id": id, "pos": loot[id]["pos"], "kind": loot[id]["kind"]})
	return out


func projectile_states() -> Array:
	var out: Array = []
	for id in projectiles:
		var pr: Dictionary = projectiles[id]
		out.append({"id": id, "pos": pr["pos"], "dir": pr["dir"], "kind": pr["kind"]})
	return out


func peer_ids() -> PackedInt32Array:
	var ids := PackedInt32Array()
	var keys := players.keys()
	keys.sort()
	for k in keys:
		ids.append(int(k))
	return ids


# ---------------- 成长（每人独立经验与等级 + 每人独立选卡） ----------------


func gain_xp(id: int, amount: int) -> int:
	## M4.4：经验记到拾取者本人（每人独立经验）；跨阈值则只给该玩家发一次候选。
	if amount <= 0 or not players.has(id):
		return 0
	var p: Dictionary = players[id]
	p["xp"] = int(p["xp"]) + amount
	var ups := 0
	while int(p["xp"]) >= Progression.xp_to_next(int(p["level"])):
		p["xp"] = int(p["xp"]) - Progression.xp_to_next(int(p["level"]))
		p["level"] = int(p["level"]) + 1
		p["skill_points"] = int(p["skill_points"]) + 1  # 每次升级额外获得 1 技能点
		ups += 1
	if ups > 0:
		_emit_fx(Combat.FX_LEVELUP, p["pos"], 0.0)
		_grant_offer(id)
	return ups


func pending_offer(id: int) -> Array:
	## 取「尚未下发」的候选卡并标记为已下发；无候选或已下发返回空。
	if _offer.has(id) and not _offer_sent.get(id, false):
		_offer_sent[id] = true
		return _offer[id]
	return []


func apply_choice(id: int, card_id: int) -> bool:
	## 校验 card_id 是否在本轮候选内；通过则叠加修饰（只作用于该玩家）。
	if not players.has(id) or not _offer.has(id):
		return false
	if not _offer[id].has(card_id):
		return false
	var card := Progression.card_by_id(card_id)
	if card.is_empty():
		return false
	var p: Dictionary = players[id]
	p["mods"] = Progression.apply_card(p["mods"], card)
	if card.has("max_hp_add"):
		p["hp"] = mini(p["hp"] + int(card["max_hp_add"]), Progression.max_hp(p["mods"]))
	if card.has("weapon_set"):
		p["weapon"] = int(card["weapon_set"])
	_offer.erase(id)
	_offer_sent.erase(id)
	return true


func _grant_offer(id: int) -> void:
	if not players.has(id) or players[id]["status"] == Combat.PLAYER_DEAD:
		return
	_offer[id] = Progression.draw_choices(_rng, 3)
	_offer_sent[id] = false


# ---------------- 技能树（每人独立节点 + 技能点） ----------------


func unlock_skill(id: int, node_id: int) -> bool:
	## 权威侧解锁一个技能节点：校验门禁（前置/点数）后扣点并追加。重复/非法一律拒绝。
	if not players.has(id):
		return false
	var p: Dictionary = players[id]
	if not Skills.can_unlock(p["skill_nodes"], node_id, int(p["skill_points"])):
		return false
	p["skill_nodes"] = Skills.unlock(p["skill_nodes"], node_id)
	p["skill_points"] = int(p["skill_points"]) - Skills.cost_of(node_id)
	return true


func set_initial_build(id: int, preset_id: String = "") -> void:
	## 初始构筑：开局直接授予一组节点（不消耗技能点），替代《生存代码》的 13 个角色专属起手。
	if not players.has(id):
		return
	var pid := preset_id if not preset_id.is_empty() else Skills.default_preset()
	var pset := Skills.preset(pid)
	if pset.is_empty():
		pset = Skills.preset(Skills.default_preset())
	players[id]["skill_nodes"] = Skills.grant([], pset["nodes"])
	players[id]["preset"] = String(pset["id"])


func skill_state(id: int) -> Dictionary:
	## 下发到客户端的技能树状态（技能点 + 已解锁节点）。
	if not players.has(id):
		return {"points": 0, "nodes": []}
	var p: Dictionary = players[id]
	return {"points": int(p["skill_points"]), "nodes": (p["skill_nodes"] as Array).duplicate()}


func take_fx_events() -> Array:
	## 取走本帧待广播特效；不取则保留（专服逐房场景下由 Net 每帧取一次）。
	var out := fx_events
	fx_events = []
	return out


# ---------------- 内部步进 ----------------


func _step_players(delta: float) -> void:
	for id in players:
		var p: Dictionary = players[id]
		p["fire_cd"] = maxf(0.0, p["fire_cd"] - delta)
		if p["status"] != Combat.PLAYER_ALIVE:
			continue
		p["pos"] = Movement.step(p["pos"], p["move"], delta, Movement.SPEED, room_walls)


func _step_firing() -> void:
	## M4.4：武器自动攻击——无需按键，最近敌人进入该武器有效射程即开火。
	var targets := _enemy_positions()
	for id in players:
		var p: Dictionary = players[id]
		if p["status"] != Combat.PLAYER_ALIVE:
			continue
		if p["fire_cd"] > 0.0:
			continue
		var nearest := INF
		for t in targets:
			nearest = minf(nearest, p["pos"].distance_to(t["pos"]))
		if nearest > Weapons.reach(int(p["weapon"])):
			continue
		var dir := Combat.aim_dir(p["pos"], targets)
		if dir == Vector2.ZERO:
			continue
		p["fire_cd"] = Weapons.cooldown(p["weapon"], p["mods"])
		_spawn_projectiles(p["pos"], dir, p["weapon"], p["mods"], id)


func _step_projectiles(delta: float) -> void:
	var expired: Array = []
	var killed: Array = []
	for pid in projectiles:
		var pr: Dictionary = projectiles[pid]
		pr["pos"] = pr["pos"] + pr["vel"] * delta
		pr["ttl"] -= delta
		if pr["ttl"] <= 0.0:
			expired.append(pid)
			continue
		for eid in enemies.keys():
			if not enemies.has(eid):
				continue
			var e: Dictionary = enemies[eid]
			var radius := Combat.enemy_radius(e["kind"])
			var proj_r := Skills.projectile_radius(pr["kind"])
			var hit := Combat.circle_hit(pr["pos"], proj_r, e["pos"], radius)
			if not hit:
				continue
			var owner := int(pr.get("owner", 0))
			e["hp"] -= int(pr["dmg"])
			_emit_fx(Combat.FX_HIT, e["pos"], 0.0)
			_resolve_element(pr, int(eid), e, owner)
			_queue_event(owner, Skills.TRIG_HIT, e["pos"])
			expired.append(pid)
			if enemies.has(eid) and int(e["hp"]) <= 0:
				killed.append([eid, owner])
			break
	for pid in expired:
		projectiles.erase(pid)
	for k in killed:
		_kill_enemy(int(k[0]), int(k[1]))


func _step_enemies(delta: float) -> void:
	var targets := _alive_targets()
	for eid in enemies:
		var e: Dictionary = enemies[eid]
		if int(e["element"]) != Skills.ELEM_PHYS and float(e["element_until"]) <= elapsed:
			e["element"] = Skills.ELEM_PHYS  # 过期即清除，避免元素状态无限残留
			e["element_until"] = 0.0
		var kind: int = e["kind"]
		var dir := EnemyAI.chase_dir(e["pos"], targets)
		var speed := Levels.enemy_speed(kind, level_id, difficulty_id, wave)
		e["pos"] = EnemyAI.step(e["pos"], dir, delta, speed)
		e["touch_cd"] = maxf(0.0, e["touch_cd"] - delta)
		if e["touch_cd"] > 0.0:
			continue
		var radius := Combat.enemy_radius(kind)
		for id in players:
			var p: Dictionary = players[id]
			if p["status"] != Combat.PLAYER_ALIVE:
				continue
			if p["invuln"] > 0.0:
				continue
			var touching := Combat.circle_hit(e["pos"], radius, p["pos"], Combat.PLAYER_RADIUS)
			if not touching:
				continue
			var dmg := Combat.enemy_touch_damage(kind)
			if int(p["shield"]) > 0:
				# 「防火墙」护盾优先吸收，护盾见底前不掉血
				var absorbed := mini(int(p["shield"]), dmg)
				p["shield"] = int(p["shield"]) - absorbed
				dmg -= absorbed
				_emit_fx(Combat.FX_SHIELD, p["pos"], 0.0)
			if dmg > 0:
				p["hp"] = maxi(0, p["hp"] - dmg)
			_queue_event(id, Skills.TRIG_HURT, p["pos"])
			e["touch_cd"] = Combat.enemy_touch_interval(kind)
			if p["hp"] <= 0:
				p["status"] = Combat.PLAYER_DOWNED
				p["revive_progress"] = 0.0
			break


func _step_downed(delta: float) -> void:
	## M4.3：不再有流血永久阵亡——倒地者只要附近有存活队友即可被救起，可无限次。
	for id in players:
		var p: Dictionary = players[id]
		if p["invuln"] > 0.0:
			p["invuln"] = maxf(0.0, p["invuln"] - delta)
		if p["status"] != Combat.PLAYER_DOWNED:
			continue
		if _count_helpers(id) > 0:
			p["revive_progress"] += delta
			if p["revive_progress"] >= Combat.REVIVE_HOLD:
				p["status"] = Combat.PLAYER_ALIVE
				p["hp"] = Combat.REVIVE_HP
				p["invuln"] = Combat.REVIVE_INVULN
				p["revive_progress"] = 0.0
		else:
			p["revive_progress"] = maxf(0.0, p["revive_progress"] - delta * 2.0)


func _step_loot(delta: float) -> void:
	var removed: Array = []
	for lid in loot:
		var l: Dictionary = loot[lid]
		var ttl := float(l.get("ttl", Combat.LOOT_TTL)) - delta
		if ttl <= 0.0:
			removed.append(lid)
			continue
		l["ttl"] = ttl
		# M4.4：碎片归属击杀者；击杀者不在场/已倒地则回退到最近的存活玩家
		var owner := int(l.get("owner", 0))
		var target := 0
		if owner != 0 and players.has(owner) and players[owner]["status"] == Combat.PLAYER_ALIVE:
			target = owner
		else:
			target = _nearest_alive_player_id(l["pos"])
		if target == 0:
			continue
		var p: Dictionary = players[target]
		var to_player: Vector2 = p["pos"] - l["pos"]
		var d := to_player.length()
		var pickup_r := Combat.PICKUP_RADIUS + float(p["mods"]["pickup_add"])
		if d <= pickup_r:
			p["pickups"] += 1
			gain_xp(target, Combat.loot_xp(int(l["kind"])))
			var heal := int(p["mods"]["heal_add"])
			if heal > 0:
				p["hp"] = mini(p["hp"] + heal, Progression.max_hp(p["mods"]))
			if int(l["kind"]) == Combat.LOOT_KIND_BYTE:
				# 字节币入库（有界）：只有拾取字节币才触发「拾取挂钩」
				p["bytes_owned"] = mini(Skills.BYTE_KIND_MAX, int(p["bytes_owned"]) + 1)
				_emit_fx(Combat.FX_COIN, l["pos"], 0.0)
				_queue_event(target, Skills.TRIG_PICKUP, l["pos"])
			removed.append(lid)
		else:
			# M4.4：取消磁吸半径上限——碎片从任意距离飞向归属玩家
			var magnet := Combat.LOOT_MAGNET_SPEED + float(p["mods"].get("magnet_speed_add", 0))
			l["pos"] = l["pos"] + to_player.normalized() * magnet * delta
	for lid in removed:
		loot.erase(lid)


func _step_spawner(delta: float) -> void:
	if players.is_empty():
		return  # 专用服务器在无人接入前不刷怪，避免敌人空堆在原点
	_spawn_accum += delta
	var cap := Levels.max_enemies(level_id, difficulty_id, wave)
	if _spawn_accum >= spawn_interval and enemies.size() < cap:
		_spawn_accum = 0.0
		_spawn_normal()
	if kills >= _next_boss_at and boss_id == 0 and not players.is_empty():
		spawn_boss()
		_next_boss_at += Levels.boss_every_kills(difficulty_id)


func _step_idle(delta: float) -> void:
	## M5.2：空场步进。既不推进波次计时，也不跑任何模拟。
	## 仅当上一局确实被玩过（elapsed > 0）且空置已达 IDLE_RESET_SECONDS 时，把整局状态就地归零，
	## 让下一位接入的玩家面对全新开局，而不是一个被打残、波次还偏高的残局。
	## 归零后 elapsed 变为 0，幂等保护使复位不会反复触发（刚启动的空服务器永远静止在 wave = 1）。
	_idle_seconds += delta
	if _idle_seconds < IDLE_RESET_SECONDS or elapsed <= 0.0:
		return
	idle_reset_seconds = _idle_seconds
	reset(_dedicated)
	idle_resets += 1


# ---------------- 内部辅助 ----------------


func _spawn_normal() -> void:
	var anchor := _random_player_pos()
	var angle := _rng.randf_range(0.0, TAU)
	var at := anchor + Vector2.RIGHT.rotated(angle) * Combat.SPAWN_RADIUS
	spawn_enemy(Rooms.clamp_inside(at, Combat.ENEMY_RADIUS))


func _spawn_projectiles(
	pos: Vector2, dir: Vector2, weapon: int, mods: Dictionary, owner: int
) -> void:
	var n := Weapons.projectile_count(weapon, mods)
	var dmg := Weapons.damage(weapon, mods)
	var spread := Weapons.spread(weapon)
	var speed := Weapons.speed(weapon)
	var ttl := Weapons.ttl(weapon)
	for i in n:
		if projectiles.size() >= Weapons.MAX_PROJECTILES:
			break
		var off := (float(i) - float(n - 1) * 0.5) * spread
		var d := dir.rotated(off)
		var pid := _alloc_id()
		projectiles[pid] = {
			"pos": pos,
			"vel": d * speed,
			"ttl": ttl,
			"dmg": dmg,
			"dir": d,
			"kind": weapon,
			"owner": owner,
		}


func _kill_enemy(eid: int, owner: int = 0) -> void:
	if not enemies.has(eid):
		return
	var e: Dictionary = enemies[eid]
	var pos: Vector2 = e["pos"]
	var kind: int = e["kind"]
	var overflow := maxi(0, -int(e["hp"]))  # 击杀时的溢出伤害（供「超杀」转化）
	enemies.erase(eid)
	if eid == boss_id:
		boss_id = 0
		boss_kills += 1
	kills += 1
	_emit_fx(Combat.FX_BURST, pos, 30.0)
	_queue_event(owner, Skills.TRIG_KILL, pos)
	var loot_kind := Combat.LOOT_KIND_BIG if kind == Combat.ENEMY_KIND_BOSS else Combat.LOOT_KIND_XP
	_add_loot(pos, loot_kind, owner)
	_overkill_burst(pos, overflow, owner)


func _overkill_burst(pos: Vector2, overflow: int, owner: int) -> void:
	## 「超杀」修饰：把击杀时的溢出伤害炸成一圈 AoE，仅在解锁该修饰的玩家身上发生。
	if overflow <= 0 or not players.has(owner):
		return
	var radius := float(Skills.modifiers(players[owner]["skill_nodes"])["overkill_radius"])
	if radius <= 0.0:
		return
	_skill_aoe(pos, radius, overflow, owner)
	_emit_fx(Combat.FX_BURST, pos, radius)


func _add_loot(pos: Vector2, kind: int, owner: int = 0) -> void:
	## 有界掉落：先按硬上限淘汰最旧（实体 id 单调递增 → 最小 id 即最旧），再带 TTL 入池。
	while loot.size() >= Combat.MAX_LOOT:
		var keys := loot.keys()
		keys.sort()
		loot.erase(int(keys[0]))
	var lid := _alloc_id()
	loot[lid] = {"pos": pos, "kind": kind, "owner": owner, "ttl": Combat.LOOT_TTL}


func _check_run_over() -> void:
	## M4.3：失败条件放宽为「场上无任何 PLAYER_ALIVE」——全员倒地/阵亡且无人可施救即当帧判负。
	if run_over:
		return
	var any_alive := false
	for id in players:
		if players[id]["status"] == Combat.PLAYER_ALIVE:
			any_alive = true
			break
	if not any_alive and not players.is_empty():
		run_over = true
		won = false
		return
	if boss_id == 0 and boss_kills >= Combat.WIN_BOSS_KILLS:
		run_over = true
		won = true


func _enemy_positions() -> Array:
	var out: Array = []
	for id in enemies:
		out.append({"pos": enemies[id]["pos"]})
	return out


func _alive_targets() -> Array:
	var out: Array = []
	for id in players:
		if players[id]["status"] == Combat.PLAYER_ALIVE:
			out.append({"pos": players[id]["pos"]})
	return out


func _count_helpers(id: int) -> int:
	var n := 0
	var pos: Vector2 = players[id]["pos"]
	for other in players:
		if other == id:
			continue
		var p: Dictionary = players[other]
		if p["status"] != Combat.PLAYER_ALIVE:
			continue
		if pos.distance_to(p["pos"]) <= Combat.REVIVE_RADIUS:
			n += 1
	return n


func _revive01(p: Dictionary) -> int:
	return clampi(roundi(float(p["revive_progress"]) / Combat.REVIVE_HOLD * 255.0), 0, 255)


func _hp01(e: Dictionary) -> int:
	## 血条比例，分母与主机权威血量同源（生成时定档），避免与波次放大后的绝对值错配。
	var full := maxi(1, int(e.get("max_hp", 1)))
	return clampi(roundi(float(e["hp"]) / float(full) * 255.0), 0, 255)


func _nearest_alive_player_id(pos: Vector2) -> int:
	var best := 0
	var best_d := INF
	for id in players:
		if players[id]["status"] != Combat.PLAYER_ALIVE:
			continue
		var d: float = players[id]["pos"].distance_to(pos)
		if d < best_d:
			best_d = d
			best = id
	return best


func _random_player_pos() -> Vector2:
	var ids := players.keys()
	if ids.is_empty():
		return Vector2.ZERO
	return players[ids[_rng.randi_range(0, ids.size() - 1)]]["pos"]


func _alloc_id() -> int:
	_next_id += 1
	return _next_id


func _new_player() -> Dictionary:
	return {
		"pos": Vector2.ZERO,
		"move": Vector2.ZERO,
		"buttons": 0,
		"hp": Combat.PLAYER_MAX_HP,
		"status": Combat.PLAYER_ALIVE,
		"fire_cd": 0.0,
		"invuln": 0.0,
		"revive_progress": 0.0,
		"pickups": 0,
		"weapon": Weapons.default_id(),
		"mods": Progression.default_modifiers(),
		"level": 1,
		"xp": 0,
		"skill_points": 0,
		"skill_nodes": [],
		"skill_state": SkillRuntime.new_state(),
		"bytes_owned": 0,
		"shield": 0,
		"preset": "",
	}


# ---------------- 技能执行（权威侧落地 runtime 的动作指令） ----------------


func _step_skills(delta: float) -> void:
	## 技能只在存活玩家上跑：先周期触发（遍历/字节农场），再消费本帧事件（命中/击杀/拾取/受伤）。
	## 事件批次先取走再处理，避免 _kill_enemy 追加的事件在本帧内形成无界递归。
	var batch := _events
	_events = []
	if players.is_empty():
		return
	for id in players.keys():
		if not players.has(id):
			continue
		var p: Dictionary = players[id]
		if p["status"] != Combat.PLAYER_ALIVE:
			continue
		var nodes: Array = p["skill_nodes"]
		if nodes.is_empty():
			continue
		_apply_commands(id, SkillRuntime.tick(p["skill_state"], nodes, delta, elapsed))
	for ev in batch:
		var pid := int(ev["player"])
		if not players.has(pid) or players[pid]["status"] != Combat.PLAYER_ALIVE:
			continue
		var ev_nodes: Array = players[pid]["skill_nodes"]
		if ev_nodes.is_empty():
			continue
		_apply_commands(
			pid,
			SkillRuntime.dispatch(players[pid]["skill_state"], ev_nodes, int(ev["event"]), elapsed)
		)


func _apply_commands(id: int, cmds: Array) -> void:
	if cmds.is_empty() or not players.has(id):
		return
	var p: Dictionary = players[id]
	if p["status"] != Combat.PLAYER_ALIVE:
		return
	var pos: Vector2 = p["pos"]
	for c in cmds:
		if not _condition_ok(p, c):
			continue
		# 循环层：同一条动作指令重复执行 loops 次（上限 MAX_LOOPS，防被叠成无限递归）
		var loops := clampi(int(c.get("loops", 1)), 1, Skills.MAX_LOOPS)
		for _i in loops:
			_apply_effect(id, p, pos, c)


func _condition_ok(p: Dictionary, c: Dictionary) -> bool:
	## 条件分支门禁：全部按权威侧实时状态判定（客户端不参与，避免作弊与不同步）。
	match int(c.get("cond", Skills.COND_NONE)):
		Skills.COND_LOW_HP:
			var max_hp := maxi(1, Progression.max_hp(p["mods"]))
			return float(p["hp"]) / float(max_hp) * 100.0 <= float(c.get("cond_value", 0))
		Skills.COND_BYTES:
			return int(p["bytes_owned"]) >= int(c.get("cond_value", 0))
		Skills.COND_ENEMIES:
			return enemies.size() >= int(c.get("cond_value", 0))
		Skills.COND_WAVE:
			return wave >= int(c.get("cond_value", 0))
	return true


func _apply_effect(id: int, p: Dictionary, pos: Vector2, c: Dictionary) -> void:
	## 单条动作指令落地。「进化脉冲」按波次给可增幅伤害补偿；固定伤害类（damage_base）不受影响。
	var cc := c
	var wave_extra := int(c.get("wave_damage", 0)) * maxi(0, wave - 1)
	if wave_extra > 0:
		cc = c.duplicate()
		cc["damage"] = int(c["damage"]) + wave_extra
	match int(cc["effect"]):
		Skills.EFF_SPAWN_BYTE:
			_add_loot(pos, Combat.LOOT_KIND_BYTE, id)
			_emit_fx(Combat.FX_COIN, pos, 0.0)
		Skills.EFF_SINGLE_DMG:
			_fire_skill_shot(id, pos, 8, cc)
		Skills.EFF_LASER:
			_fire_skill_shot(id, pos, 10, cc)
			# 亮束长度取固定值（c["radius"] 是弹丸半径，不等于束长），方向对准最近敌人
			_emit_fx(Combat.FX_LASER, pos, 260.0, Combat.aim_dir(pos, _enemy_positions()))
		Skills.EFF_SPLIT:
			_fire_skill_shot(id, pos, 11, cc)
		Skills.EFF_HOMING:
			_fire_skill_shot(id, pos, 12, cc)
		Skills.EFF_SPIKE:
			_fire_skill_volley(id, pos, Skills.PROJ_SPIKE, cc, maxi(1, int(cc["count"])), 0.22)
		Skills.EFF_CHIP:
			# 芯片数据包：命中后在原地植入一块伤害区域
			_skill_aoe(pos, float(cc["radius"]), int(cc["damage"]), id)
			_emit_fx(Combat.FX_CHIP, pos, float(cc["radius"]))
		Skills.EFF_BUG:
			# BUG 机制：击杀后向附近敌人扩散病毒
			_skill_aoe(pos, float(cc["radius"]), int(cc["damage"]), id)
			_emit_fx(Combat.FX_BUG, pos, float(cc["radius"]))
		Skills.EFF_NULL:
			# 空指针：受伤时近身反击
			_skill_aoe(pos, float(cc["radius"]), int(cc["damage"]), id)
			_emit_fx(Combat.FX_NULL, pos, float(cc["radius"]))
		Skills.EFF_WEAKEST:
			# 最弱协议：处决血量比例最低的敌人
			_skill_hit_weakest(int(cc["damage"]), id)
		Skills.EFF_GIGA:
			_skill_aoe(pos, float(cc["radius"]), int(cc["damage"]), id)
			_emit_fx(Combat.FX_GIGA, pos, float(cc["radius"]))
		Skills.EFF_FAULT:
			_skill_aoe(pos, float(cc["radius"]), int(cc["damage"]), id)
			_emit_fx(Combat.FX_FAULT, pos, float(cc["radius"]))
		Skills.EFF_SPIN:
			_skill_aoe(pos, float(cc["radius"]), int(cc["damage"]), id)
			_emit_fx(Combat.FX_SPIN, pos, float(cc["radius"]))
		Skills.EFF_MINE_COPY:
			var mines := maxi(1, int(cc["count"]))
			for i in mines:
				var off := Vector2.RIGHT.rotated(TAU * float(i) / float(mines)) * 36.0
				_skill_aoe(pos + off, float(cc["radius"]), int(cc["damage"]), id)
				_emit_fx(Combat.FX_BURST, pos + off, float(cc["radius"]))
		Skills.EFF_BYTE_BURST:
			if _consume_bytes(id, 1):
				# 字节爆裂/风暴/脉冲：固定伤害，不受「溢出伤害」等修饰增幅
				_skill_aoe(pos, float(cc["radius"]), int(cc["damage_base"]), id)
				_emit_fx(Combat.FX_BURST, pos, float(cc["radius"]))
		Skills.EFF_BYTE_STORM:
			if _consume_bytes(id, int(p["bytes_owned"])):
				_skill_aoe(pos, float(cc["radius"]), int(cc["damage_base"]), id)
				_emit_fx(Combat.FX_BURST, pos, float(cc["radius"]))
		Skills.EFF_BYTE_PULSE:
			_skill_aoe(pos, float(cc["radius"]), int(cc["damage_base"]), id)
			_emit_fx(Combat.FX_PULSE, pos, float(cc["radius"]))
		Skills.EFF_NUKE:
			_skill_aoe(pos, float(cc["radius"]), int(cc["damage"]), id)
			_emit_fx(Combat.FX_NUKE, pos, float(cc["radius"]))
		Skills.EFF_ORBIT:
			_skill_aoe(pos, 90.0, int(cc["damage"]), id)
			_emit_fx(Combat.FX_PULSE, pos, 90.0)
		Skills.EFF_MINE:
			_skill_aoe(pos, float(cc["radius"]), int(cc["damage"]), id)
			_emit_fx(Combat.FX_BURST, pos, float(cc["radius"]))
		Skills.EFF_SHIELD:
			p["shield"] = Combat.BYTE_SHIELD
			_emit_fx(Combat.FX_SHIELD, pos, 0.0)
		Skills.EFF_DRAIN:
			p["hp"] = mini(int(p["hp"]) + Combat.DRAIN_HEAL, Progression.max_hp(p["mods"]))
			_emit_fx(
				Combat.FX_DRAIN, pos, float(cc["radius"]), Combat.aim_dir(pos, _enemy_positions())
			)
		Skills.EFF_SUMMON:
			_skill_aoe(pos, 70.0, Combat.SUMMON_DAMAGE, id)
			_emit_fx(Combat.FX_PULSE, pos, 70.0)


func _skill_hit_weakest(dmg: int, owner: int) -> void:
	## 「最弱协议」：锁定血量比例最低的敌人并结算伤害（比例用小分母，Boss 与杂兵可比）。
	if dmg <= 0:
		return
	var best_id := 0
	var best := INF
	for eid in enemies:
		var e: Dictionary = enemies[eid]
		var ratio := float(e["hp"]) / float(maxi(1, int(e.get("max_hp", 1))))
		if ratio < best:
			best = ratio
			best_id = int(eid)
	if best_id == 0:
		return
	var target: Dictionary = enemies[best_id]
	target["hp"] = int(target["hp"]) - dmg
	_emit_fx(Combat.FX_NULL, target["pos"], 0.0)
	if int(target["hp"]) <= 0:
		_kill_enemy(best_id, owner)


func _fire_skill_shot(id: int, pos: Vector2, kind: int, c: Dictionary) -> void:
	_fire_skill_volley(id, pos, kind, c, 1, 0.0)


func _fire_skill_volley(
	id: int, pos: Vector2, kind: int, c: Dictionary, n: int, spread: float
) -> void:
	## 技能弹丸：伤害/存活时间取自指令（modifiers 已叠加），速度缺省时回退技能弹表。
	## n>1 时呈扇形散布（供「尖刺数据包」一排齐射）；n=1 时与旧行为逐位一致（零回归）。
	var dir := Combat.aim_dir(pos, _enemy_positions())
	if dir == Vector2.ZERO:
		return
	var info: Dictionary = Skills.projectile(kind)
	var speed := float(c["speed"])
	if speed <= 0.0:
		speed = float(info.get("speed", 600.0))
	var ttl := float(c["ttl"])
	if ttl <= 0.0:
		ttl = float(info.get("ttl", 1.4))
	for i in maxi(1, n):
		if projectiles.size() >= Weapons.MAX_PROJECTILES:
			break
		var d := dir.rotated((float(i) - float(n - 1) * 0.5) * spread)
		var pid := _alloc_id()
		projectiles[pid] = {
			"pos": pos,
			"vel": d * speed,
			"ttl": ttl,
			"dmg": int(c["damage"]),
			"dir": d,
			"kind": kind,
			"owner": id,
			"element": int(c["element"]),
			"elements": (c["elements"] as Array).duplicate(),
			"pierce": int(c["pierce"]),
		}


func _skill_aoe(pos: Vector2, radius: float, dmg: int, owner: int) -> void:
	## 技能范围伤害。用 enemies.keys() 快照迭代：命中结算可能连带击杀并擦除敌人。
	if dmg <= 0:
		return
	for eid in enemies.keys():
		if not enemies.has(eid):
			continue
		var e: Dictionary = enemies[int(eid)]
		if not Combat.circle_hit(pos, radius, e["pos"], Combat.enemy_radius(int(e["kind"]))):
			continue
		e["hp"] = int(e["hp"]) - dmg
		if int(e["hp"]) <= 0:
			_kill_enemy(int(eid), owner)


func _consume_bytes(id: int, n: int) -> bool:
	if n <= 0 or not players.has(id):
		return false
	var p: Dictionary = players[id]
	if int(p["bytes_owned"]) < n:
		return false
	p["bytes_owned"] = int(p["bytes_owned"]) - n
	return true


func _resolve_element(pr: Dictionary, eid: int, e: Dictionary, owner: int) -> void:
	## 弹丸元素与敌人身上残留元素的反应（蒸汽爆裂 / 超导 / 等离子），并记下本发元素。
	var elems: Array = pr.get("elements", [])
	for el in elems:
		var elem := int(el)
		if elem == Skills.ELEM_PHYS:
			continue
		var cur := int(e.get("element", Skills.ELEM_PHYS))
		if cur != Skills.ELEM_PHYS and cur != elem:
			var r := Skills.reaction(cur, elem)
			if not r.is_empty():
				e["element"] = Skills.ELEM_PHYS
				var rad := float(r["radius"])
				_emit_fx(Combat.FX_REACTION, e["pos"], rad)
				if rad <= 0.0:
					e["hp"] = int(e["hp"]) - int(r["damage"])
					if int(e["hp"]) <= 0:
						_kill_enemy(eid, owner)
				else:
					_skill_aoe(e["pos"], rad, int(r["damage"]), owner)
				return
		e["element"] = elem
		e["element_until"] = elapsed + Skills.ELEMENT_SECONDS
		_emit_fx(_element_fx(elem), e["pos"], 0.0)


func _element_fx(elem: int) -> int:
	match elem:
		Skills.ELEM_FIRE:
			return Combat.FX_BURN
		Skills.ELEM_FROST:
			return Combat.FX_FROST
		Skills.ELEM_ELEC:
			return Combat.FX_CHAIN
	return Combat.FX_HIT


func _queue_event(id: int, event: int, pos: Vector2) -> void:
	if id <= 0 or not players.has(id):
		return
	if _events.size() >= MAX_SKILL_EVENTS:
		return
	_events.append({"player": id, "event": event, "pos": pos})


func _emit_fx(kind: int, pos: Vector2, radius: float = 0.0, dir: Vector2 = Vector2.ZERO) -> void:
	## dir 仅供方向性特效（激光亮束 / 吸血连线）使用；默认零向量表示「无方向」。
	if fx_events.size() >= MAX_FX_EVENTS:
		return
	fx_events.append({"kind": kind, "pos": pos, "radius": radius, "dir": dir})

# gdlint:ignore=max-file-lines
