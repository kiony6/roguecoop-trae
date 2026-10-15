extends RefCounted
## 磁盘持久化测试：原子写 / .bak 备份 / 坏主文件回退。落盘位置在 user://（工程目录外，零污染）。

const Harness := preload("res://tools/tests/harness.gd")
const Store := preload("res://disk/store.gd")

const DIR := "user://test_store_tmp"
const PATH := DIR + "/accounts.json"


func run() -> int:
	var t := Harness.new()
	_cleanup()
	DirAccess.make_dir_recursive_absolute(DIR)

	# (1) 文件不存在 → 空表
	t.eq(Store.load_accounts(PATH), {}, "文件不存在时返回空表")

	# (2) 首次保存
	var acc := {"alice": {"name": "Alice", "salt": "AAA=", "verifier": "BBB=", "created": 123}}
	t.eq(Store.save_accounts(PATH, acc), OK, "首次保存成功")
	t.eq(Store.load_accounts(PATH).size(), 1, "保存后可读回 1 条")
	t.eq(String(Store.load_accounts(PATH)["alice"]["verifier"]), "BBB=", "读回字段一致")
	t.check(not FileAccess.file_exists(PATH + ".tmp"), "原子写后无 .tmp 残留")

	# (3) 二次保存 → 生成 .bak
	acc["bob"] = {"name": "Bob", "salt": "CCC=", "verifier": "DDD=", "created": 456}
	t.eq(Store.save_accounts(PATH, acc), OK, "二次保存成功")
	t.check(FileAccess.file_exists(PATH + ".bak"), "二次保存生成 .bak")
	t.eq(Store.load_accounts(PATH).size(), 2, "二次保存后 2 条")

	# (4) 主文件写坏 → 回退 .bak（.bak 里是第一次保存的内容，只有 alice）
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("{ not json at all")
	f.close()
	var recovered := Store.load_accounts(PATH)
	t.check(recovered.has("alice"), "坏主文件回退 .bak 读到旧数据")
	t.check(not recovered.has("bob"), "回退读到的是备份时的快照")

	_cleanup()
	return t.report("Store")


func _cleanup() -> void:
	for p in [PATH, PATH + ".tmp", PATH + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
