extends Node2D
## 弹丸表现节点（M4）。弹丸速度快，客户端用「最近权威位置 + 方向」航位推算，
## 避免插值带来的明显滞后；主机直连权威位置。

const Weapons := preload("res://sim/weapons.gd")
const Skills := preload("res://sim/skills.gd")

const SKILL_COLORS := {
	Skills.PROJ_DATA: Color("4aa3ff"),  # 数据弹
	Skills.PROJ_LASER: Color("a8e0ff"),  # 激光
	Skills.PROJ_SPLIT: Color("ffd93d"),  # 分叉弹
	Skills.PROJ_HOMING: Color("ff8a3d"),  # 追踪导弹
	Skills.PROJ_MINE: Color("b06bff"),  # 数据雷
	Skills.PROJ_SPIKE: Color("9fe8ff"),  # 尖刺弹
}

var proj_id := 0
var kind := 0

var _auth := Vector2.ZERO
var _dir := Vector2.RIGHT
var _recv_ms := 0.0
var _has_auth := false


func setup(id: int, k: int) -> void:
	proj_id = id
	kind = k
	z_index = -2
	queue_redraw()


func push_authoritative(pos: Vector2, dir: Vector2, k: int) -> void:
	_auth = pos
	if dir.length() > 0.0001:
		_dir = dir
	kind = k
	_recv_ms = float(Time.get_ticks_msec())
	if not _has_auth:
		_has_auth = true
		position = pos
	queue_redraw()


func _physics_process(_delta: float) -> void:
	if not _has_auth:
		return
	# M4.5：本局结算后权威位置被冻结，若继续航位推算，
	# 每帧自推进都会被下一帧快照拽回，表现为弹丸抽搐
	if Net.is_run_over():
		position = _auth
		return
	if Net.is_client():
		var dt := (float(Time.get_ticks_msec()) - _recv_ms) / 1000.0
		position = _auth + _dir.normalized() * _speed() * dt
	else:
		position = _auth


func _speed() -> float:
	## 技能弹（kind 8+）走技能弹表，武器弹回退 Weapons。
	var info := Skills.projectile(kind)
	if not info.is_empty():
		return float(info["speed"])
	return Weapons.speed(kind)


func _draw() -> void:
	var r := Skills.projectile_radius(kind)
	var col := _color()
	draw_circle(Vector2.ZERO, r, col)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 16, col.darkened(0.4), 1.5)
	if kind >= Skills.PROJ_DATA:
		# 技能弹加一段拖尾，与武器弹区分开
		draw_line(Vector2.ZERO, -_dir.normalized() * r * 2.2, Color(col, 0.45), r * 1.2)


func _color() -> Color:
	if kind == Weapons.KIND_SHOTGUN:
		return Color("ffe9a8")
	if kind == Weapons.KIND_RIFLE:
		return Color("ffd0f0")
	return SKILL_COLORS.get(kind, Color("a8e0ff"))
