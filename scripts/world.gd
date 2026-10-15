extends Node2D
## 世界场景：按 Net 广播的 world_state 渲染玩家/敌人/掉落/弹丸与房间墙体，
## 并承载 HUD / 升级 / 结算面板。不参与任何权威裁决。

const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const LootScript := preload("res://scripts/loot.gd")
const ProjectileScript := preload("res://scripts/projectile.gd")
const UpgradeMenu := preload("res://scripts/upgrade_menu.gd")
const RunOverMenu := preload("res://scripts/runover_menu.gd")
const Progression := preload("res://sim/progression.gd")
const Weapons := preload("res://sim/weapons.gd")
const Rooms := preload("res://sim/rooms.gd")

const COLORS: Array[Color] = [
	Color("4aa3ff"),
	Color("ff7a59"),
	Color("ffd93d"),
	Color("7be07b"),
]

var _player_nodes := {}
var _enemy_nodes := {}
var _loot_nodes := {}
var _proj_nodes := {}
var _level := 1
var _xp := 0
var _kills := 0
var _wave := 1
var _local_weapon := 0
var _last_pick := ""

var _upgrade_menu: Control
var _runover_menu: Control

@onready var _info: Label = $Hud/Info


func _ready() -> void:
	Net.world_state.connect(_on_world_state)
	Net.player_left.connect(_on_player_left)
	Net.upgrade_offer.connect(_on_upgrade_offer)
	Net.player_upgrade.connect(_on_player_upgrade)
	Net.run_over.connect(_on_run_over)
	Net.room_ready.connect(_on_room_ready)
	if Net.is_host():
		queue_redraw()

	_upgrade_menu = UpgradeMenu.new()
	_upgrade_menu.name = "UpgradeMenu"
	$Hud.add_child(_upgrade_menu)
	_upgrade_menu.picked.connect(_on_upgrade_picked)

	_runover_menu = RunOverMenu.new()
	_runover_menu.name = "RunOverMenu"
	$Hud.add_child(_runover_menu)
	_runover_menu.back_requested.connect(_on_back_requested)

	_update_info()


func _process(_delta: float) -> void:
	_update_info()


func _draw() -> void:
	for w in Net.room_walls():
		var r: Rect2 = w
		draw_rect(r, Color("2a3550"), true)
		draw_rect(r, Color("3d4d70"), false, 2.0)
	draw_rect(Rooms.arena_rect(), Color("5566aa"), false, 4.0)


func _on_room_ready() -> void:
	queue_redraw()


func _on_world_state(
	_tick: int, meta: Dictionary, players: Array, enemies: Array, loot: Array, projectiles: Array
) -> void:
	_level = int(meta.get("level", 1))
	_xp = int(meta.get("xp", 0))
	_kills = int(meta.get("kills", 0))
	_wave = int(meta.get("wave", 1))
	_sync_players(players)
	_sync_enemies(enemies)
	_sync_loot(loot)
	_sync_projectiles(projectiles)


func _sync_players(players: Array) -> void:
	for p in players:
		var id: int = p["id"]
		var node: Node2D = _player_nodes.get(id)
		if node == null:
			node = _spawn_player(id)
		if id == Net.local_id:
			_local_weapon = int(p.get("weapon", 0))
		node.push_authoritative(
			p["pos"],
			int(p.get("hp", 100)),
			int(p.get("status", 0)),
			int(p.get("revive01", 0)),
			int(p.get("weapon", 0))
		)


func _sync_enemies(enemies: Array) -> void:
	var alive := {}
	for e in enemies:
		var id: int = e["id"]
		alive[id] = true
		var node: Node2D = _enemy_nodes.get(id)
		if node == null:
			node = _spawn_enemy(id)
		node.push_authoritative(e["pos"], int(e.get("hp01", 255)), int(e.get("kind", 0)))
	for id in _enemy_nodes.keys():
		if not alive.has(id):
			_enemy_nodes[id].queue_free()
			_enemy_nodes.erase(id)


