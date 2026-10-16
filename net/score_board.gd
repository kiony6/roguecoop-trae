extends RefCounted
## 双榜与关卡进度的纯逻辑 + 落盘（子项目 6）。
## 唯一碰盘路径经 disk/store.gd（.tmp → .bak → rename 原子写）。
## - 波次榜：按难度分档的历史最佳波次，并列比击杀
## - 技能榜：已解锁节点数，并列比最高波次（再并列比击杀）
## - 关卡进度：cleared 关卡集合 + 各关最佳波次
## 仅记录「经大厅的在线局」：用户名为空一律拒绝写入（不落盘）。

const Store := preload("res://disk/store.gd")
const Levels := preload("res://sim/levels.gd")

const DEFAULT_PATH := "user://scores.json"
const TOP_N := 20

var _path: String
var _scores: Dictionary = {}


func _init(path := DEFAULT_PATH) -> void:
	_path = path
	load_from_disk()


func load_from_disk() -> void:
	_scores = Store.load_scores(_path)
	_normalize()


func save_to_disk() -> Error:
	return Store.save_scores(_path, _scores)


func path() -> String:
	return _path


func count() -> int:
	return _scores.size()


func has_user(username: String) -> bool:
	return _scores.has(_key(username))


## 写入一局成绩。返回是否真的落盘（空用户名一律拒绝）。
func record(
	username: String,
	level_id: int,
	difficulty_id: int,
	wave: int,
	kills: int,
	seconds: float,
	boss_kills: int,
	nodes: int,
	at: int
) -> bool:
	var key := _key(username)
	if key.is_empty():
		return false
	var rec: Dictionary = _scores.get(key, {})
	rec["name"] = username.strip_edges()
	var entry := {
		"wave": maxi(wave, 1),
		"kills": maxi(kills, 0),
		"seconds": maxf(seconds, 0.0),
		"boss_kills": maxi(boss_kills, 0),
		"level": level_id,
		"at": at
	}
	# 各难度分档最佳
	var by_diff: Dictionary = rec.get("by_difficulty", {})
	var dk := str(difficulty_id)
	if _better(entry, by_diff.get(dk, {})):
		by_diff[dk] = entry
	rec["by_difficulty"] = by_diff
	# R1 既有字段：恒表示默认难度（普通）的历史最佳
	var top: Dictionary = rec
	if difficulty_id == Levels.DEFAULT_DIFFICULTY and _better(entry, top):
		for k in entry:
			rec[k] = entry[k]
	# 技能榜：节点数优先，并列比波次（再并列比击杀）
	var nrec: Dictionary = rec.get("nodes", {})
	if _better_nodes(nodes, entry, nrec):
		rec["nodes"] = {
			"count": maxi(nodes, 0),
			"wave": entry["wave"],
			"kills": entry["kills"],
			"level": level_id,
			"at": at
		}
	# 关卡进度：到达通关波次即解锁该关
	var prog: Dictionary = rec.get("levels", {})
	var cleared: Array = prog.get("cleared", [])
	var best: Dictionary = prog.get("best_wave", {})
	var lk := str(level_id)
	best[lk] = maxi(int(best.get(lk, 0)), entry["wave"])
	if not cleared.has(level_id) and int(entry["wave"]) >= Levels.clear_wave(level_id):
		cleared.append(level_id)
		cleared.sort()
	prog["cleared"] = cleared
	prog["best_wave"] = best
	rec["levels"] = prog
	_scores[key] = rec
	save_to_disk()
	return true


## 波次榜：按难度筛选，默认 n = 20。并列比击杀，再按用户名升序保证确定性。
func leaderboard_wave(difficulty_id: int, n := TOP_N) -> Array:
	var rows: Array = []
	var dk := str(difficulty_id)
	for key in _scores:
		var rec: Dictionary = _scores[key]
		var entry: Dictionary = {}
		var by_diff: Dictionary = rec.get("by_difficulty", {})
		if by_diff.has(dk):
			entry = by_diff[dk]
		elif difficulty_id == Levels.DEFAULT_DIFFICULTY and rec.has("wave"):
			entry = rec
		if entry.is_empty():
			continue
		rows.append(
			{
				"username": _display_name(rec, key),
				"wave": int(entry.get("wave", 0)),
				"kills": int(entry.get("kills", 0)),
				"seconds": float(entry.get("seconds", 0.0)),
				"boss_kills": int(entry.get("boss_kills", 0))
			}
		)
	rows.sort_custom(_sort_wave)
	return rows.slice(0, maxi(n, 0))


