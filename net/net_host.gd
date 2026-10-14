extends RefCounted
## 主机权威模拟（纯逻辑，不含传输）。由 autoload Net 驱动。
## M2：在 M1 移动之上叠加敌人 AI、开火/命中裁决、掉落与磁吸拾取。

const Movement := preload("res://sim/movement.gd")
const Combat := preload("res://sim/combat.gd")
const EnemyAI := preload("res://sim/enemy_ai.gd")

var tick := 0
var snapshot_count := 0
var local_move := Vector2.ZERO
var local_buttons := 0
var spawn_interval := Combat.SPAWN_INTERVAL
var players := {}  # id -> {pos, move, buttons, hp, fire_cd, touch_cd, pickups}
var enemies := {}  # id -> {pos, hp, touch_cd}
var loot := {}  # id -> {pos, kind}
var projectiles := {}  # id -> {pos, vel, ttl}

var _next_id := 1
var _spawn_accum := 0.0
var _rng := RandomNumberGenerator.new()


func reset() -> void:
	tick = 0
	snapshot_count = 0
	local_move = Vector2.ZERO
	local_buttons = 0
	spawn_interval = Combat.SPAWN_INTERVAL
	players = {1: _new_player()}
	enemies = {}
	loot = {}
	projectiles = {}
	_next_id = 1
	_spawn_accum = 0.0
	_rng.seed = 20261015


func add_player(id: int) -> void:
	players[id] = _new_player()


func remove_player(id: int) -> void:
	players.erase(id)


func has_player(id: int) -> bool:
	return players.has(id)


func set_remote_input(id: int, move: Vector2, buttons: int) -> void:
	if players.has(id):
		players[id]["move"] = move
		players[id]["buttons"] = buttons


func spawn_enemy(pos: Vector2) -> int:
	var eid := _alloc_id()
	enemies[eid] = {"pos": pos, "hp": Combat.ENEMY_MAX_HP, "touch_cd": 0.0}
	return eid


func physics_step(delta: float) -> void:
	tick += 1
	if players.has(1):
		players[1]["move"] = local_move
		players[1]["buttons"] = local_buttons
	_step_players(delta)
	_step_firing()
	_step_projectiles(delta)
	_step_enemies(delta)
	_step_loot(delta)
	_step_spawner(delta)


func player_states() -> Array:
	var out: Array = []
	for id in peer_ids():
		out.append({"id": id, "pos": players[id]["pos"], "hp": players[id]["hp"]})
	return out


func enemy_states() -> Array:
	var out: Array = []
	for id in enemies:
		out.append({"id": id, "pos": enemies[id]["pos"], "hp": enemies[id]["hp"]})
	return out


func loot_states() -> Array:
	var out: Array = []
	for id in loot:
		out.append({"id": id, "pos": loot[id]["pos"], "kind": loot[id]["kind"]})
	return out


func peer_ids() -> PackedInt32Array:
	var ids := PackedInt32Array()
	var keys := players.keys()
	keys.sort()
	for k in keys:
		ids.append(int(k))
	return ids


# ---------------- 内部步进 ----------------


func _step_players(delta: float) -> void:
	for id in players:
		var p: Dictionary = players[id]
		p["pos"] = Movement.step(p["pos"], p["move"], delta)
		p["fire_cd"] = maxf(0.0, p["fire_cd"] - delta)
		p["touch_cd"] = maxf(0.0, p["touch_cd"] - delta)


