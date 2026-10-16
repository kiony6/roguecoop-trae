extends Control
## 技能树页（子项目 5，复刻《生存代码》的节点体系）：三列节点卡（触发/动作/修饰）+ 前置连线，点击解锁。
## 双模式复用同一份脚本：
##   - 主菜单入口 = 独立页面（返回键回主菜单）；
##   - 对局内 = world.gd 挂到 HUD 的覆盖层（open()/close()，返回键收起面板）。
## 连线画在自身 _draw() 里：Control 先画自己再画子节点，天然位于卡片之下。

const Skills := preload("res://sim/skills.gd")
const Palette := preload("res://scripts/ui/theme/palette.gd")

const CARD_SIZE := Vector2(190.0, 44.0)
const COLUMN_MIN_WIDTH := 200.0
const LAYERS: Array = [
	Skills.LAYER_TRIGGER, Skills.LAYER_ACTION, Skills.LAYER_LOGIC, Skills.LAYER_MOD
]

var _overlay := false
var _points := 0
var _nodes: Array = []
var _cards := {}
var _points_label: Label
var _hint: Label
var _preset_row: HBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	Net.skill_state_changed.connect(_on_skill_state_changed)
	_refresh()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()  # 卡片位置随布局变动，连线每帧重算


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.BG, 0.94), true)
	_draw_links()


func open() -> void:
	## 覆盖层模式：展开面板。
	visible = true
	_refresh()


func close() -> void:
	visible = false


func setup_overlay() -> void:
	## 对局内覆盖层模式：返回键改为收起面板，而不是跳转主菜单。
	_overlay = true
	visible = false


# ---------------- 构建 ----------------


func _build() -> void:
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 24)
	root.add_theme_constant_override("margin_top", 16)
	root.add_theme_constant_override("margin_right", 24)
	root.add_theme_constant_override("margin_bottom", 16)
	add_child(root)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	root.add_child(col)

	col.add_child(_build_header())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	col.add_child(scroll)

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 18)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for layer in LAYERS:
		_build_column(grid, layer)

	_preset_row = HBoxContainer.new()
	_preset_row.add_theme_constant_override("separation", 8)
	col.add_child(_preset_row)
	_build_presets()

	_hint = Label.new()
	_hint.theme_type_variation = &"Caption"
	col.add_child(_hint)


func _build_header() -> HBoxContainer:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)

	var back := Button.new()
	back.theme_type_variation = &"TextButton"
	back.text = "← 返回"
	back.pressed.connect(_on_back)
	head.add_child(back)

	var title := Label.new()
	title.theme_type_variation = &"Title"
	title.text = "技能树"
	head.add_child(title)

	_points_label = Label.new()
	_points_label.theme_type_variation = &"Caption"
	head.add_child(_points_label)
	return head


func _build_column(grid: HBoxContainer, layer: int) -> void:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(COLUMN_MIN_WIDTH, 0.0)
	box.add_theme_constant_override("separation", 6)
	grid.add_child(box)

	var head := Label.new()
	head.theme_type_variation = &"Caption"
	head.text = _layer_name(layer)
	box.add_child(head)

	for n in Skills.nodes_of_layer(layer):
		var card := Button.new()
		card.custom_minimum_size = CARD_SIZE
		card.tooltip_text = str(n["desc"])
		card.pressed.connect(_on_card_pressed.bind(int(n["id"])))
		box.add_child(card)
		_cards[int(n["id"])] = card


func _build_presets() -> void:
	var label := Label.new()
	label.theme_type_variation = &"Caption"
	label.text = "初始构筑（会重置技能树）："
	_preset_row.add_child(label)
	for p in Skills.presets():
		var btn := Button.new()
		btn.theme_type_variation = &"TextButton"
		btn.text = str(p["name"])
		btn.tooltip_text = str(p["desc"])
		btn.pressed.connect(_on_preset_pressed.bind(String(p["id"])))
		_preset_row.add_child(btn)


# ---------------- 刷新 ----------------


func _refresh() -> void:
	var st: Dictionary = Net.local_skill_state()
	_points = int(st["points"])
	_nodes = Array(st["nodes"])
	_points_label.text = "技能点 %d" % _points
	for id in _cards:
		_refresh_card(int(id), _cards[int(id)])
	_preset_row.visible = Net.is_host()  # 换构筑只能在主机（自开服/单机）本地生效
	_hint.text = _hint_text()
	queue_redraw()


func _refresh_card(id: int, card: Button) -> void:
	var name := Skills.name_of(id)
	var cost := Skills.cost_of(id)
	var unlocked := _nodes.has(id)
	var can := Skills.can_unlock(_nodes, id, _points)
	card.disabled = not (unlocked or can)
	if unlocked:
		card.theme_type_variation = &"PrimaryButton"
		card.text = "%s ✔" % name
	elif can:
		card.theme_type_variation = &""
		card.text = "%s  [%d点]" % [name, cost]
	else:
		card.theme_type_variation = &""
		card.text = "%s  [锁定]" % name


func _hint_text() -> String:
	if Net.is_host():
		return "点击卡片消耗技能点解锁；升级获得技能点。解锁后技能会在对局中自动链式触发。"
	if Net.is_client():
		return "点击卡片消耗技能点解锁（由主机校验）；解锁后技能会在对局中自动链式触发。"
	return "当前未在对局中：技能点与解锁要在开局后可用；可先查看节点与初始构筑。"


func _draw_links() -> void:
	var inv := get_global_transform().affine_inverse()
	for n in Skills.all():
		var dst: Button = _cards.get(int(n["id"]))
		if dst == null:
			continue
		for req in n["requires"]:
			var src: Button = _cards.get(int(req))
			if src == null:
				continue
			var a: Vector2 = inv * _edge_point(src, 1.0)
			var b: Vector2 = inv * _edge_point(dst, -1.0)
			draw_line(a, b, _link_color(int(req), int(n["id"])), 2.0, true)


func _edge_point(card: Button, sign_x: float) -> Vector2:
	var r: Rect2 = card.get_global_rect()
	return Vector2(r.get_center().x + sign_x * r.size.x * 0.5, r.get_center().y)


func _link_color(req: int, node_id: int) -> Color:
	if _nodes.has(node_id):
		return Palette.PRIMARY
	if _nodes.has(req) and Skills.can_unlock(_nodes, node_id, _points):
		return Palette.ACCENT
	return Palette.BORDER


func _layer_name(layer: int) -> String:
	match layer:
		Skills.LAYER_TRIGGER:
			return "触发层 · 什么时候放"
		Skills.LAYER_ACTION:
			return "动作层 · 放什么"
		Skills.LAYER_LOGIC:
			return "条件/循环层 · 什么条件下放几次"
	return "修饰层 · 怎么强化"


# ---------------- 交互 ----------------


func _on_card_pressed(node_id: int) -> void:
	if not Skills.can_unlock(_nodes, node_id, _points):
		return
	Net.send_skill_unlock(node_id)
	_refresh()  # 客户端要等主机回包，回包会再触发一次刷新


func _on_preset_pressed(preset_id: String) -> void:
	Net.set_local_build(preset_id)
	_refresh()


func _on_skill_state_changed(_points: int, _nodes: PackedInt32Array) -> void:
	_refresh()


func _on_back() -> void:
	if _overlay:
		close()
		return
	get_tree().change_scene_to_file("res://scenes/main.tscn")