## 技能榜：解锁节点数降序，并列比最高波次（再并列比击杀）。
func leaderboard_skill(n := TOP_N) -> Array:
	var rows: Array = []
	for key in _scores:
		var rec: Dictionary = _scores[key]
		var entry: Dictionary = rec.get("nodes", {})
		if entry.is_empty():
			continue
		rows.append(
			{
				"username": _display_name(rec, key),
				"nodes": int(entry.get("count", 0)),
				"wave": int(entry.get("wave", 0)),
				"kills": int(entry.get("kills", 0))
			}
		)
	rows.sort_custom(_sort_skill)
	return rows.slice(0, maxi(n, 0))


## 关卡进度：cleared 为已通关关卡 id 数组，best_wave 下标即关卡 id（长度 = 关卡数）。
func progress_of(username: String) -> Dictionary:
	var rec: Dictionary = _scores.get(_key(username), {})
	var prog: Dictionary = rec.get("levels", {})
	var best: Dictionary = prog.get("best_wave", {})
	var out := PackedInt32Array()
	out.resize(Levels.level_count())
	out.fill(0)
	for i in range(Levels.level_count()):
		out[i] = int(best.get(str(i), 0))
	return {"cleared": _cleared_of(rec), "best_wave": out}


func _cleared_of(rec: Dictionary) -> PackedInt32Array:
	var prog: Dictionary = rec.get("levels", {})
	var out := PackedInt32Array()
	for v in prog.get("cleared", []):
		var id := int(v)
		if Levels.is_valid_level(id) and not out.has(id):
			out.append(id)
	out.sort()
	return out


func _normalize() -> void:
	for key in _scores:
		var rec = _scores[key]
		if not (rec is Dictionary):
			continue
		var prog = rec.get("levels", null)
		if prog is Dictionary and prog.has("cleared"):
			var fixed := PackedInt32Array()
			for v in prog["cleared"]:
				fixed.append(int(v))
			prog["cleared"] = fixed
			rec["levels"] = prog


static func _better(entry: Dictionary, prev: Dictionary) -> bool:
	var wave := int(entry.get("wave", 0))
	var pw := int(prev.get("wave", -1))
	if wave != pw:
		return wave > pw
	return int(entry.get("kills", 0)) > int(prev.get("kills", -1))


static func _better_nodes(nodes: int, entry: Dictionary, prev: Dictionary) -> bool:
	var pn := int(prev.get("count", -1))
	if nodes != pn:
		return nodes > pn
	var wave := int(entry.get("wave", 0))
	var pw := int(prev.get("wave", -1))
	if wave != pw:
		return wave > pw
	return int(entry.get("kills", 0)) > int(prev.get("kills", -1))


static func _sort_wave(a: Dictionary, b: Dictionary) -> bool:
	if int(a["wave"]) != int(b["wave"]):
		return int(a["wave"]) > int(b["wave"])
	if int(a["kills"]) != int(b["kills"]):
		return int(a["kills"]) > int(b["kills"])
	return String(a["username"]) < String(b["username"])


static func _sort_skill(a: Dictionary, b: Dictionary) -> bool:
	if int(a["nodes"]) != int(b["nodes"]):
		return int(a["nodes"]) > int(b["nodes"])
	if int(a["wave"]) != int(b["wave"]):
		return int(a["wave"]) > int(b["wave"])
	if int(a["kills"]) != int(b["kills"]):
		return int(a["kills"]) > int(b["kills"])
	return String(a["username"]) < String(b["username"])


static func _display_name(rec: Dictionary, key: String) -> String:
	return String(rec.get("name", key))


static func _key(username: String) -> String:
	return username.strip_edges().to_lower()