func _step_firing() -> void:
	var targets := enemy_states()
	for id in players:
		var p: Dictionary = players[id]
		if (p["buttons"] & 1) == 0:
			continue
		if p["fire_cd"] > 0.0:
			continue
		var dir := Combat.aim_dir(p["pos"], targets)
		if dir == Vector2.ZERO:
			continue
		p["fire_cd"] = Combat.FIRE_COOLDOWN
		_spawn_projectile(p["pos"], dir)


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
		for eid in enemies:
			var e: Dictionary = enemies[eid]
			var hit := Combat.circle_hit(
				pr["pos"], Combat.PROJECTILE_RADIUS, e["pos"], Combat.ENEMY_RADIUS
			)
			if not hit:
				continue
			e["hp"] -= Combat.PROJECTILE_DAMAGE
			expired.append(pid)
			if e["hp"] <= 0:
				killed.append(eid)
			break
	for pid in expired:
		projectiles.erase(pid)
	for eid in killed:
		_kill_enemy(eid)


func _step_enemies(delta: float) -> void:
	var targets := player_states()
	for eid in enemies:
		var e: Dictionary = enemies[eid]
		var dir := EnemyAI.chase_dir(e["pos"], targets)
		e["pos"] = EnemyAI.step(e["pos"], dir, delta)
		e["touch_cd"] = maxf(0.0, e["touch_cd"] - delta)
		if e["touch_cd"] > 0.0:
			continue
		for id in players:
			var p: Dictionary = players[id]
			var touching := Combat.circle_hit(
				e["pos"], Combat.ENEMY_RADIUS, p["pos"], Combat.PLAYER_RADIUS
			)
			if not touching:
				continue
			p["hp"] = maxi(0, p["hp"] - Combat.ENEMY_TOUCH_DAMAGE)
			e["touch_cd"] = Combat.ENEMY_TOUCH_INTERVAL
			break


func _step_loot(delta: float) -> void:
	var picked: Array = []
	for lid in loot:
		var l: Dictionary = loot[lid]
		var owner := _nearest_player_id(l["pos"])
		if owner == 0:
			continue
		var to_player: Vector2 = players[owner]["pos"] - l["pos"]
		var d := to_player.length()
		if d <= Combat.PICKUP_RADIUS:
			players[owner]["pickups"] += 1
			picked.append(lid)
		elif d <= Combat.LOOT_MAGNET_RADIUS:
			l["pos"] = l["pos"] + to_player.normalized() * Combat.LOOT_MAGNET_SPEED * delta
	for lid in picked:
		loot.erase(lid)


func _step_spawner(delta: float) -> void:
	_spawn_accum += delta
	if _spawn_accum < spawn_interval:
		return
	_spawn_accum = 0.0
	if enemies.size() >= Combat.MAX_ENEMIES:
		return
	var ids := players.keys()
	if ids.is_empty():
		return
	var anchor: Vector2 = players[ids[_rng.randi_range(0, ids.size() - 1)]]["pos"]
	var angle := _rng.randf_range(0.0, TAU)
	spawn_enemy(anchor + Vector2.RIGHT.rotated(angle) * Combat.SPAWN_RADIUS)


func _spawn_projectile(pos: Vector2, dir: Vector2) -> void:
	var pid := _alloc_id()
	projectiles[pid] = {
		"pos": pos,
		"vel": dir * Combat.PROJECTILE_SPEED,
		"ttl": Combat.PROJECTILE_TTL,
	}


func _kill_enemy(eid: int) -> void:
	if not enemies.has(eid):
		return
	var pos: Vector2 = enemies[eid]["pos"]
	enemies.erase(eid)
	var lid := _alloc_id()
	loot[lid] = {"pos": pos, "kind": 0}


func _nearest_player_id(pos: Vector2) -> int:
	var best := 0
	var best_d := INF
	for id in players:
		var d: float = players[id]["pos"].distance_to(pos)
		if d < best_d:
			best_d = d
			best = id
	return best


func _alloc_id() -> int:
	_next_id += 1
	return _next_id


func _new_player() -> Dictionary:
	return {
		"pos": Vector2.ZERO,
		"move": Vector2.ZERO,
		"buttons": 0,
		"hp": Combat.PLAYER_MAX_HP,
		"fire_cd": 0.0,
		"touch_cd": 0.0,
		"pickups": 0,
	}
