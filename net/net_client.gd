extends RefCounted
## 客户端状态（纯逻辑，不含传输）。由 autoload Net 驱动。

var tick := 0
var last_snapshot_tick := 0
var last_meta: Dictionary = {}
var last_players: Array = []
var pending_move := Vector2.ZERO
var pending_buttons := 0
var run_over := false
var room_walls: Array = []


func reset() -> void:
	tick = 0
	last_snapshot_tick = 0
	last_meta = {}
	last_players = []
	pending_move = Vector2.ZERO
	pending_buttons = 0
	run_over = false
	room_walls = []
