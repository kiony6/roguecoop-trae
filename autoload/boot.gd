extends Node
## 启动引导：运行期注册 InputMap，并记录「启动期一次性直连意图」。
## 这样可避免手写 project.godot 里冗长的 InputEventKey 字面量。

const UiTheme := preload("res://scripts/ui/theme/ui_theme.gd")

const ACTIONS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"fire": [KEY_J],
	"dash": [KEY_K],
}

## 启动期一次性意图：仅当命令行显式要求 `--auto=join` 时为 true（`--ip=` / `--port=` / `--transport=` 只作预填，不劫持主菜单）。
## 由主菜单首帧消费并直达直连页；若进程本就以直连页启动，则由直连页消费，
## 从而保证此后「← 返回主菜单」不会再被弹回直连页。
var auto_join_pending := false


func _ready() -> void:
	get_window().theme = UiTheme.build()
	auto_join_pending = _wants_auto_join()
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for keycode in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)

	if not InputMap.has_action("fire"):
		InputMap.add_action("fire", 0.2)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("fire", mb)


func _wants_auto_join() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--auto=") and a.substr(7) == "join":
			return true
	return false


func take_auto_join_pending() -> bool:
	var pending := auto_join_pending
	auto_join_pending = false
	return pending
