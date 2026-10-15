extends RefCounted
## 甲·夜幕蓝全局主题：纯代码构建（单一事实源、可被无头单测断言）。
## 由 autoload/boot.gd 在 _ready() 里挂到 Window.theme，向下传播到所有 Control（含 world.tscn 的 HUD）。

const Palette := preload("res://scripts/ui/theme/palette.gd")

## 字体走运行时读盘：本仓库无 .godot 导入缓存，load()/preload() 必然失败。
const FONT_PATH := "res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.ttf"

## Theme 里必须注册的 7 个类型变体：变体名 -> 基类。
## TextButton 是自定义变体名（不与任何内置控件类同名），节点上写
## theme_type_variation = &"TextButton" 即可按此名解析到下面的样式。
const VARIATIONS := {
	"Title": "Label",
	"Code": "Label",
	"Caption": "Label",
	"Card": "PanelContainer",
	"PrimaryButton": "Button",
	"DangerButton": "Button",
	"TextButton": "Button",
}

const _PAD_PANEL := 24
const _PAD_CARD := 32
const _PAD_CONTROL := 12
const _BORDER_W := 2
const _BORDER_W_FOCUS := 3
const _TEXT_STATES: Array = ["normal", "hover", "pressed", "focus"]


static func build() -> Theme:
	var th := Theme.new()
	th.default_font = _pixel_font()
	th.default_font_size = Palette.FONT_BODY
	_build_label(th)
	_build_panel(th)
	_build_button(th)
	_build_line_edit(th)
	_build_variations(th)
	return th


static func _pixel_font() -> FontFile:
	var f := FontFile.new()
	if f.load_dynamic_font(FONT_PATH) != OK:
		push_error("UiTheme: 无法加载像素字体 %s" % FONT_PATH)
		return null
	# 像素字体必须：关抗锯齿、关 hinting、关子像素定位，否则非整数缩放发虚。
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.multichannel_signed_distance_field = false
	f.allow_system_fallback = false
	return f


