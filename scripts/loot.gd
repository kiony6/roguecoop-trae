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
	var big := kind == Combat.LOOT_KIND_BIG
	var r := 9.0 if big else 6.0
	var col := Color("ffd93d") if big else Color("7be07b")
	var pts := PackedVector2Array(
		[Vector2(0.0, -r), Vector2(r, 0.0), Vector2(0.0, r), Vector2(-r, 0.0)]
	)
	draw_colored_polygon(pts, col)
