extends Node2D
## 掉落物表现节点。位置随快照更新（不做插值，掉落物会磁吸移动）。M3：按 kind 区分外观。

const Combat := preload("res://sim/combat.gd")

var loot_id := 0
var kind := 0


func setup(id: int, k: int) -> void:
	loot_id = id
	kind = k
	z_index = -1
	queue_redraw()


func push_authoritative(pos: Vector2) -> void:
	position = pos


func _draw() -> void:
	match kind:
		Combat.LOOT_KIND_BIG:
			_draw_gem(9.0, Color("ffd93d"))
		Combat.LOOT_KIND_BYTE:
			_draw_byte()
		_:
			_draw_gem(6.0, Color("7be07b"))


func _draw_gem(r: float, col: Color) -> void:
	var pts := PackedVector2Array(
		[Vector2(0.0, -r), Vector2(r, 0.0), Vector2(0.0, r), Vector2(-r, 0.0)]
	)
	draw_colored_polygon(pts, col)


func _draw_byte() -> void:
	## 字节币：蓝色方块 + 中心字节刻度（技能节点的资源型掉落，与经验碎片区分）。
	var r := 7.0
	_draw_gem(r, Color("4aa3ff"))
	draw_rect(Rect2(-r * 0.5, -r * 0.5, r, r), Color("ffd93d"), false, 1.0)
	draw_line(Vector2(-r * 0.5, 0.0), Vector2(r * 0.5, 0.0), Color("0e1524"), 2.0)
