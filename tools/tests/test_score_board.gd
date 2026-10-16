extends RefCounted
## 双榜与关卡进度单测（子项目 6 任务 2）：
## 原子写与回读、按难度分档、并列比击杀、技能榜并列规则、仅记录在线局、
## R1 既有字段保留、通关解锁、坏文件回退 .bak。

const Harness := preload("res://tools/tests/harness.gd")
const ScoreBoard := preload("res://net/score_board.gd")
const Store := preload("res://disk/store.gd")
const Levels := preload("res://sim/levels.gd")

const PATH := "user://__test_scores.json"
const PATH_BAK := "user://__test_scores_bak.json"


func run() -> int:
	var t := Harness.new()
	_clean(PATH)
	_clean(PATH_BAK)

	# (1) 空库
	var sb := ScoreBoard.new(PATH)
	t.eq(sb.count(), 0, "空库 count 为 0")
	t.eq(sb.leaderboard_wave(Levels.DEFAULT_DIFFICULTY, 20).size(), 0, "空库波次榜为空")
	t.eq(sb.leaderboard_skill(20).size(), 0, "空库技能榜为空")
	t.check(not FileAccess.file_exists(PATH), "未写前不落盘")

	# (2) 仅在线局：空用户名拒绝且不落盘
	t.check(not sb.record("", 0, 1, 99, 99, 9.0, 9, 9, 1), "空用户名拒绝写入")
	t.check(not sb.record("   ", 0, 1, 99, 99, 9.0, 9, 9, 1), "纯空白用户名拒绝写入")
	t.eq(sb.count(), 0, "拒绝后 count 仍为 0")
	t.check(not FileAccess.file_exists(PATH), "拒绝后不落盘")

	# (3) 正常写入 + 回读
	t.check(sb.record("Alice", 0, 1, 12, 140, 310.5, 4, 7, 1000), "Alice 写入成功")
	t.eq(sb.count(), 1, "落库 1 人")
	t.check(not FileAccess.file_exists(PATH + ".tmp"), "原子写不残留 .tmp")
	var round_trip := ScoreBoard.new(PATH)
	var w := round_trip.leaderboard_wave(1, 20)
	t.eq(w.size(), 1, "普通档 1 行")
	t.eq(String(w[0]["username"]), "Alice", "玩家名")
	t.eq(int(w[0]["wave"]), 12, "最高波次")
	t.eq(int(w[0]["kills"]), 140, "击杀")
	t.check(absf(float(w[0]["seconds"]) - 310.5) < 0.001, "存活时长")
	t.eq(int(w[0]["boss_kills"]), 4, "Boss 数")

	# (4) 分档：不同难度互不覆盖
	t.check(sb.record("Alice", 0, 4, 9, 50, 100.0, 1, 3, 1002), "地狱档写入成功")
	var hell := sb.leaderboard_wave(4, 20)
	t.eq(int(hell[0]["wave"]), 9, "地狱档波次 9")
	t.eq(int(sb.leaderboard_wave(1, 20)[0]["wave"]), 12, "普通档仍是 12")
	t.eq(sb.leaderboard_wave(2, 20).size(), 0, "未打过的难度为空档")

	# (5) R1 既有字段保留 + 新增字段结构
	var raw := Store.load_scores(PATH)
	var rec: Dictionary = raw["alice"]
	t.eq(int(rec["wave"]), 12, "既有字段 wave 保留（= 默认难度）")
	t.eq(int(rec["kills"]), 140, "既有字段 kills 保留")
	t.check(absf(float(rec["seconds"]) - 310.5) < 0.001, "既有字段 seconds 保留")
	t.eq(int(rec["boss_kills"]), 4, "既有字段 boss_kills 保留")
	t.check(rec.has("at"), "既有字段 at 保留")
	t.eq(int(rec["by_difficulty"]["1"]["wave"]), 12, "新增 by_difficulty 普通档")
	t.eq(int(rec["by_difficulty"]["4"]["wave"]), 9, "新增 by_difficulty 地狱档")
	t.eq(int(rec["nodes"]["count"]), 7, "新增 nodes 记录")
	t.eq(int(rec["levels"]["cleared"][0]), 0, "通关关卡 0 解锁")
	t.eq(int(rec["levels"]["best_wave"]["0"]), 12, "关卡 0 最佳波次")

	# (6) 低于既有最佳不覆盖
	t.check(sb.record("Alice", 0, 1, 5, 400, 50.0, 0, 2, 1003), "低分局写入成功")
	var raw2 := Store.load_scores(PATH)
	t.eq(int(sb.leaderboard_wave(1, 20)[0]["wave"]), 12, "低波次不覆盖最佳")
	t.eq(int(sb.leaderboard_wave(1, 20)[0]["kills"]), 140, "同日低击杀不覆盖")
	t.eq(int(raw2["alice"]["nodes"]["count"]), 7, "低节点数不覆盖技能榜")
	t.eq(int(raw2["alice"]["levels"]["best_wave"]["0"]), 12, "低波次不覆盖关卡最佳")

	# (7) 并列比击杀：波次相同时击杀高者在前
	t.check(sb.record("Bob", 0, 1, 12, 200, 300.0, 2, 3, 1004), "Bob 写入")
	t.check(sb.record("Cara", 0, 1, 12, 100, 300.0, 2, 9, 1005), "Cara 写入")
	var order := sb.leaderboard_wave(1, 20)
	t.eq(order.size(), 3, "普通档 3 行")
	t.eq(String(order[0]["username"]), "Bob", "并列同波次击杀高者第一")
	t.eq(String(order[1]["username"]), "Alice", "击杀次高者第二")
	t.eq(String(order[2]["username"]), "Cara", "击杀最低者第三")

	# (8) 技能榜：节点数优先，并列比波次
	t.check(sb.record("Dave", 1, 3, 15, 80, 200.0, 3, 7, 1006), "Dave 写入（噩梦档）")
	var skill := sb.leaderboard_skill(20)
	t.eq(skill.size(), 4, "技能榜 4 行")
	t.eq(String(skill[0]["username"]), "Cara", "节点数 9 第一")
	t.eq(int(skill[0]["nodes"]), 9, "Cara 节点数")
	t.eq(String(skill[1]["username"]), "Dave", "同为 7 节点、波次高者在前")
	t.eq(int(skill[1]["wave"]), 15, "Dave 波次")
	t.eq(String(skill[2]["username"]), "Alice", "同为 7 节点、波次次者第三")
	t.eq(String(skill[3]["username"]), "Bob", "3 节点垫底")

	# (9) 关卡进度
	var prog := sb.progress_of("Alice")
	t.eq(prog["cleared"].size(), 1, "Alice 通关 1 关")
	t.eq(int(prog["cleared"][0]), 0, "通关关卡 0")
	t.eq(prog["best_wave"].size(), Levels.level_count(), "best_wave 长度 = 关卡数")
	t.eq(int(prog["best_wave"][0]), 12, "关卡 0 最佳波次 12")
	t.eq(int(prog["best_wave"][1]), 0, "关卡 1 未打过为 0")
	var none := sb.progress_of("Nobody")
	t.eq(none["cleared"].size(), 0, "未登录过的人无进度")
	t.eq(int(none["best_wave"][0]), 0, "无进度最佳波次为 0")
	t.check(sb.record("Erin", 2, 1, 16, 10, 10.0, 0, 1, 1007), "Erin 写入成功")
	t.eq(int(sb.progress_of("Erin")["cleared"][0]), 2, "到达通关波次即解锁区域 3")

	# (10) 坏文件回退 .bak
	_clean(PATH_BAK)
	var bak_sb := ScoreBoard.new(PATH_BAK)
	bak_sb.record("Frank", 0, 1, 7, 30, 60.0, 0, 1, 1008)
	bak_sb.record("Frank", 0, 1, 8, 40, 70.0, 1, 2, 1009)
	var f := FileAccess.open(PATH_BAK, FileAccess.WRITE)
	f.store_string("{ 坏文件")
	f.close()
	var recovered := ScoreBoard.new(PATH_BAK)
	t.eq(recovered.count(), 1, "坏主文件回退 .bak 保住数据")
	t.eq(int(recovered.leaderboard_wave(1, 20)[0]["wave"]), 7, "回退到上一次写入的值")

	_clean(PATH)
	_clean(PATH_BAK)
	return t.report("ScoreBoard")


func _clean(path: String) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
