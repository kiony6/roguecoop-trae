extends RefCounted
## 主机权威模拟（纯逻辑，不含传输）。由 autoload Net 驱动。

const Movement := preload("res://sim/movement.gd")

var tick := 0
var snapshot_count := 0
var local_move := Vector2.ZERO
var local_buttons := 0
var players := {}  # id:int -> {pos:Vector2, move:Vector2, buttons:int}


func reset() -> void:
	tick = 0
	snapshot_count = 0
	local_move = Vector2.ZERO
	local_buttons = 0
	players = {1: _new_player()}


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


func physics_step(delta: float) -> void:
	tick += 1
	if players.has(1):
		players[1]["move"] = local_move
		players[1]["buttons"] = local_buttons
	for id in players:
		var p: Dictionary = players[id]
		p["pos"] = Movement.step(p["pos"], p["move"], delta)


func player_states() -> Array:
	var out: Array = []
	for id in peer_ids():
		out.append({"id": id, "pos": players[id]["pos"]})
	return out


func peer_ids() -> PackedInt32Array:
	var ids := PackedInt32Array()
	var keys := players.keys()
	keys.sort()
	for k in keys:
		ids.append(int(k))
	return ids


func _new_player() -> Dictionary:
	return {"pos": Vector2.ZERO, "move": Vector2.ZERO, "buttons": 0}
