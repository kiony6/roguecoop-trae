extends Node2D
## 世界场景：只负责按 Net 广播的 world_state 渲染玩家/敌人/掉落，不参与任何权威裁决。

const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const LootScript := preload("res://scripts/loot.gd")

const COLORS: Array[Color] = [
	Color("4aa3ff"),
	Color("ff7a59"),
	Color("ffd93d"),
	Color("7be07b"),
]

var _player_nodes := {}
var _enemy_nodes := {}
var _loot_nodes := {}

@onready var _info: Label = $Hud/Info


func _ready() -> void:
	Net.world_state.connect(_on_world_state)
	Net.player_left.connect(_on_player_left)
	_update_info()


func _process(_delta: float) -> void:
	_update_info()


func _on_world_state(_tick: int, players: Array, enemies: Array, loot: Array) -> void:
	_sync_players(players)
	_sync_enemies(enemies)
	_sync_loot(loot)


func _sync_players(players: Array) -> void:
	for p in players:
		var id: int = p["id"]
		var node: Node2D = _player_nodes.get(id)
		if node == null:
			node = _spawn_player(id)
		node.push_authoritative(p["pos"], int(p.get("hp", 100)))


func _sync_enemies(enemies: Array) -> void:
	var alive := {}
	for e in enemies:
		var id: int = e["id"]
		alive[id] = true
		var node: Node2D = _enemy_nodes.get(id)
		if node == null:
			node = _spawn_enemy(id)
		node.push_authoritative(e["pos"], int(e.get("hp", 0)))
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


func _update_info() -> void:
	var role := "未连接"
	if Net.is_host():
		role = "主机 id=%d" % Net.local_id
	elif Net.is_client():
		role = "客户端 id=%d" % Net.local_id
	_info.text = (
		"%s | 在线 %d 人 | 敌人 %d | 掉落 %d | J 键射击"
		% [role, _player_nodes.size(), _enemy_nodes.size(), _loot_nodes.size()]
	)
