extends Node2D
## 玩家表现节点。状态全部来自 Net 的 world_state 推送：
## - 主机端：一切权威直连（自己 + 远端都直接读权威位置）
## - 客户端：本地玩家「预测 + 软校正」，远端玩家「按到达时间插值」
## M3 保留倒地/阵亡表现与救援进度环；M4 新增武器枪管与墙体碰撞预测。

const Interp := preload("res://net/interp.gd")
const Movement := preload("res://sim/movement.gd")
const Combat := preload("res://sim/combat.gd")
const Weapons := preload("res://sim/weapons.gd")

const CORRECT_RATE := 10.0  # 软校正速率
const SNAP_DIST := 140.0  # 误差超过该距离直接硬吸附
const RADIUS := 14.0

var player_id := 0
var is_local := false
var color := Color.WHITE
var hp := Combat.PLAYER_MAX_HP
var status := Combat.PLAYER_ALIVE
var revive01 := 0
var weapon := 0

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


func push_authoritative(
	pos: Vector2, hp_in: int, status_in: int, revive_in: int, weapon_in: int
) -> void:
	if not _has_auth:
		_has_auth = true
		_auth = pos
		_predicted = pos
		position = pos
	_auth = pos
	hp = hp_in
	status = status_in
	revive01 = revive_in
	weapon = weapon_in
	_interp.push(pos, float(Time.get_ticks_msec()))
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not _has_auth:
		return
	# 倒地/阵亡、或本局已结算：不再预测，直接贴权威位置
	# （M4.5：结算后若继续预测，客户端会与冻结的权威位置互相拉扯，表现为抽搐）
	if status != Combat.PLAYER_ALIVE or Net.is_run_over():
		position = _auth
		return
	if is_local and Net.is_client():
		_local_tick(delta)
	elif Net.is_client():
		_interp.delay_ms = Net.interp_delay_ms()
		position = _interp.sample(float(Time.get_ticks_msec()))
	else:
		position = _auth


func _local_tick(delta: float) -> void:
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_predicted = Movement.step(_predicted, move, delta, Movement.SPEED, Net.room_walls())
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
	if status == Combat.PLAYER_DEAD:
		draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 20, color.darkened(0.6), 2.0)
		return
	var body := color
	if status == Combat.PLAYER_DOWNED:
		body = color.darkened(0.55)
	draw_circle(Vector2.ZERO, RADIUS, body)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 24, body.darkened(0.35), 2.0)
	if is_local:
		draw_arc(Vector2.ZERO, RADIUS + 4.0, 0.0, TAU, 24, color.lightened(0.4), 1.0)
	_draw_weapon()
	if status == Combat.PLAYER_DOWNED:
		# 救援进度环（顺时针，进度越满越接近救起）
		var p := float(revive01) / 255.0
		draw_arc(
			Vector2.ZERO, RADIUS + 7.0, -PI * 0.5, -PI * 0.5 + TAU * p, 32, Color("7be07b"), 3.0
		)
		return
	var ratio := clampf(float(hp) / float(Combat.PLAYER_MAX_HP), 0.0, 1.0)
	draw_rect(Rect2(-14.0, -RADIUS - 9.0, 28.0, 3.0), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(-14.0, -RADIUS - 9.0, 28.0 * ratio, 3.0), Color("7be07b"))


func _draw_weapon() -> void:
	# 枪管按武器着色，便于一眼分辨当前武器
	var col := Color("a8e0ff")
	if weapon == Weapons.KIND_SHOTGUN:
		col = Color("ffe9a8")
	elif weapon == Weapons.KIND_RIFLE:
		col = Color("ffd0f0")
	draw_rect(Rect2(4.0, -2.0, 11.0, 4.0), col)
