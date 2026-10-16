extends Node2D
## 单个动态特效节点（子项目 5）：纯 _draw 自绘、生命周期结束后自毁。
## 20 种 kind 与 Combat.FX_* 一一对应；颜色取自「甲·夜幕蓝」世界色系。

const Combat := preload("res://sim/combat.gd")

const BLUE := Color("4aa3ff")
const GOLD := Color("ffd93d")
const RED := Color("b23b3b")
const VIOLET := Color("b06bff")
const ICE := Color("9fe8ff")
const EMBER := Color("ff8a3d")
const SHIELD_C := Color("7be0c0")

var kind := 0
var dir := Vector2.RIGHT
var radius := 0.0
var duration := 0.3

var _age := 0.0


func setup(k: int, pos: Vector2, d: Vector2, r: float, dur: float) -> void:
	kind = k
	position = pos
	if d.length() > 0.0001:
		dir = d.normalized()
	radius = r
	duration = maxf(dur, 0.05)
	z_index = 3
	queue_redraw()


func _process(delta: float) -> void:
	_age += delta
	queue_redraw()
	if _age >= duration:
		queue_free()


func _draw() -> void:
	var t := clampf(_age / duration, 0.0, 1.0)
	var fade := 1.0 - t
	match kind:
		Combat.FX_HIT:
			_draw_hit(t, fade)
		Combat.FX_CHAIN:
			_draw_chain(t, fade)
		Combat.FX_BURST:
			_draw_ring(t, fade, radius if radius > 0.0 else 60.0, RED)
		Combat.FX_PULSE:
			_draw_pulse(t, fade)
		Combat.FX_NUKE:
			_draw_nuke(t, fade)
		Combat.FX_LASER:
			_draw_laser(t, fade)
		Combat.FX_FROST:
			_draw_frost(t, fade)
		Combat.FX_BURN:
			_draw_burn(t, fade)
		Combat.FX_SHIELD:
			_draw_shield(t, fade)
		Combat.FX_DRAIN:
			_draw_drain(t, fade)
		Combat.FX_COIN:
			_draw_coin(t, fade)
		Combat.FX_LEVELUP:
			_draw_levelup(t, fade)
		Combat.FX_REACTION:
			_draw_reaction(t, fade)
		Combat.FX_SPIKE:
			_draw_spike(t, fade)
		Combat.FX_CHIP:
			_draw_chip(t, fade)
		Combat.FX_BUG:
			_draw_bug(t, fade)
		Combat.FX_NULL:
			_draw_null(t, fade)
		Combat.FX_SPIN:
			_draw_spin(t, fade)
		Combat.FX_GIGA:
			_draw_giga(t, fade)
		Combat.FX_FAULT:
			_draw_fault(t, fade)


func _draw_hit(t: float, fade: float) -> void:
	var r := 6.0 + 10.0 * t
	var c := GOLD
	c.a = fade
	for i in 4:
		var a := float(i) * TAU / 4.0 + t
		var p := Vector2.RIGHT.rotated(a) * r
		draw_line(Vector2.ZERO, p, c, 2.0)


func _draw_chain(t: float, fade: float) -> void:
	var c := BLUE
	c.a = fade
	var pts := PackedVector2Array()
	var n := 7
	var span := 26.0
	for i in n:
		var f := float(i) / float(n - 1)
		var wobble := sin(f * 6.0 + t * 8.0) * 6.0
		pts.append(Vector2(-span * 0.5 + span * f, wobble))
	draw_polyline(pts, c, 2.0)


func _draw_ring(t: float, fade: float, base: float, col: Color) -> void:
	var c := col
	c.a = fade * 0.9
	var r := base * (0.4 + 0.6 * t)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, c, 2.5)
	var fill := col
	fill.a = fade * 0.25
	draw_circle(Vector2.ZERO, r, fill)


func _draw_pulse(t: float, fade: float) -> void:
	var base := radius if radius > 0.0 else 300.0
	for i in 3:
		var off := float(i) / 3.0
		var local := clampf(t - off, 0.0, 1.0)
		if local <= 0.0:
			continue
		var c := BLUE
		c.a = (1.0 - local) * fade
		draw_arc(Vector2.ZERO, base * local, 0.0, TAU, 40, c, 2.0)


func _draw_nuke(t: float, fade: float) -> void:
	var base := radius if radius > 0.0 else 220.0
	var flash := Color(1, 1, 1, fade * 0.5)
	draw_circle(Vector2.ZERO, base * 0.25 * (1.0 - t), flash)
	_draw_ring(t, fade, base, GOLD)


func _draw_laser(t: float, fade: float) -> void:
	var length := radius if radius > 0.0 else 240.0
	var c := BLUE
	c.a = fade
	var w := 6.0 * fade * (1.0 - 0.4 * t)
	var end := dir * length
	draw_line(-end * 0.4, end, c, w)
	var core := Color(1, 1, 1, fade * 0.8)
	draw_line(-end * 0.4, end, core, w * 0.35)


func _draw_frost(t: float, fade: float) -> void:
	var c := ICE
	c.a = fade
	var spread := 0.5
	var r := 16.0 + 10.0 * t
	var pts := PackedVector2Array([Vector2.ZERO])
	for i in 5:
		pts.append(Vector2.RIGHT.rotated(-spread + spread * 2.0 * float(i) / 4.0) * r)
	draw_colored_polygon(pts, c)


func _draw_burn(t: float, fade: float) -> void:
	var c := EMBER
	c.a = fade
	for i in 3:
		var h := (12.0 + 6.0 * float(i)) * (1.0 - 0.4 * t)
		var x := (float(i) - 1.0) * 6.0
		draw_line(Vector2(x, 4.0), Vector2(x + sin(t * 6.0 + float(i)) * 3.0, -h), c, 2.0)


