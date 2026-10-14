extends Node2D
## 世界场景：只负责按 Net 广播的 world_state 渲染玩家，不参与任何权威裁决。

const PlayerScript := preload("res://scripts/player.gd")

const COLORS: Array[Color] = [
	Color("4aa3ff"), Color("ff7a59"), Color("ffd93d"), Color("7be07b"),
]

@onready var _info: Label = $Hud/Info

var _nodes := {}


func _ready() -> void:
	Net.world_state.connect(_on_world_state)
	Net.player_left.connect(_on_player_left)
	_update_info()


func _process(_delta: float) -> void:
	_update_info()


func _on_world_state(_tick: int, players: Array) -> void:
	for p in players:
		var id: int = p["id"]
		var node: Node2D = _nodes.get(id)
		if node == null:
			node = _spawn(id)
		node.push_authoritative(p["pos"])


func _on_player_left(id: int) -> void:
	var node: Node2D = _nodes.get(id)
	if node != null:
		node.queue_free()
		_nodes.erase(id)


func _spawn(id: int) -> Node2D:
	var node := PlayerScript.new()
	node.name = "Player%d" % id
	node.setup(id, id == Net.local_id, COLORS[(id - 1) % COLORS.size()])
	add_child(node)
	_nodes[id] = node
	return node


func _update_info() -> void:
	var role := "未连接"
	if Net.is_host():
		role = "主机 id=%d" % Net.local_id
	elif Net.is_client():
		role = "客户端 id=%d" % Net.local_id
	_info.text = "%s | 在线 %d 人 | WASD 移动" % [role, _nodes.size()]
