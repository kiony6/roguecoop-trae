extends RefCounted
## 全工程唯一直接操作磁盘的模块（spec §5.5）。
## accounts 结构：{"version": 1, "accounts": {"<lowername>": {"name","salt","verifier","created"}}}
## scores 结构：{"version": 1, "scores": {"<lowername>": {"name","wave","kills","seconds",
##   "boss_kills","at","by_difficulty":{...},"nodes":{...},"levels":{...}}}}
## 原子写：先写 .tmp → 主文件若存在则先改名成 .bak → 再把 .tmp 改名成主文件。
## 坏文件只在读路径降级（回退 .bak），不抛错、不删数据。

const VERSION := 1


static func load_accounts(path: String) -> Dictionary:
	return _load_library(path, "accounts")


static func save_accounts(path: String, accounts: Dictionary) -> Error:
	return _save_library(path, "accounts", accounts)


static func load_scores(path: String) -> Dictionary:
	return _load_library(path, "scores")


static func save_scores(path: String, scores: Dictionary) -> Error:
	return _save_library(path, "scores", scores)


static func _load_library(path: String, key: String) -> Dictionary:
	var data := _read_json(path)
	if int(data.get("version", 0)) != VERSION:
		data = _read_json(path + ".bak")
	if int(data.get("version", 0)) != VERSION:
		return {}
	var rows = data.get(key, {})
	if not (rows is Dictionary):
		return {}
	return rows


static func _save_library(path: String, key: String, rows: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var text := JSON.stringify({"version": VERSION, key: rows})
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	if FileAccess.file_exists(path):
		var bak := path + ".bak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(path, bak)
	return DirAccess.rename_absolute(tmp, path)


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	return parsed
