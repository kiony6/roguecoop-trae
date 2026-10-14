extends Control
## 结算面板（M3）：胜利/失败 + 统计 + 返回主菜单。

signal back_requested


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func show_result(won: bool, stats: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	visible = true

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.75)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var box := VBoxContainer.new()
	box.position = Vector2(420.0, 220.0)
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var title := Label.new()
	title.text = "胜利！" if won else "全员阵亡……"
	box.add_child(title)

	var info := Label.new()
	info.text = (
		"存活 %.1f 秒 | 击杀 %d | 等级 %d | 击败 Boss %d"
		% [
			float(stats.get("seconds", 0.0)),
			int(stats.get("kills", 0)),
			int(stats.get("level", 1)),
			int(stats.get("boss_kills", 0)),
		]
	)
	box.add_child(info)

	var btn := Button.new()
	btn.text = "返回主菜单"
	btn.custom_minimum_size = Vector2(220.0, 40.0)
	btn.pressed.connect(func() -> void: back_requested.emit())
	box.add_child(btn)
