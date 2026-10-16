extends Node2D
## 敌人表现节点。客户端按到达时间插值，主机直连权威位置。M3：Boss 差异化绘制。

const Interp := preload("res://net/interp.gd")
const Combat := preload("res://sim/combat.gd")
const Skills := preload("res://sim/skills.gd")

const ELEM_COLORS := {
	Skills.ELEM_FIRE: Color("ff6a2a"),
	Skills.ELEM_FROST: Color("9fe8ff"),
	Skills.ELEM_ELEC: Color("b06bff"),
}

var enemy_id := 0
var kind := Combat.ENEMY_KIND_NORMAL

var _interp := Interp.new()
var _auth := Vector2.ZERO
var _has_auth := false
var _hp01 := 255
var _elem := Skills.ELEM_PHYS


func setup(id: int) -> void:
	enemy_id = id
	z_index = 0
	queue_redraw()


func push_authoritative(pos: Vector2, hp01: int, kind_in: int) -> void:
	if not _has_auth:
		_has_auth = true
		_auth = pos
		position = pos
	_auth = pos
	_hp01 = hp01
	kind = kind_in
	_interp.push(pos, float(Time.get_ticks_msec()))
	queue_redraw()


func set_element(e: int) -> void:
	## 元素状态由独立稀疏通道下发；相同值不重绘，避免每快照无谓刷新。
	if e == _elem:
		return
	_elem = e
	queue_redraw()


func _physics_process(_delta: float) -> void:
	if not _has_auth:
		return
	if Net.is_client():
		_interp.delay_ms = Net.interp_delay_ms()
		position = _interp.sample(float(Time.get_ticks_msec()))
	else:
		position = _auth


func _draw() -> void:
	var radius := Combat.enemy_radius(kind)
	var frac := clampf(float(_hp01) / 255.0, 0.0, 1.0)
	var t := 1.0 - frac
	var base := Color("6a3bb2") if kind == Combat.ENEMY_KIND_BOSS else Color("b23b3b")
	var col := base.lerp(Color("ff8080"), t)
	draw_circle(Vector2.ZERO, radius, col)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, col.darkened(0.4), 2.0)
	if kind == Combat.ENEMY_KIND_BOSS:
		draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 32, Color("e0b0ff"), 2.0)
	if ELEM_COLORS.has(_elem):
		draw_arc(Vector2.ZERO, radius + 2.5, 0.0, TAU, 28, ELEM_COLORS[_elem], 2.5)
	var w := radius * 1.7
	draw_rect(Rect2(-w * 0.5, -radius - 9.0, w, 3.0), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(-w * 0.5, -radius - 9.0, w * frac, 3.0), Color("ffd93d"))
