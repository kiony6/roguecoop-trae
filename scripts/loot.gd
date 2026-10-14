extends Node2D
## 掉落物表现节点。位置随快照更新（M2 不做插值，掉落物会磁吸移动）。

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
	var pts := PackedVector2Array(
		[Vector2(0.0, -6.0), Vector2(6.0, 0.0), Vector2(0.0, 6.0), Vector2(-6.0, 0.0)]
	)
	draw_colored_polygon(pts, Color("7be07b"))