static func _flat(bg: Color, border: Color, width: int, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(0)  # 直角像素风
	sb.anti_aliasing = false
	sb.set_content_margin_all(pad)
	return sb


static func _empty() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


static func _build_label(th: Theme) -> void:
	th.set_color("font_color", "Label", Palette.TEXT)


static func _build_panel(th: Theme) -> void:
	var sb := _flat(Palette.SURFACE, Palette.BORDER, _BORDER_W, _PAD_PANEL)
	th.set_stylebox("panel", "PanelContainer", sb)


static func _build_button(th: Theme) -> void:
	th.set_stylebox(
		"normal", "Button", _flat(Palette.SURFACE, Palette.BORDER, _BORDER_W, _PAD_CONTROL)
	)
	th.set_stylebox(
		"hover", "Button", _flat(Palette.SURFACE_HOVER, Palette.PRIMARY, _BORDER_W, _PAD_CONTROL)
	)
	th.set_stylebox(
		"pressed",
		"Button",
		_flat(Palette.SURFACE_PRESSED, Palette.PRIMARY, _BORDER_W, _PAD_CONTROL)
	)
	th.set_stylebox(
		"focus", "Button", _flat(Palette.SURFACE, Palette.PRIMARY, _BORDER_W_FOCUS, _PAD_CONTROL)
	)
	var disabled := _flat(Palette.SURFACE, Palette.BORDER, _BORDER_W, _PAD_CONTROL)
	disabled.border_color.a = 0.5
	disabled.bg_color.a = 0.5
	th.set_stylebox("disabled", "Button", disabled)
	th.set_color("font_color", "Button", Palette.TEXT)
	th.set_color("font_hover_color", "Button", Palette.PRIMARY)
	th.set_color("font_pressed_color", "Button", Palette.PRIMARY)
	th.set_color("font_focus_color", "Button", Palette.PRIMARY)
	th.set_color("font_disabled_color", "Button", Palette.TEXT_MUTED)


static func _build_line_edit(th: Theme) -> void:
	th.set_stylebox(
		"normal", "LineEdit", _flat(Palette.BG, Palette.BORDER, _BORDER_W, _PAD_CONTROL)
	)
	th.set_stylebox(
		"focus", "LineEdit", _flat(Palette.BG, Palette.PRIMARY, _BORDER_W_FOCUS, _PAD_CONTROL)
	)
	th.set_color("font_color", "LineEdit", Palette.TEXT)
	th.set_color("font_placeholder_color", "LineEdit", Palette.TEXT_MUTED)
	th.set_color("caret_color", "LineEdit", Palette.PRIMARY)
	th.set_color("selection_color", "LineEdit", Palette.PRIMARY)


static func _build_variations(th: Theme) -> void:
	for variant in VARIATIONS:
		th.set_type_variation(variant, VARIATIONS[variant])

	th.set_font_size("font_size", "Title", Palette.FONT_TITLE)
	th.set_color("font_color", "Title", Palette.PRIMARY)

	th.set_font_size("font_size", "Code", Palette.FONT_CODE)
	th.set_color("font_color", "Code", Palette.ACCENT)

	th.set_font_size("font_size", "Caption", Palette.FONT_CAPTION)
	th.set_color("font_color", "Caption", Palette.TEXT_MUTED)

	th.set_stylebox("panel", "Card", _flat(Palette.SURFACE, Palette.BORDER, _BORDER_W, _PAD_CARD))

	th.set_stylebox(
		"normal", "PrimaryButton", _flat(Palette.PRIMARY, Palette.PRIMARY, _BORDER_W, _PAD_CONTROL)
	)
	th.set_stylebox(
		"hover", "PrimaryButton", _flat(Palette.PRIMARY, Palette.ACCENT, _BORDER_W, _PAD_CONTROL)
	)
	th.set_stylebox(
		"pressed", "PrimaryButton", _flat(Palette.PRIMARY, Palette.ACCENT, _BORDER_W, _PAD_CONTROL)
	)
	th.set_stylebox(
		"focus",
		"PrimaryButton",
		_flat(Palette.PRIMARY, Palette.ACCENT, _BORDER_W_FOCUS, _PAD_CONTROL)
	)
	th.set_stylebox(
		"disabled", "PrimaryButton", _flat(Palette.SURFACE, Palette.BORDER, _BORDER_W, _PAD_CONTROL)
	)
	th.set_color("font_color", "PrimaryButton", Palette.ON_PRIMARY)
	th.set_color("font_hover_color", "PrimaryButton", Palette.ON_PRIMARY)
	th.set_color("font_pressed_color", "PrimaryButton", Palette.ON_PRIMARY)
	th.set_color("font_focus_color", "PrimaryButton", Palette.ON_PRIMARY)
	th.set_color("font_disabled_color", "PrimaryButton", Palette.TEXT_MUTED)

	th.set_stylebox(
		"normal", "DangerButton", _flat(Palette.DANGER, Palette.DANGER, _BORDER_W, _PAD_CONTROL)
	)
	th.set_stylebox(
		"hover", "DangerButton", _flat(Palette.DANGER, Palette.ACCENT, _BORDER_W, _PAD_CONTROL)
	)
	th.set_stylebox(
		"pressed", "DangerButton", _flat(Palette.DANGER, Palette.ACCENT, _BORDER_W, _PAD_CONTROL)
	)
	th.set_stylebox(
		"focus",
		"DangerButton",
		_flat(Palette.DANGER, Palette.ACCENT, _BORDER_W_FOCUS, _PAD_CONTROL)
	)
	th.set_color("font_color", "DangerButton", Palette.TEXT)
	th.set_color("font_hover_color", "DangerButton", Palette.TEXT)
	th.set_color("font_pressed_color", "DangerButton", Palette.TEXT)
	th.set_color("font_focus_color", "DangerButton", Palette.TEXT)

	for state in _TEXT_STATES:
		th.set_stylebox(state, "TextButton", _empty())
	th.set_color("font_color", "TextButton", Palette.TEXT_MUTED)
	th.set_color("font_hover_color", "TextButton", Palette.PRIMARY)
	th.set_color("font_pressed_color", "TextButton", Palette.PRIMARY)
	th.set_color("font_focus_color", "TextButton", Palette.PRIMARY)
