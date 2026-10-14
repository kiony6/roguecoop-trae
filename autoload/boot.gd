extends Node
## 启动引导：运行期注册 InputMap。
## 这样可避免手写 project.godot 里冗长的 InputEventKey 字面量。

const ACTIONS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"fire": [KEY_J],
	"dash": [KEY_K],
}


func _ready() -> void:
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
