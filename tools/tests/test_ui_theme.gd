extends RefCounted
## UI 主题测试：断言调色板 11 色与 4 档字号。

const Harness := preload("res://tools/tests/harness.gd")
const Palette := preload("res://scripts/ui/theme/palette.gd")
const UiTheme := preload("res://scripts/ui/theme/ui_theme.gd")


func run() -> int:
	var t := Harness.new()

	t.eq(Palette.BG, Color("#2a3550"), "BG = 夜幕蓝底色")
	t.eq(Palette.SURFACE, Color("#3d4d70"), "SURFACE = 面板/卡片底")
	t.eq(Palette.BORDER, Color("#5566aa"), "BORDER = 边框")
	t.eq(Palette.PRIMARY, Color("#4aa3ff"), "PRIMARY = 焦点/主色")
	t.eq(Palette.ACCENT, Color("#ffd93d"), "ACCENT = 强调")
	t.eq(Palette.DANGER, Color("#b23b3b"), "DANGER = 危险")

	t.eq(Palette.TEXT, Color("#e8eefb"), "TEXT = 正文")
	t.eq(Palette.TEXT_MUTED, Color("#8b9bc4"), "TEXT_MUTED = 次要文字/占位")
	t.eq(Palette.ON_PRIMARY, Color("#0e1524"), "ON_PRIMARY = 主色按钮上的字")
	t.eq(Palette.SURFACE_HOVER, Color("#46587f"), "SURFACE_HOVER = 悬停底")
	t.eq(Palette.SURFACE_PRESSED, Color("#2f3a57"), "SURFACE_PRESSED = 按下底")

	t.eq(_color_const_count(), 11, "调色板色常量恰为 11 个（不再新增）")

	t.eq(Palette.FONT_CODE, 48, "字号 48 = 组队码")
	t.eq(Palette.FONT_TITLE, 36, "字号 36 = 页面标题")
	t.eq(Palette.FONT_BODY, 24, "字号 24 = 正文/按钮/表格")
	t.eq(Palette.FONT_CAPTION, 12, "字号 12 = 说明/角标")
	var sizes: Array = [
		Palette.FONT_CODE, Palette.FONT_TITLE, Palette.FONT_BODY, Palette.FONT_CAPTION
	]
	for size in sizes:
		t.eq(size % 12, 0, "字号 %d 是 12 的整数倍" % size)

	_assert_theme(t)

	return t.report("UiTheme")


func _color_const_count() -> int:
	var n := 0
	var palette_script: GDScript = Palette
	for v in palette_script.get_script_constant_map().values():
		if v is Color:
			n += 1
	return n


func _assert_theme(t: Harness) -> void:
	var th := UiTheme.build()
	t.check(th.default_font != null, "主题已挂载字体（load_dynamic_font 成功）")
	t.eq(th.default_font_size, 24, "主题默认字号 = 24")
	t.eq(UiTheme.VARIATIONS.size(), 7, "类型变体恰为 7 个")
	for variant in UiTheme.VARIATIONS:
		t.eq(
			String(th.get_type_variation_base(variant)),
			UiTheme.VARIATIONS[variant],
			"变体 %s 基类正确" % variant
		)

	t.eq(th.get_font_size("font_size", "Title"), 36, "Title 字号 = 36")
	t.eq(th.get_color("font_color", "Title"), Palette.PRIMARY, "Title 字色 = PRIMARY")
	t.eq(th.get_font_size("font_size", "Code"), 48, "Code 字号 = 48")
	t.eq(th.get_color("font_color", "Code"), Palette.ACCENT, "Code 字色 = ACCENT")
	t.eq(th.get_font_size("font_size", "Caption"), 12, "Caption 字号 = 12")
	t.eq(th.get_color("font_color", "Caption"), Palette.TEXT_MUTED, "Caption 字色 = TEXT_MUTED")

	var sb_normal := th.get_stylebox("normal", "Button") as StyleBoxFlat
	t.eq(sb_normal.bg_color, Palette.SURFACE, "按钮常态底 = SURFACE")
	t.eq(sb_normal.border_color, Palette.BORDER, "按钮常态边 = BORDER")
	t.eq(sb_normal.border_width_left, 2, "按钮边框 2px")
	t.eq(sb_normal.corner_radius_top_left, 0, "按钮直角（radius 0）")
	t.eq(sb_normal.anti_aliasing, false, "StyleBox 关抗锯齿")
	var sb_hover := th.get_stylebox("hover", "Button") as StyleBoxFlat
	t.eq(sb_hover.bg_color, Palette.SURFACE_HOVER, "按钮悬停底 = SURFACE_HOVER")
	t.eq(sb_hover.border_color, Palette.PRIMARY, "按钮悬停边 = PRIMARY")
	var sb_focus := th.get_stylebox("focus", "Button") as StyleBoxFlat
	t.eq(sb_focus.border_width_left, 3, "按钮焦点边框 3px")

	var sb_primary := th.get_stylebox("normal", "PrimaryButton") as StyleBoxFlat
	t.eq(sb_primary.bg_color, Palette.PRIMARY, "主按钮底 = PRIMARY")
	t.eq(th.get_color("font_color", "PrimaryButton"), Palette.ON_PRIMARY, "主按钮字 = ON_PRIMARY")
	var sb_danger := th.get_stylebox("normal", "DangerButton") as StyleBoxFlat
	t.eq(sb_danger.bg_color, Palette.DANGER, "危险按钮底 = DANGER")

	for state in ["normal", "hover", "pressed", "focus"]:
		t.check(
			th.get_stylebox(state, "TextButton") is StyleBoxEmpty, "文字按钮 %s = StyleBoxEmpty" % state
		)
	t.eq(th.get_color("font_color", "TextButton"), Palette.TEXT_MUTED, "文字按钮常态字 = TEXT_MUTED")
	t.eq(th.get_color("font_hover_color", "TextButton"), Palette.PRIMARY, "文字按钮悬停字 = PRIMARY")

	var sb_edit := th.get_stylebox("normal", "LineEdit") as StyleBoxFlat
	t.eq(sb_edit.bg_color, Palette.BG, "输入框底 = BG")
	t.eq(
		th.get_color("font_placeholder_color", "LineEdit"), Palette.TEXT_MUTED, "输入框占位 = TEXT_MUTED"
	)

	var sb_card := th.get_stylebox("panel", "Card") as StyleBoxFlat
	t.eq(sb_card.content_margin_left, 32.0, "卡片内边距 = 32")
	var sb_panel := th.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	t.eq(sb_panel.content_margin_left, 24.0, "面板内边距 = 24")
