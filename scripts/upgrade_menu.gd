extends Control
## 升级选卡面板（M3）。world.gd 收到 upgrade_offer 时调用 open(choices)。

signal picked(card_id: int)

const Progression := preload("res://sim/progression.gd")

var _locked := false


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func open(choices: PackedInt32Array) -> void:
	for c in get_children():
		c.queue_free()
	_locked = false
	visible = true

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.6)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var box := VBoxContainer.new()
	box.position = Vector2(440.0, 210.0)
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var title := Label.new()
	title.text = "升级！选择一项强化（只作用于你自己）"
	box.add_child(title)

	for cid in choices:
		var card := Progression.card_by_id(int(cid))
		var btn := Button.new()
		btn.text = str(card.get("name", "?"))
		btn.custom_minimum_size = Vector2(320.0, 44.0)
		btn.pressed.connect(_on_pick.bind(int(cid)))
		box.add_child(btn)


func _on_pick(card_id: int) -> void:
	if _locked:
		return
	_locked = true
	visible = false
	picked.emit(card_id)