func _sync_loot(loot: Array) -> void:
	var alive := {}
	for l in loot:
		var id: int = l["id"]
		alive[id] = true
		var node: Node2D = _loot_nodes.get(id)
		if node == null:
			node = _spawn_loot(id, int(l.get("kind", 0)))
		node.push_authoritative(l["pos"])
	for id in _loot_nodes.keys():
		if not alive.has(id):
			_loot_nodes[id].queue_free()
			_loot_nodes.erase(id)


func _sync_projectiles(projectiles: Array) -> void:
	var alive := {}
	for pj in projectiles:
		var id: int = pj["id"]
		alive[id] = true
		var node: Node2D = _proj_nodes.get(id)
		if node == null:
			node = _spawn_projectile(id, int(pj.get("kind", 0)))
		node.push_authoritative(pj["pos"], pj["dir"], int(pj.get("kind", 0)))
	for id in _proj_nodes.keys():
		if not alive.has(id):
			_proj_nodes[id].queue_free()
			_proj_nodes.erase(id)


func _on_player_left(id: int) -> void:
	var node: Node2D = _player_nodes.get(id)
	if node != null:
		node.queue_free()
		_player_nodes.erase(id)


func _spawn_player(id: int) -> Node2D:
	var node := PlayerScript.new()
	node.name = "Player%d" % id
	node.setup(id, id == Net.local_id, COLORS[(id - 1) % COLORS.size()])
	add_child(node)
	_player_nodes[id] = node
	return node


func _spawn_enemy(id: int) -> Node2D:
	var node := EnemyScript.new()
	node.name = "Enemy%d" % id
	node.setup(id)
	add_child(node)
	_enemy_nodes[id] = node
	return node


func _spawn_loot(id: int, kind: int) -> Node2D:
	var node := LootScript.new()
	node.name = "Loot%d" % id
	node.setup(id, kind)
	add_child(node)
	_loot_nodes[id] = node
	return node


func _spawn_projectile(id: int, kind: int) -> Node2D:
	var node := ProjectileScript.new()
	node.name = "Proj%d" % id
	node.setup(id, kind)
	add_child(node)
	_proj_nodes[id] = node
	return node


# ---------------- 升级与结算 ----------------


func _on_upgrade_offer(choices: PackedInt32Array) -> void:
	if _upgrade_menu != null:
		_upgrade_menu.open(choices)


func _on_upgrade_picked(card_id: int) -> void:
	Net.send_upgrade_pick(card_id)


func _on_player_upgrade(player_id: int, card_id: int) -> void:
	var card := Progression.card_by_id(card_id)
	_last_pick = "%d 号获得 %s" % [player_id, str(card.get("name", "?"))]


func _on_run_over(won: bool, stats: Dictionary) -> void:
	# M4.4：结算面板弹出时收起尚未选完的升级卡片，避免两层 UI 叠显
	if _upgrade_menu != null:
		_upgrade_menu.visible = false
	if _runover_menu != null:
		_runover_menu.show_result(won, stats)


func _on_back_requested() -> void:
	if Net.is_client():
		Net.client_disconnect()
	elif Net.is_host():
		Net.host_stop()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _update_info() -> void:
	var role := "未连接"
	if Net.is_host():
		role = "主机 id=%d" % Net.local_id
	elif Net.is_client():
		role = "客户端 id=%d" % Net.local_id
	var pick := "" if _last_pick.is_empty() else " | %s" % _last_pick
	var wpn := " | 武器 %s" % Weapons.name_of(_local_weapon)
	_info.text = (
		"%s | 波次 %d | 等级 %d (经验 %d) | 击杀 %d | 在线 %d | 敌人 %d | 掉落 %d | 弹丸 %d%s%s"
		% [
			role,
			_wave,
			_level,
			_xp,
			_kills,
			_player_nodes.size(),
			_enemy_nodes.size(),
			_loot_nodes.size(),
			_proj_nodes.size(),
			wpn,
			pick,
		]
	)