func _draw_shield(t: float, fade: float) -> void:
	var c := SHIELD_C
	c.a = fade
	var r := 22.0
	var pts := PackedVector2Array()
	for i in 7:
		pts.append(Vector2.RIGHT.rotated(TAU * float(i) / 6.0) * r)
	draw_polyline(pts, c, 2.0)
	draw_arc(Vector2.ZERO, r * (0.6 + 0.4 * t), 0.0, TAU, 24, c, 1.0)


func _draw_drain(t: float, fade: float) -> void:
	var length := radius if radius > 0.0 else 140.0
	var c := VIOLET
	c.a = fade
	var end := dir * length
	draw_line(Vector2.ZERO, end, c, 2.0)
	for i in 4:
		var f := float(i) / 3.0
		var p := end.lerp(Vector2.ZERO, f * 0.8 + t * 0.2)
		draw_circle(p, 2.5, c)


func _draw_coin(t: float, fade: float) -> void:
	var c := GOLD
	c.a = fade
	var r := 7.0
	var pts := PackedVector2Array(
		[Vector2(0.0, -r), Vector2(r, 0.0), Vector2(0.0, r), Vector2(-r, 0.0)]
	)
	var grow := 0.6 + 0.4 * (1.0 - t)
	draw_colored_polygon(pts, c)
	draw_arc(Vector2.ZERO, r * grow, 0.0, TAU, 16, GOLD.darkened(0.3), 1.0)


func _draw_levelup(t: float, fade: float) -> void:
	var c := GOLD
	c.a = fade
	var w := 10.0
	var h := 70.0 * (1.0 - 0.3 * t)
	draw_rect(Rect2(-w * 0.5, -h, w, h), c, false)
	var fill := GOLD
	fill.a = fade * 0.2
	draw_rect(Rect2(-w * 0.5, -h, w, h), fill, true)


func _draw_reaction(t: float, fade: float) -> void:
	var base := radius if radius > 0.0 else 90.0
	_draw_ring(t, fade, base, VIOLET)
	var c := Color(1, 1, 1, fade)
	for i in 6:
		var a := TAU * float(i) / 6.0
		draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(a) * base * 0.6 * (0.5 + t), c, 2.0)


func _draw_spike(t: float, fade: float) -> void:
	## 尖刺锥：一排窄长尖刺沿方向扇形张开。
	var c := ICE
	c.a = fade
	var n := 5
	for i in n:
		var a := (float(i) / float(n - 1) - 0.5) * 0.9
		draw_line(Vector2.ZERO, dir.rotated(a) * (22.0 + 16.0 * t), c, 3.0 * fade)


func _draw_chip(t: float, fade: float) -> void:
	## 芯片方格：逐渐张开的电路板边框 + 四只触角。
	var base := radius if radius > 0.0 else 45.0
	var c := BLUE
	c.a = fade * 0.9
	var s := base * (0.5 + 0.5 * t)
	draw_rect(Rect2(-s, -s, s * 2.0, s * 2.0), c, false, 2.0)
	for i in 4:
		var d := Vector2.RIGHT.rotated(TAU * float(i) / 4.0 + PI * 0.25)
		draw_line(d * s, d * (s * 1.35), c, 1.5)


func _draw_bug(t: float, fade: float) -> void:
	## BUG 腐蚀泡：三颗带缺口的泡向外鼓起。
	var base := radius if radius > 0.0 else 70.0
	var c := VIOLET
	c.a = fade * 0.8
	for i in 3:
		var p := Vector2.RIGHT.rotated(TAU * float(i) / 3.0 + t * 2.0) * base * (0.3 + 0.6 * t)
		draw_arc(p, 8.0 + 6.0 * (1.0 - t), 0.0, TAU * 0.75, 12, c, 2.0)


func _draw_null(t: float, fade: float) -> void:
	## 空指针：十字镖炸开。
	var r := 18.0 + 26.0 * t
	var c := RED
	c.a = fade
	draw_line(Vector2(-r, 0.0), Vector2(r, 0.0), c, 3.0)
	draw_line(Vector2(0.0, -r), Vector2(0.0, r), c, 3.0)
	draw_circle(Vector2.ZERO, 5.0 * (1.0 - t), Color(1, 1, 1, fade * 0.6))


func _draw_spin(t: float, fade: float) -> void:
	## 旋转数据包：6 个小方块沿轨道旋转。
	var base := radius if radius > 0.0 else 130.0
	var c := GOLD
	c.a = fade
	for i in 6:
		var p := Vector2.RIGHT.rotated(TAU * float(i) / 6.0 + t * 4.0) * base * 0.7
		draw_rect(Rect2(p - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), c, true)


func _draw_giga(t: float, fade: float) -> void:
	## 千兆攻：双环冲击 + 中心亮点。
	var base := radius if radius > 0.0 else 260.0
	_draw_ring(t, fade, base, BLUE)
	_draw_ring(t, fade * 0.7, base * 0.55, GOLD)
	draw_circle(Vector2.ZERO, base * 0.06 * (1.0 - t), Color(1, 1, 1, fade * 0.7))


func _draw_fault(t: float, fade: float) -> void:
	## 测试故障：全屏水平扫描线上下扫过。
	var span := radius if radius > 0.0 else 400.0
	var c := RED
	c.a = fade * 0.7
	for i in 5:
		var y := (float(i) / 4.0 - 0.5) * span * 0.5 + sin(t * 6.0 + float(i)) * 6.0
		draw_line(Vector2(-span * 0.5, y), Vector2(span * 0.5, y), c, 2.0)
