extends Node
## 单元测试入口。以场景方式运行，避免 --script 与 autoload 的兼容性问题。

const SUITES: Array = [
	preload("res://tools/tests/test_protocol_input.gd"),
	preload("res://tools/tests/test_protocol_snapshot.gd"),
	preload("res://tools/tests/test_movement.gd"),
	preload("res://tools/tests/test_interp.gd"),
	preload("res://tools/tests/test_combat.gd"),
	preload("res://tools/tests/test_weapons.gd"),
	preload("res://tools/tests/test_rooms.gd"),
	preload("res://tools/tests/test_waves.gd"),
	preload("res://tools/tests/test_progression.gd"),
	preload("res://tools/tests/test_enemy_ai.gd"),
	preload("res://tools/tests/test_aoi.gd"),
	preload("res://tools/tests/test_net_host_combat.gd"),
	preload("res://tools/tests/test_net_transport.gd"),
]


func _ready() -> void:
	var failed := 0
	for suite_script in SUITES:
		failed += suite_script.new().run()
	if failed == 0:
		print("[UnitTests] ALL PASS")
		get_tree().quit(0)
	else:
		printerr("[UnitTests] FAILED=%d" % failed)
		get_tree().quit(1)
