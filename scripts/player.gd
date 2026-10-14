extends Node2D
## 玩家表现节点。状态全部来自 Net 的 world_state 推送：
## - 主机端：一切权威直连（自己 + 远端都直接读权威位置）
## - 客户端：本地玩家「预测 + 软校正」，远端玩家「按到达时间插值」

const Interp := preload("res://net/interp.gd")
const Movement := preload("res://sim/movement.gd")

const CORRECT_RATE := 10.0   # 软校正速率
const SNAP_DIST := 140.0     # 误差超过该距离直接硬吸附
const RADIUS := 14.0

var player_id := 0
var is_local := false
var color := Color.WHITE

var _interp := Interp.new()
var _auth := Vector2.ZERO
var _has_auth := false
var _predicted := Vector2.ZERO


func setup(id: int, local: bool, c: Color) -> void:
	player_id = id
	is_local = local
	color = c
	_predicted = position
	z_index = 1 if local else 0
	queue_redraw()


func push_authoritative(pos: Vector2) -> void:
	if not _has_auth:
		_has_auth = true
		_auth = pos
		_predicted = pos
		position = pos
	_auth = pos
	_interp.push(pos, float(Time.get_ticks_msec()))


func _physics_process(delta: float) -> void:
	if not _has_auth:
		return
	if is_local and Net.is_client():
		_local_tick(delta)
	elif Net.is_client():
		position = _interp.sample(float(Time.get_ticks_msec()))
	else:
		position = _auth


func _local_tick(delta: float) -> void:
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_predicted = Movement.step(_predicted, move, delta)
	Net.send_local_input(move, _read_buttons())

	var err := _auth - _predicted
	if err.length() > SNAP_DIST:
		_predicted = _auth
	else:
		_predicted += err * (1.0 - exp(-CORRECT_RATE * delta))
	position = _predicted


func _read_buttons() -> int:
	var b := 0
	if Input.is_action_pressed("fire"):
		b |= 1
	if Input.is_action_pressed("dash"):
		b |= 2
	return b


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, color)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 24, color.darkened(0.35), 2.0)
	if is_local:
		draw_arc(Vector2.ZERO, RADIUS + 4.0, 0.0, TAU, 24, color.lightened(0.4), 1.0)
