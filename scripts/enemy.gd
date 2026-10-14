extends Node2D
## 敌人表现节点。客户端按到达时间插值，主机直连权威位置。

const Interp := preload("res://net/interp.gd")
const Combat := preload("res://sim/combat.gd")

var enemy_id := 0

var _interp := Interp.new()
var _auth := Vector2.ZERO
var _has_auth := false
var _hp := Combat.ENEMY_MAX_HP


func setup(id: int) -> void:
	enemy_id = id
	z_index = 0
	queue_redraw()


func push_authoritative(pos: Vector2, hp: int) -> void:
	if not _has_auth:
		_has_auth = true
		_auth = pos
		position = pos
	_auth = pos
	_hp = hp
	_interp.push(pos, float(Time.get_ticks_msec()))
	queue_redraw()


func _physics_process(_delta: float) -> void:
	if not _has_auth:
		return
	if Net.is_client():
		position = _interp.sample(float(Time.get_ticks_msec()))
	else:
		position = _auth


func _draw() -> void:
	var t := clampf(1.0 - float(_hp) / float(Combat.ENEMY_MAX_HP), 0.0, 1.0)
	var col := Color("b23b3b").lerp(Color("ff8080"), t)
	draw_circle(Vector2.ZERO, Combat.ENEMY_RADIUS, col)
	draw_arc(Vector2.ZERO, Combat.ENEMY_RADIUS, 0.0, TAU, 20, col.darkened(0.4), 2.0)
	# 血条
	draw_rect(Rect2(-12.0, -Combat.ENEMY_RADIUS - 9.0, 24.0, 3.0), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(-12.0, -Combat.ENEMY_RADIUS - 9.0, 24.0 * t, 3.0), Color("ffd93d"))
